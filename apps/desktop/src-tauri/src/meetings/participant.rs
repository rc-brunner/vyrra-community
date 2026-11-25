use super::{Event, Profile, Result};
use base64::{Engine, engine::general_purpose::STANDARD};
use image::{ImageFormat, ImageReader, imageops::FilterType};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::Cursor, path::Path, time::Duration};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use url::Url;

pub fn address(raw: &str) -> Result<String> {
    let u = Url::parse(raw.trim()).map_err(|_| "Enter the address of your Attendee server.")?;
    let local = matches!(u.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"));
    if u.host_str().is_none()
        || !(u.scheme() == "https" || (local && u.scheme() == "http"))
        || u.path() != "/"
        || !u.username().is_empty()
        || u.password().is_some()
        || u.query().is_some()
        || u.fragment().is_some()
    {
        return Err("Use your server’s HTTPS origin, or HTTP on localhost.");
    }
    Ok(u.origin().ascii_serialization())
}
pub fn picture(path: &Path) -> Result<String> {
    if path
        .metadata()
        .map_err(|_| "The picture could not be opened.")?
        .len()
        > 12 * 1024 * 1024
    {
        return Err("Choose a picture smaller than 12 MB.");
    }
    let mut reader = ImageReader::open(path)
        .map_err(|_| "The picture could not be opened.")?
        .with_guessed_format()
        .map_err(|_| "Choose a PNG or JPEG picture.")?;
    if !matches!(reader.format(), Some(ImageFormat::Png | ImageFormat::Jpeg)) {
        return Err("Choose a PNG or JPEG picture.");
    }
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(10000);
    limits.max_image_height = Some(10000);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let image = reader
        .decode()
        .map_err(|_| "The picture is too large or could not be decoded.")?
        .resize_to_fill(256, 256, FilterType::Lanczos3);
    let mut buf = Cursor::new(Vec::new());
    image
        .write_to(&mut buf, ImageFormat::Png)
        .map_err(|_| "The picture could not be prepared.")?;
    Ok(STANDARD.encode(buf.into_inner()))
}
pub fn avatar(profile: &Profile) -> String {
    profile
        .image
        .clone()
        .unwrap_or_else(|| STANDARD.encode(include_bytes!("../../icons/128x128.png")))
}
fn entry(server: &str) -> Result<keyring::Entry> {
    keyring::Entry::new("com.runnerconcepts.vyrra.meetings", server)
        .map_err(|_| "The system credential store is unavailable.")
}
pub fn save_key(server: &str, token: &str) -> Result<()> {
    if token.is_empty() || token.len() > 2048 || !token.bytes().all(|b| b.is_ascii_graphic()) {
        return Err("Choose a text file containing only the server API key.");
    }
    entry(server)?
        .set_password(token)
        .map_err(|_| "The key could not be saved in the system credential store.")
}
fn request(
    server: &str,
    token: &str,
    method: &str,
    route: &str,
    body: Option<Value>,
) -> Result<Value> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .max_redirects(0)
        .timeout_global(Some(Duration::from_secs(12)))
        .build()
        .into();
    let url = format!("{server}/api/v1/bots{route}");
    let auth = format!("Token {token}");
    let response = match method {
        "GET" => agent.get(&url).header("Authorization", &auth).call(),
        "DELETE" => agent.delete(&url).header("Authorization", &auth).call(),
        "PATCH" => agent
            .patch(&url)
            .header("Authorization", &auth)
            .send_json(body.unwrap_or_else(|| json!({}))),
        "POST" => agent
            .post(&url)
            .header("Authorization", &auth)
            .send_json(body.unwrap_or_else(|| json!({}))),
        _ => return Err("Unsupported meeting operation."),
    };
    let mut response = response.map_err(|error| match error {
        ureq::Error::StatusCode(401 | 403) => "The server rejected its API key.",
        ureq::Error::StatusCode(404) => "The participant could not be found on this server.",
        ureq::Error::StatusCode(400 | 409) => {
            "The server declined this change. Refresh the meeting before retrying."
        }
        _ => "Your participant server could not be reached. Check its address and connection.",
    })?;
    let bytes = response
        .body_mut()
        .with_config()
        .limit(8 * 1024 * 1024)
        .read_to_vec()
        .map_err(|_| "The server response could not be read.")?;
    if bytes.is_empty() {
        return Ok(Value::Null);
    }
    serde_json::from_slice(&bytes).map_err(|_| "Your server returned an unreadable response.")
}
pub fn payload(event: &Event, profile: &Profile, key: &str) -> Result<Value> {
    let date = OffsetDateTime::from_unix_timestamp(event.start_ms / 1000)
        .map_err(|_| "Invalid meeting time.")?
        .format(&Rfc3339)
        .map_err(|_| "Invalid meeting time.")?;
    Ok(
        json!({"meeting_url": event.url, "bot_name": profile.name, "bot_image": {"type":"image/png", "data": avatar(profile)}, "bot_chat_message":{"to":"everyone","message":"Vyrra is here to take meeting notes using the meeting captions."}, "join_at":date, "deduplication_key":key, "recording_settings":{"format":"none"}, "transcription_settings":{"meeting_closed_captions":{}}}),
    )
}
#[derive(Deserialize)]
pub struct Bot {
    pub id: String,
    pub state: String,
}
fn bot(raw: Value) -> Result<Bot> {
    let b: Bot =
        serde_json::from_value(raw).map_err(|_| "Your server returned an invalid participant.")?;
    if !b.id.starts_with("bot_")
        || b.id.len() > 100
        || !b.id.bytes().all(|v| v.is_ascii_alphanumeric() || v == b'_')
    {
        return Err("Your server returned an invalid participant ID.");
    }
    Ok(b)
}
pub struct Client {
    server: String,
    key: String,
}
impl Client {
    pub fn new(server: &str) -> Result<Self> {
        let server = address(server)?;
        let key = entry(&server)?
            .get_password()
            .map_err(|_| "Import an API key for this server in Meetings settings.")?;
        Ok(Self { server, key })
    }
    pub fn lookup(&self, key: &str) -> Result<Option<Bot>> {
        let previous = request(
            &self.server,
            &self.key,
            "GET",
            &format!("?deduplication_key={key}"),
            None,
        )?;
        let items = previous
            .get("results")
            .and_then(Value::as_array)
            .or_else(|| previous.as_array())
            .ok_or("The server returned an invalid participant list.")?;
        items.first().cloned().map(bot).transpose()
    }
    pub fn schedule(&self, event: &Event, profile: &Profile, key: &str) -> Result<Bot> {
        if let Some(existing) = self.lookup(key)? {
            return Ok(existing);
        }
        bot(request(
            &self.server,
            &self.key,
            "POST",
            "",
            Some(payload(event, profile, key)?),
        )?)
    }
    pub fn status(&self, id: &str) -> Result<Bot> {
        bot(request(
            &self.server,
            &self.key,
            "GET",
            &format!("/{id}"),
            None,
        )?)
    }
    pub fn reschedule(&self, id: &str, event: &Event) -> Result<()> {
        let start = OffsetDateTime::from_unix_timestamp(event.start_ms / 1000)
            .map_err(|_| "Invalid meeting time.")?
            .format(&Rfc3339)
            .map_err(|_| "Invalid meeting time.")?;
        request(
            &self.server,
            &self.key,
            "PATCH",
            &format!("/{id}"),
            Some(json!({"join_at":start,"meeting_url":event.url})),
        )?;
        Ok(())
    }
    pub fn stop(&self, id: &str, scheduled: bool) -> Result<()> {
        let route = if scheduled {
            format!("/{id}")
        } else {
            format!("/{id}/leave")
        };
        request(
            &self.server,
            &self.key,
            if scheduled { "DELETE" } else { "POST" },
            &route,
            None,
        )?;
        Ok(())
    }
    pub fn transcript(&self, id: &str) -> Result<String> {
        transcript(&request(
            &self.server,
            &self.key,
            "GET",
            &format!("/{id}/transcript"),
            None,
        )?)
    }
}
fn transcript(raw: &Value) -> Result<String> {
    let rows = raw
        .as_array()
        .ok_or("The server returned an invalid transcript.")?;
    let mut lines = Vec::new();
    for row in rows {
        let body = &row["transcription"];
        if let Some(s) = body["transcript"].as_str().or_else(|| body.as_str()) {
            let s = s.trim();
            if !s.is_empty() {
                let speaker = row["speaker_name"]
                    .as_str()
                    .filter(|n| !n.is_empty())
                    .unwrap_or("Speaker");
                lines.push(format!("{speaker}: {s}"));
            }
        }
    }
    Ok(lines.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::meetings;
    #[test]
    fn uses_chosen_name_strips_image_metadata_and_schedules_caption_notes() {
        let temp = tempfile::tempdir().unwrap();
        let original = temp.path().join("picture.jpg");
        image::RgbImage::from_pixel(300, 190, image::Rgb([52, 30, 120]))
            .save(&original)
            .unwrap();
        let profile = Profile {
            name: "Otter in a sweater".into(),
            image: Some(picture(&original).unwrap()),
            ..Profile::default()
        };
        let event = Event {
            uid: "quality-test".into(),
            title: "Private title".into(),
            url: "https://meet.google.com/aaa-bbbb-ccc".into(),
            start_ms: meetings::now() + 3600000,
            end_ms: meetings::now() + 7200000,
        };
        let p = payload(&event, &profile, "test-key").unwrap();
        assert_eq!(p["bot_name"], profile.name);
        assert_eq!(p["bot_image"]["type"], "image/png");
        let bytes = STANDARD
            .decode(p["bot_image"]["data"].as_str().unwrap())
            .unwrap();
        let image = image::load_from_memory(&bytes).unwrap();
        assert_eq!((image.width(), image.height()), (256, 256));
        assert_eq!(p["recording_settings"]["format"], "none");
        assert!(p["transcription_settings"]["meeting_closed_captions"].is_object());
        assert_eq!(p["bot_chat_message"]["to"], "everyone");
        assert!(p.get("title").is_none());
        assert_ne!(avatar(&Profile::default()), p["bot_image"]["data"]);
    }
    #[test]
    fn client_uses_actual_speaker_fields_and_constrains_server_addresses() {
        assert!(address("http://localhost:8042").is_ok());
        assert!(address("https://meetings.example.com/").is_ok());
        for bad in [
            "http://example.com",
            "https://name@host.test",
            "https://example.com/?secret",
            "file:///tmp",
        ] {
            assert!(address(bad).is_err());
        }
        let raw = json!([{"speaker_name":"Kai","transcription":{"transcript":"Friday works."}},{"speaker_name":"Lei","transcription":{"transcript":"I’ll send the notes."}}]);
        assert_eq!(
            transcript(&raw).unwrap(),
            "Kai: Friday works.\nLei: I’ll send the notes."
        );
    }
    // Schedules on a loopback-only disposable Attendee instance and cancels before the call can start.
    #[test]
    #[ignore = "requires a disposable local Attendee server and test project key file"]
    fn schedules_identity_and_cancels_on_real_self_hosted_server() {
        let addr = std::env::var("VYRRA_TEST_ATTENDEE_ORIGIN").unwrap();
        assert!(addr.starts_with("http://127.0.0.1:"));
        let token = std::fs::read_to_string(std::env::var("VYRRA_TEST_ATTENDEE_KEY_FILE").unwrap())
            .unwrap();
        let client = Client {
            server: address(&addr).unwrap(),
            key: token.trim().to_string(),
        };
        let event = Event {
            uid: "vyrra-disposable-review".into(),
            title: "Vyrra disposable QA".into(),
            url: "https://meet.google.com/aaa-bbbb-ccc".into(),
            start_ms: meetings::now() + 86400000,
            end_ms: meetings::now() + 86500000,
        };
        let image = tempfile::Builder::new().suffix(".png").tempfile().unwrap();
        image::RgbImage::from_pixel(160, 130, image::Rgb([110, 100, 185]))
            .save(image.path())
            .unwrap();
        let profile = Profile {
            name: "Vyrra Studio QA".into(),
            image: Some(picture(image.path()).unwrap()),
            ..Profile::default()
        };
        let key = format!("vyrra-qa-{}", meetings::now());
        let first = client.schedule(&event, &profile, &key).unwrap();
        assert_eq!(first.state, "scheduled");
        let again = client.schedule(&event, &profile, &key).unwrap();
        assert_eq!(first.id, again.id);
        let read = request(
            &client.server,
            &client.key,
            "GET",
            &format!("/{}", first.id),
            None,
        )
        .unwrap();
        assert_eq!(read["deduplication_key"], key);
        assert_eq!(read["state"], "scheduled");
        let mut moved = event;
        moved.start_ms += 3600000;
        client.reschedule(&first.id, &moved).unwrap();
        client.stop(&first.id, true).unwrap();
        assert!(client.lookup(&key).unwrap().is_none());
    }
}

#[cfg(test)]
mod admitted_room_test {
    use super::*;
    /// Operator creates and hosts an empty test room. The marker ends the check after its tile and chat message have been inspected.
    #[test]
    #[ignore = "requires an explicitly authorized empty external test room and an isolated loopback Attendee deployment"]
    fn observe_named_participant_in_private_test_room() {
        let dir = std::path::PathBuf::from(std::env::var("VYRRA_TEST_MEET_DIR").unwrap());
        let link = std::fs::read_to_string(dir.join("room")).unwrap();
        let server = address(&std::env::var("VYRRA_TEST_ATTENDEE_ORIGIN").unwrap()).unwrap();
        assert!(server.starts_with("http://127.0.0.1:"));
        let key = std::fs::read_to_string(std::env::var("VYRRA_TEST_ATTENDEE_KEY_FILE").unwrap())
            .unwrap();
        let client = Client {
            server,
            key: key.trim().into(),
        };
        let now = super::super::now();
        let event = Event {
            uid: "explicit-empty-room".into(),
            title: "Private QA".into(),
            url: link.trim().into(),
            start_ms: now + 20_000,
            end_ms: now + 300_000,
        };
        event.validate().unwrap();
        let profile = Profile {
            name: "Vyrra Studio Scribe".into(),
            image: Some(picture(&dir.join("avatar.png")).unwrap()),
            ..Profile::default()
        };
        let bot = client
            .schedule(&event, &profile, &format!("vyrra-visual-{now}"))
            .unwrap();
        std::fs::write(dir.join("bot"), &bot.id).unwrap();
        let mut admitted = false;
        let mut previous = String::new();
        for _ in 0..120 {
            let state = client.status(&bot.id).unwrap().state;
            if state != previous {
                println!("Participant state: {state}");
                previous = state.clone();
            }
            admitted |= state.starts_with("joined_");
            if super::super::terminal(&state) || dir.join("finish").exists() {
                break;
            }
            std::thread::sleep(Duration::from_secs(3));
        }
        let last = client.status(&bot.id).unwrap().state;
        if !super::super::terminal(&last) {
            client.stop(&bot.id, last == "scheduled").unwrap();
        }
        assert!(admitted, "Provider admission was not observed.");
    }
}
