pub mod calendar;
mod local;
mod participant;
mod store;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tauri::{AppHandle, Manager, State};
use url::Url;
type Result<T> = std::result::Result<T, &'static str>;
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub uid: String,
    pub title: String,
    pub url: String,
    pub start_ms: i64,
    pub end_ms: i64,
}
#[derive(Clone, Deserialize, Serialize, Default, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Mode {
    #[default]
    Local,
    Participant,
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Profile {
    name: String,
    image: Option<String>,
    server: String,
    source: String,
}
impl Default for Profile {
    fn default() -> Self {
        Self {
            name: "Vyrra Notes".into(),
            image: None,
            server: String::new(),
            source: local::sources().first().map(|s| s.0).unwrap_or("").into(),
        }
    }
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Plan {
    key: String,
    event: Event,
    mode: Mode,
    phase: String,
    source: String,
    server: String,
    remote: Option<String>,
    transcript: String,
    notes: String,
    error: Option<String>,
    #[serde(default)]
    generation: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    identity: Option<Profile>,
}
fn terminal(p: &str) -> bool {
    matches!(
        p,
        "ended" | "missed" | "canceled" | "interrupted" | "failed" | "fatal_error" | "data_deleted"
    )
}
fn valid_link(value: &str) -> bool {
    let Ok(url) = Url::parse(value) else {
        return false;
    };
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
        || value.len() > 4096
    {
        return false;
    }
    let host = url.host_str().unwrap_or("");
    let path = url.path();
    if host == "meet.google.com" {
        let code = path.trim_matches('/').split('-').collect::<Vec<_>>();
        return code.len() == 3
            && code.iter().map(|s| s.len()).eq([3, 4, 3])
            && code
                .iter()
                .all(|s| s.bytes().all(|c| c.is_ascii_lowercase()));
    }
    if host == "zoom.us"
        || host.ends_with(".zoom.us")
        || host == "zoomgov.com"
        || host.ends_with(".zoomgov.com")
    {
        return ["/j/", "/my/", "/w/"].iter().any(|p| {
            path.strip_prefix(p)
                .is_some_and(|x| !x.is_empty() && !x.contains('/'))
        });
    }
    matches!(
        host,
        "teams.microsoft.com" | "teams.live.com" | "teams.cloud.microsoft"
    ) && ["/l/meetup-join/", "/meet/"]
        .iter()
        .any(|p| path.starts_with(p) && path.len() > p.len())
}
impl Event {
    fn validate(&self) -> Result<()> {
        if self.uid.is_empty()
            || self.uid.len() > 1024
            || self.title.trim().is_empty()
            || self.title.len() > 512
            || !valid_link(&self.url)
        {
            return Err("Choose a Google Meet, Zoom, or Teams calendar call.");
        }
        if self.end_ms <= self.start_ms
            || self.start_ms < now()
            || self.end_ms - self.start_ms > 7 * 86400000
        {
            return Err("Choose an upcoming call with a valid end time.");
        }
        Ok(())
    }
}
#[derive(Clone)]
pub struct Meetings {
    dir: PathBuf,
    stop: Arc<AtomicBool>,
    quit: Arc<AtomicBool>,
    active: Arc<Mutex<Option<String>>>,
    network: Arc<Mutex<()>>,
}
impl Meetings {
    fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            stop: Default::default(),
            quit: Default::default(),
            active: Default::default(),
            network: Default::default(),
        }
    }
    fn change<T>(&self, key: &str, mutate: impl FnOnce(&mut Plan) -> Result<T>) -> Result<T> {
        store::update(&self.dir, |db| {
            mutate(
                db.plans
                    .iter_mut()
                    .find(|p| p.key == key)
                    .ok_or("This meeting is no longer scheduled.")?,
            )
        })
    }
    pub fn is_recording(&self) -> bool {
        self.active
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .is_some()
    }
    pub fn shutdown(&self) {
        self.quit.store(true, Ordering::Release);
        self.stop.store(true, Ordering::Release);
    }
    fn sync(&self, key: &str, allow_create: bool) -> Result<()> {
        let _lock = self.network.lock().unwrap_or_else(|p| p.into_inner());
        let db = store::read(&self.dir)?;
        let plan = db
            .plans
            .iter()
            .find(|p| p.key == key)
            .ok_or("This meeting is unavailable.")?;
        if plan.mode != Mode::Participant || terminal(&plan.phase) {
            return Ok(());
        }
        let client = participant::Client::new(&plan.server)?;
        let bot = if let Some(id) = &plan.remote {
            client.status(id)?
        } else if allow_create {
            client.schedule(
                &plan.event,
                plan.identity.as_ref().unwrap_or(&db.profile),
                &format!("vyrra-{key}-{}", plan.generation),
            )?
        } else {
            return Ok(());
        };
        let transcript = if matches!(
            bot.state.as_str(),
            "ended"
                | "post_processing"
                | "joined_recording"
                | "joined_recording_paused"
                | "leaving"
        ) {
            Some(client.transcript(&bot.id)?)
        } else {
            None
        };
        self.change(key, |p| {
            p.remote = Some(bot.id);
            p.phase = bot.state;
            if let Some(text) = transcript
                && !text.is_empty()
            {
                p.transcript = text;
            }
            p.error = None;
            Ok(())
        })
    }
    fn notes(&self, app: &AppHandle, key: &str) {
        let Ok(db) = store::read(&self.dir) else {
            return;
        };
        let Some(p) = db.plans.iter().find(|p| {
            p.key == key && p.notes.is_empty() && !p.transcript.is_empty() && terminal(&p.phase)
        }) else {
            return;
        };
        let writer = app.state::<crate::dictation::writing::Writing>();
        if let Ok(notes) = writer.meeting_notes(&p.transcript) {
            let _ = self.change(key, |p| {
                p.notes = notes;
                Ok(())
            });
        }
    }
    fn reconcile(&self, plan: &Plan, current: Option<&Event>) -> Result<()> {
        if current == Some(&plan.event) {
            return Ok(());
        }
        let _network = self.network.lock().unwrap_or_else(|p| p.into_inner());
        let snapshot = store::read(&self.dir)?;
        let Some(saved) = snapshot
            .plans
            .iter()
            .find(|p| p.key == plan.key && p.phase == "scheduled")
        else {
            return Ok(());
        };
        if saved.mode == Mode::Participant
            && let Some(id) = &saved.remote
        {
            let client = participant::Client::new(&saved.server)?;
            match current {
                Some(event) => {
                    client.reschedule(id, event)?;
                }
                None => client.stop(id, true)?,
            }
        }
        self.change(&plan.key, |p| {
            if p.phase == "scheduled" {
                match current {
                    Some(e) => p.event = e.clone(),
                    None => p.phase = "canceled".into(),
                };
                p.error = None;
            }
            Ok(())
        })
    }
    fn due(&self, app: &AppHandle, p: &Plan) {
        let (key, t) = (&p.key, now());
        if p.phase != "scheduled" || p.mode != Mode::Local || p.event.start_ms > t {
            return;
        }
        if self.quit.load(Ordering::Acquire) {
            return;
        }
        if p.event.end_ms <= t || t - p.event.start_ms > 90_000 {
            let _ = self.change(key, |p| {
                if p.phase == "scheduled" {
                    p.phase = "missed".into();
                }
                Ok(())
            });
            return;
        }
        if p.event.uid.starts_with("apple:") {
            match calendar::calls(false) {
                Ok(items) => {
                    let current = items.iter().find(|e| e.uid == p.event.uid);
                    if current != Some(&p.event) {
                        let _ = self.reconcile(p, current);
                        return;
                    }
                }
                Err(error) => {
                    let _ = self.change(key, |plan| {
                        plan.phase = "failed".into();
                        plan.error = Some(error.into());
                        Ok(())
                    });
                    return;
                }
            }
        }
        let mut active = self.active.lock().unwrap_or_else(|p| p.into_inner());
        if active.is_some() {
            return;
        }
        if self
            .change(key, |p| {
                if p.phase == "scheduled" {
                    p.phase = "opening".into();
                    Ok(())
                } else {
                    Err("Meeting already started.")
                }
            })
            .is_err()
        {
            return;
        }
        self.stop.store(false, Ordering::Release);
        *active = Some(key.clone());
        drop(active);
        let (state, app, plan) = (self.clone(), app.clone(), p.clone());
        std::thread::spawn(move || {
            let result = local::run(&app, &state, &plan.event, &plan.source, &plan.key);
            let _ = state.change(&plan.key, |p| {
                p.phase = if result.is_ok() { "ended" } else { "failed" }.into();
                p.error = result.err().map(Into::into);
                Ok(())
            });
            if let Some(panel) = app.get_webview_window("meeting-indicator") {
                let _ = panel.hide();
            }
            *state.active.lock().unwrap_or_else(|p| p.into_inner()) = None;
            state.notes(&app, &plan.key);
        });
    }
}
pub fn setup(app: &AppHandle) -> std::result::Result<(), Box<dyn std::error::Error>> {
    let state = Meetings::new(app.path().app_local_data_dir()?);
    let handle = app.clone();
    app.manage(state.clone());
    std::thread::spawn(move || {
        let Ok(_owner) = store::owner(&state.dir) else {
            return;
        };
        let _ = store::update(&state.dir, |db| {
            for p in &mut db.plans {
                if p.mode == Mode::Local && matches!(p.phase.as_str(), "opening" | "taking_notes") {
                    p.phase = "interrupted".into();
                }
            }
            Ok(())
        });
        let network = state.clone();
        let network_app = handle.clone();
        std::thread::spawn(move || {
            while !network.quit.load(Ordering::Acquire) {
                if let Ok(db) = store::read(&network.dir) {
                    let calendar_needed = db.plans.iter().any(|p| {
                        p.event.uid.starts_with("apple:")
                            && matches!(p.phase.as_str(), "scheduled" | "scheduling")
                    });
                    if calendar_needed && let Ok(calls) = calendar::calls(false) {
                        for plan in db
                            .plans
                            .iter()
                            .filter(|p| p.event.uid.starts_with("apple:") && p.phase == "scheduled")
                        {
                            if let Err(error) = network
                                .reconcile(plan, calls.iter().find(|e| e.uid == plan.event.uid))
                            {
                                let _ = network.change(&plan.key, |p| {
                                    p.error = Some(error.into());
                                    Ok(())
                                });
                            }
                        }
                    }
                    for plan in db.plans.iter().filter(|p| {
                        p.mode == Mode::Participant
                            && !terminal(&p.phase)
                            && (p.phase == "scheduling" || p.event.start_ms < now() + 120000)
                    }) {
                        if let Err(e) = network.sync(&plan.key, true) {
                            let _ = network.change(&plan.key, |p| {
                                p.error = Some(e.into());
                                Ok(())
                            });
                        } else {
                            network.notes(&network_app, &plan.key);
                        }
                    }
                }
                for _ in 0..30 {
                    if network.quit.load(Ordering::Acquire) {
                        return;
                    }
                    std::thread::sleep(Duration::from_secs(1));
                }
            }
        });
        while !state.quit.load(Ordering::Acquire) {
            if let Ok(db) = store::read(&state.dir) {
                for p in &db.plans {
                    state.due(&handle, p);
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    });
    Ok(())
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct View {
    profile: Profile,
    avatar: String,
    sources: Vec<(&'static str, &'static str)>,
    plans: Vec<Plan>,
}
#[tauri::command]
pub fn meeting_list(state: State<'_, Meetings>) -> Result<View> {
    let db = store::read(&state.dir)?;
    let avatar = participant::avatar(&db.profile);
    let mut profile = db.profile;
    profile.image = profile.image.map(|_| "custom".into());
    Ok(View {
        profile,
        avatar,
        sources: local::sources(),
        plans: db
            .plans
            .into_iter()
            .map(|mut plan| {
                plan.identity = None;
                plan
            })
            .collect(),
    })
}
#[tauri::command]
pub fn meeting_profile(
    state: State<'_, Meetings>,
    name: String,
    server: String,
    source: String,
) -> Result<()> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 64 || name.chars().any(char::is_control) {
        return Err("Use a participant name between 1 and 64 characters.");
    }
    let server = if server.trim().is_empty() {
        String::new()
    } else {
        participant::address(&server)?
    };
    if !source.is_empty() && !local::sources().iter().any(|s| s.0 == source) {
        return Err("Choose a supported audio source.");
    }
    store::update(&state.dir, |d| {
        d.profile.name = name.into();
        d.profile.server = server;
        d.profile.source = source;
        Ok(())
    })
}
#[tauri::command]
pub async fn meeting_picture(state: State<'_, Meetings>, reset: bool) -> Result<()> {
    let dir = state.dir.clone();
    let image = if reset {
        None
    } else {
        let Some(f) = rfd::AsyncFileDialog::new()
            .set_title("Choose a participant picture")
            .add_filter("Pictures", &["png", "jpg", "jpeg"])
            .pick_file()
            .await
        else {
            return Ok(());
        };
        let path = f.path().to_owned();
        Some(work(move || participant::picture(&path)).await?)
    };
    store::update(&dir, |d| {
        d.profile.image = image;
        Ok(())
    })
}
#[tauri::command]
pub async fn meeting_key(state: State<'_, Meetings>, server: String) -> Result<()> {
    let server = participant::address(&server)?;
    let Some(file) = rfd::AsyncFileDialog::new()
        .set_title("Choose a file containing your Attendee API key")
        .pick_file()
        .await
    else {
        return Ok(());
    };
    let path = file.path().to_owned();
    let _ = state;
    work(move || {
        use std::io::Read;
        let mut text = String::new();
        std::fs::File::open(path)
            .and_then(|f| f.take(2050).read_to_string(&mut text))
            .map_err(|_| "The key file could not be read.")?;
        participant::save_key(&server, text.trim())
    })
    .await
}
async fn work<T: Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<T> {
    tauri::async_runtime::spawn_blocking(f)
        .await
        .map_err(|_| "The meeting worker was interrupted.")?
}
#[tauri::command]
pub async fn meeting_schedule(
    state: State<'_, Meetings>,
    app: AppHandle,
    event: Event,
    mode: Mode,
) -> Result<()> {
    event.validate()?;
    let key = format!("{:x}", Sha256::digest(event.uid.as_bytes()));
    let state = state.inner().clone();
    if mode == Mode::Local {
        if local::sources().is_empty() {
            return Err("Local meeting audio is unavailable on this platform. Choose the self-hosted participant.");
        }
        if !app.state::<crate::dictation::Dictation>().meeting_ready() {
            return Err("Install a speech model in Models before scheduling local notes.");
        }
    }
    work(move || {
        let profile = store::read(&state.dir)?.profile;
        if mode == Mode::Participant { participant::Client::new(&profile.server)?; }
        store::update(&state.dir, |db| {
            let old = db.plans.iter().find(|plan| plan.key == key);
            let generation = match old {
                Some(plan) if plan.phase == "canceled" => plan.generation + 1,
                Some(plan) if plan.phase == "scheduling" && mode == Mode::Participant && plan.event == event => return Ok(()),
                Some(_) => return Err("This calendar occurrence already has a plan. Cancel it before scheduling again."),
                None => 0,
            };
            db.plans.retain(|plan| plan.key != key);
            db.plans.insert(0, Plan {
                key:key.clone(), event, mode:mode.clone(), generation,
                phase: if mode == Mode::Local { "scheduled" } else { "scheduling" }.into(),
                source:profile.source.clone(), server:if mode==Mode::Participant {profile.server.clone()} else {String::new()},
                identity:if mode==Mode::Participant {Some(profile.clone())} else {None},
                remote:None, transcript:String::new(), notes:String::new(), error:None,
            });
            Ok(())
        })?;
        if mode == Mode::Participant && let Err(error)=state.sync(&key,true) {
            state.change(&key,|plan| {plan.error=Some(error.into());Ok(())})?;
            return Err(error);
        }
        Ok(())
    }).await
}
#[tauri::command]
pub async fn meeting_action(
    state: State<'_, Meetings>,
    app: AppHandle,
    key: String,
    action: String,
) -> Result<()> {
    let state = state.inner().clone();
    work(move || {
        if action == "refresh" {
            state.sync(&key, true)?;
            state.notes(&app, &key);
            return Ok(());
        }
        let _serial = state.network.lock().unwrap_or_else(|p| p.into_inner());
        let db = store::read(&state.dir)?;
        let p = db
            .plans
            .iter()
            .find(|p| p.key == key)
            .ok_or("This meeting is unavailable.")?;
        match action.as_str() {
            "delete" if terminal(&p.phase) => store::update(&state.dir, |db| {
                db.plans.retain(|p| p.key != key);
                Ok(())
            }),
            "stop" if !terminal(&p.phase) => {
                if p.mode == Mode::Participant {
                    let client = participant::Client::new(&p.server)?;
                    let id = if let Some(id) = &p.remote {
                        Some(id.clone())
                    } else {
                        client
                            .lookup(&format!("vyrra-{key}-{}", p.generation))?
                            .map(|b| b.id)
                    };
                    if let Some(id) = id {
                        let b = client.status(&id)?;
                        if terminal(&b.state) {
                            let text = if b.state == "ended" {
                                client.transcript(&b.id)?
                            } else {
                                String::new()
                            };
                            return state.change(&key, |p| {
                                p.phase = b.state;
                                p.remote = Some(id);
                                if !text.is_empty() {
                                    p.transcript = text;
                                }
                                Ok(())
                            });
                        } else {
                            client.stop(&b.id, b.state == "scheduled")?;
                            if b.state != "scheduled" {
                                return state.change(&key, |p| {
                                    p.phase = "leaving".into();
                                    p.remote = Some(id);
                                    Ok(())
                                });
                            }
                        }
                    }
                } else if state
                    .active
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .as_deref()
                    == Some(&key)
                {
                    state.stop.store(true, Ordering::Release);
                    return Ok(());
                }
                state.change(&key, |p| {
                    p.phase = "canceled".into();
                    p.error = None;
                    Ok(())
                })
            }
            _ => Err("This action is unavailable in the current meeting state."),
        }
    })
    .await
}
#[tauri::command]
pub fn meeting_stop_active(state: State<'_, Meetings>) {
    state.stop.store(true, Ordering::Release);
}

#[tauri::command]
pub fn meeting_indicator_phase(state: State<'_, Meetings>) -> String {
    let key = state
        .active
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .clone();
    key.and_then(|k| {
        store::read(&state.dir)
            .ok()?
            .plans
            .into_iter()
            .find(|p| p.key == k)
            .map(|p| p.phase)
    })
    .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_supported_meeting_urls_can_be_launched_and_stale_calls_are_rejected() {
        for u in [
            "https://meet.google.com/aaa-bbbb-ccc",
            "https://us02web.zoom.us/j/123456?pwd=test",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting",
        ] {
            assert!(valid_link(u));
        }
        for u in [
            "https://meet.google.com.example.com/aaa-bbbb-ccc",
            "https://zoom.us@notzoom.test/j/3",
            "https://zoom.us/signin",
            "file:///tmp/x",
            "javascript:alert(1)",
            "https://meet.google.com:567/aaa-bbbb-ccc",
        ] {
            assert!(!valid_link(u));
        }
        let mut e = Event {
            uid: "A".into(),
            title: "Session".into(),
            url: "https://meet.google.com/aaa-bbbb-ccc".into(),
            start_ms: now() + 60000,
            end_ms: now() + 120000,
        };
        assert!(e.validate().is_ok());
        e.start_ms = now() - 1000;
        assert!(e.validate().is_err());
    }
    #[test]
    fn updates_survive_restart_and_an_unreadable_store_is_preserved() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path();
        store::update(path, |db| {
            db.profile.name = "Nova".into();
            Ok(())
        })
        .unwrap();
        assert_eq!(store::read(path).unwrap().profile.name, "Nova");
        let lock = store::owner(path).unwrap();
        assert!(store::owner(path).is_err());
        drop(lock);
        assert!(store::owner(path).is_ok());
        std::fs::write(path.join("meetings-v1.json"), "broken").unwrap();
        assert!(
            store::update(path, |db| {
                db.profile.name = "New".into();
                Ok(())
            })
            .is_err()
        );
        assert_eq!(
            std::fs::read_to_string(path.join("meetings-v1.json")).unwrap(),
            "broken"
        );
    }
}
