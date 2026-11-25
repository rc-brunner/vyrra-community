pub(crate) mod audio;
mod engine;
pub mod feedback;
pub mod hotkeys;
mod insertion;
mod library;
pub mod writing;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State};
use whisper_rs::WhisperContext;

use audio::Microphone;
use engine::{MODEL_FILE, Result, SpeechOptions};

#[derive(Default, Clone, Copy, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
enum Phase {
    #[default]
    Idle,
    Starting,
    Listening,
    Paused,
    Transcribing,
}

#[derive(Default, Clone, Copy, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
enum Model {
    #[default]
    Missing,
    Checking,
    Installing,
    Ready,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    phase: Phase,
    model: Model,
    elapsed_ms: u64,
    level: f32,
    text: String,
    revision: u64,
    error: Option<String>,
    delivery: Option<bool>,
}

#[derive(Default)]
struct Session {
    phase: Phase,
    model: Model,
    token: u64,
    engine: Option<Arc<WhisperContext>>,
    mic: Option<Microphone>,
    options: SpeechOptions,
    external: bool,
    target: Option<insertion::Insertion>,
    delivery: Option<bool>,
    elapsed_ms: u64,
    text: String,
    revision: u64,
    error: Option<String>,
}

#[derive(Clone)]
pub struct Dictation {
    dir: PathBuf,
    inner: Arc<Mutex<Session>>,
    decoder: Arc<Mutex<()>>,
}

impl Dictation {
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            inner: Default::default(),
            decoder: Default::default(),
        }
    }
    fn lock(&self) -> MutexGuard<'_, Session> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
    fn model_path(&self) -> PathBuf {
        self.dir.join("models").join(MODEL_FILE)
    }

    pub fn prepare_existing(&self) {
        let path = self.model_path();
        if path.is_file() {
            let _ = self.prepare(Model::Checking, || engine::load_model(&path));
        }
    }

    fn prepare(&self, mode: Model, load: impl FnOnce() -> Result<WhisperContext>) -> Result<()> {
        {
            let mut session = self.lock();
            match session.model {
                Model::Ready => return Ok(()),
                Model::Checking | Model::Installing => {
                    return Err("Model setup is already running.");
                }
                Model::Missing => {}
            }
            session.model = mode;
            session.error = None;
        }
        let result = load();
        let mut session = self.lock();
        match result {
            Ok(engine) => {
                session.engine = Some(Arc::new(engine));
                session.model = Model::Ready;
                Ok(())
            }
            Err(msg) => {
                session.model = Model::Missing;
                session.error = Some(msg.into());
                Err(msg)
            }
        }
    }

    pub(crate) fn meeting_ready(&self) -> bool {
        self.lock().engine.is_some()
    }
    pub(crate) fn meeting_text(&self, pcm: &[f32]) -> Result<String> {
        let _worker = self.decoder.lock().unwrap_or_else(|e| e.into_inner());
        let model = self
            .lock()
            .engine
            .clone()
            .ok_or("Install the speech model first.")?;
        let mut options = library::load(&self.dir)?.options;
        options.snippets.clear();
        engine::transcribe(&model, pcm, &options)
    }
    fn begin(&self) -> Result<u64> {
        let mut session = self.lock();
        if session.phase != Phase::Idle {
            return Err("A dictation is already in progress.");
        }
        if session.engine.is_none() {
            return Err("Install the speech model on this device first.");
        }
        session.external = false;
        session.target = None;
        session.delivery = None;
        session.options = library::load(&self.dir)?.options;
        session.token = session.token.wrapping_add(1);
        session.error = None;
        session.elapsed_ms = 0;
        session.phase = Phase::Starting;
        Ok(session.token)
    }

    fn start(&self) -> Result<()> {
        let token = self.begin()?;
        self.open_microphone(token)
    }

    fn open_microphone(&self, token: u64) -> Result<()> {
        if self.lock().token != token {
            return Ok(());
        }
        let result = (|| {
            #[cfg(target_os = "macos")]
            audio::authorize_microphone()?;
            let sound = {
                let s = self.lock();
                if s.token != token {
                    return Err("Canceled.");
                }
                s.options.sound
            };
            sound.play(false);
            if self.lock().token != token {
                return Err("Canceled.");
            }
            Microphone::open()
        })();
        let mut session = self.lock();
        if session.token != token {
            return Ok(());
        }
        match result {
            Ok(mic) => {
                session.mic = Some(mic);
                session.phase = Phase::Listening;
                Ok(())
            }
            Err(msg) => {
                session.phase = Phase::Idle;
                session.error = Some(msg.into());
                Err(msg)
            }
        }
    }

    #[cfg(test)]
    fn snapshot(&self) -> Snapshot {
        self.snapshot_for(None, true)
    }
    fn snapshot_for(&self, since: Option<u64>, include_text: bool) -> Snapshot {
        let mut s = self.lock();
        let (elapsed_ms, level, disconnected) = s
            .mic
            .as_ref()
            .map_or((s.elapsed_ms, 0.0, false), |m| m.metrics());
        if disconnected {
            s.phase = Phase::Idle;
            s.mic.take();
            s.error = Some("The microphone was disconnected or ran out of memory.".into());
        }
        Snapshot {
            phase: s.phase,
            model: s.model,
            elapsed_ms,
            level: if s.phase == Phase::Listening {
                level
            } else {
                0.0
            },
            text: if include_text && since != Some(s.revision) {
                s.text.clone()
            } else {
                String::new()
            },
            revision: s.revision,
            error: s.error.clone(),
            delivery: s.delivery,
        }
    }

    fn finish(&self) -> Result<()> {
        self.finish_inner(None)
    }

    fn finish_external(&self, token: u64) -> Result<()> {
        self.finish_inner(Some(token))
    }

    fn finish_inner(&self, expected: Option<u64>) -> Result<()> {
        let (token, mic) = {
            let mut s = self.lock();
            if let Some(token) = expected {
                if s.token != token {
                    return Ok(());
                }
                if s.phase == Phase::Starting {
                    s.token = s.token.wrapping_add(1);
                    s.phase = Phase::Idle;
                    s.target.take();
                    return Ok(());
                }
            }
            let mic = s.mic.take().ok_or("The microphone is not recording.")?;
            s.elapsed_ms = mic.metrics().0;
            s.phase = Phase::Transcribing;
            (s.token, mic)
        };
        let samples = mic.finish();
        let sound = self.lock().options.sound;
        std::thread::spawn(move || sound.play(true));
        self.decode(token, samples)
    }

    fn import(&self, path: &Path) -> Result<()> {
        let token = self.begin()?;
        {
            let mut s = self.lock();
            if s.token != token {
                return Ok(());
            }
            s.phase = Phase::Transcribing;
        }
        self.decode(token, audio::read_wav(path))
    }

    fn decode(&self, token: u64, samples: Result<Vec<f32>>) -> Result<()> {
        let _worker = self.decoder.lock().unwrap_or_else(|e| e.into_inner());
        let (engine, options) = {
            let s = self.lock();
            if s.token != token {
                return Ok(());
            }
            (
                s.engine.clone().ok_or("The speech model is unavailable.")?,
                s.options.clone(),
            )
        };
        let result = samples.and_then(|samples| engine::transcribe(&engine, &samples, &options));
        let mut s = self.lock();
        if s.token != token {
            return Ok(());
        }
        s.phase = Phase::Idle;
        match result {
            Ok(text) => {
                if s.external {
                    s.delivery = Some(s.target.take().is_some_and(|t| t.insert(text.clone())));
                }
                s.text = text;
                s.revision += 1;
                Ok(())
            }
            Err(msg) => {
                s.error = Some(msg.into());
                Err(msg)
            }
        }
    }

    fn cancel_external(&self) {
        let mut s = self.lock();
        if s.external {
            Self::cancel_session(&mut s);
        }
    }
    pub fn cancel(&self) {
        Self::cancel_session(&mut self.lock());
    }
    fn cancel_session(s: &mut Session) {
        s.target = None;
        s.delivery = None;
        s.external = false;
        let was_recording = s.mic.take().is_some();
        s.token = s.token.wrapping_add(1);
        if was_recording {
            let sound = s.options.sound;
            std::thread::spawn(move || sound.play(true));
        }
        s.phase = Phase::Idle;
        s.elapsed_ms = 0;
        s.error = None;
    }
}

pub fn setup(app: &AppHandle) -> std::result::Result<(), Box<dyn std::error::Error>> {
    let state = Dictation::new(app.path().app_local_data_dir()?);
    app.manage(writing::Writing::new(
        state.dir.join("models").join("writing"),
    ));
    app.manage(state.clone());
    hotkeys::restore(app.clone(), &state);
    tauri::async_runtime::spawn_blocking(move || state.prepare_existing());
    Ok(())
}

#[tauri::command]
pub fn dictation_status(
    state: State<'_, Dictation>,
    window: tauri::Window,
    since: Option<u64>,
) -> Snapshot {
    state.snapshot_for(since, window.label() == "main")
}

async fn blocking<T: Send + 'static>(f: impl FnOnce() -> Result<T> + Send + 'static) -> Result<T> {
    tauri::async_runtime::spawn_blocking(f)
        .await
        .map_err(|_| "The dictation worker was interrupted.")?
}

#[tauri::command]
pub async fn dictation_install(state: State<'_, Dictation>, offline: bool) -> Result<()> {
    let state = state.inner().clone();
    let import = if offline {
        let Some(file) = rfd::AsyncFileDialog::new()
            .set_title("Choose the Whisper base model")
            .add_filter("Whisper base", &["bin"])
            .pick_file()
            .await
        else {
            return Ok(());
        };
        Some(file.path().to_owned())
    } else {
        None
    };
    blocking(move || {
        state.prepare(Model::Installing, || {
            engine::install_model(&state.model_path(), import.as_deref())
        })
    })
    .await
}

#[tauri::command]
pub async fn dictation_import(state: State<'_, Dictation>) -> Result<()> {
    let state = state.inner().clone();
    let Some(file) = rfd::AsyncFileDialog::new()
        .set_title("Transcribe audio on this device")
        .add_filter("WAV audio", &["wav"])
        .pick_file()
        .await
    else {
        return Ok(());
    };
    blocking(move || state.import(file.path())).await
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Start,
    Check,
    Pause,
    Resume,
    Finish,
    Cancel,
    Clear,
}

#[tauri::command]
pub async fn dictation_action(action: Action, state: State<'_, Dictation>) -> Result<()> {
    let state = state.inner().clone();
    blocking(move || match action {
        Action::Start => state.start(),
        Action::Check => {
            let token = state.begin()?;
            state.open_microphone(token)?;
            std::thread::sleep(std::time::Duration::from_secs(5));
            let still_ours = {
                let s = state.lock();
                s.token == token && matches!(s.phase, Phase::Listening | Phase::Paused)
            };
            if still_ours {
                state.finish_inner(Some(token))
            } else {
                Ok(())
            }
        }
        Action::Finish => state.finish(),
        Action::Pause | Action::Resume => {
            let mut s = state.lock();
            let mic = s.mic.as_ref().ok_or("The microphone is not recording.")?;
            if matches!(action, Action::Pause) {
                mic.pause()?;
                s.phase = Phase::Paused;
            } else {
                mic.resume()?;
                s.phase = Phase::Listening;
            }
            Ok(())
        }
        Action::Cancel => {
            state.cancel();
            Ok(())
        }
        Action::Clear => {
            let mut s = state.lock();
            s.text.clear();
            s.revision += 1;
            Ok(())
        }
    })
    .await
}

#[tauri::command]
pub fn dictation_languages() -> Vec<(&'static str, &'static str)> {
    // Whisper base has 99 language tokens. Cantonese was added with large-v3.
    let mut items: Vec<_> = (0..99)
        .filter_map(|id| {
            Some((
                whisper_rs::get_lang_str(id)?,
                whisper_rs::get_lang_str_full(id)?,
            ))
        })
        .collect();
    items.sort_unstable_by_key(|(_, name)| *name);
    items
}

#[tauri::command]
pub async fn dictation_export(text: String) -> Result<()> {
    let Some(file) = rfd::AsyncFileDialog::new()
        .set_title("Export transcript")
        .set_file_name("Vyrra transcript.txt")
        .add_filter("Text", &["txt"])
        .save_file()
        .await
    else {
        return Ok(());
    };
    blocking(move || {
        use std::io::Write;
        let parent = file
            .path()
            .parent()
            .ok_or("The destination is unavailable.")?;
        let mut tmp = tempfile::NamedTempFile::new_in(parent)
            .map_err(|_| "The transcript could not be exported.")?;
        tmp.write_all(text.as_bytes())
            .and_then(|_| tmp.flush())
            .map_err(|_| "The transcript could not be exported.")?;
        tmp.persist(file.path())
            .map_err(|_| "The transcript could not be exported.")?;
        Ok(())
    })
    .await
}

#[tauri::command]
pub fn dictation_options(state: State<'_, Dictation>) -> Result<SpeechOptions> {
    Ok(library::load(&state.dir)?.options)
}

#[tauri::command]
pub fn dictation_set_options(state: State<'_, Dictation>, options: SpeechOptions) -> Result<()> {
    options.validate()?;
    library::update(&state.dir, |db| {
        db.options = options;
        Ok(())
    })
}

#[tauri::command]
pub fn dictation_entries(state: State<'_, Dictation>) -> Result<Vec<library::Entry>> {
    Ok(library::load(&state.dir)?.entries)
}

#[tauri::command]
pub fn dictation_save(state: State<'_, Dictation>, id: Option<u64>, text: String) -> Result<u64> {
    library::update(&state.dir, |db| db.save(id, text))
}

#[tauri::command]
pub fn dictation_mark(
    state: State<'_, Dictation>,
    id: u64,
    pinned: Option<bool>,
    archived: Option<bool>,
) -> Result<()> {
    library::update(&state.dir, |db| {
        let entry = db
            .entries
            .iter_mut()
            .find(|entry| entry.id == id)
            .ok_or("This transcript was deleted.")?;
        if let Some(value) = pinned {
            entry.pinned = value;
        }
        if let Some(value) = archived {
            entry.archived = value;
        }
        Ok(())
    })
}

#[tauri::command]
pub fn dictation_delete(state: State<'_, Dictation>, id: u64) -> Result<()> {
    library::update(&state.dir, |db| {
        db.entries.retain(|entry| entry.id != id);
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn new_or_browser_sessions_cannot_simulate_recording() {
        let dir = tempfile::tempdir().unwrap();
        let dictation = Dictation::new(dir.path().into());
        assert!(dictation.start().is_err());
        assert!(dictation.finish().is_err());
        assert!(dictation.snapshot().phase == Phase::Idle);
    }

    #[test]
    #[ignore = "requires verified model and recorded WAV in VYRRA_TEST_MODEL and VYRRA_TEST_WAV"]
    fn desktop_decodes_known_speech_offline() {
        let model = PathBuf::from(std::env::var("VYRRA_TEST_MODEL").unwrap());
        let file = PathBuf::from(std::env::var("VYRRA_TEST_WAV").unwrap());
        let dir = tempfile::tempdir().unwrap();
        let dictation = Dictation::new(dir.path().into());
        dictation
            .prepare(Model::Installing, || {
                engine::install_model(&dictation.model_path(), Some(&model))
            })
            .unwrap();
        library::update(&dictation.dir, |db| {
            db.options.language = Some("en".into());
            Ok(())
        })
        .unwrap();
        dictation.import(&file).unwrap();
        let result = dictation.snapshot();
        assert!(result.phase == Phase::Idle);
        println!("Fixture transcript: {}", result.text);
        let words = result.text.trim_end_matches(['.', '?', '!']).to_lowercase();
        assert_eq!(
            words,
            "please bring the blue notebook to the meeting on friday"
        );
        assert!(library::load(&dictation.dir).unwrap().entries.is_empty());
        let token = dictation.begin().unwrap();
        dictation.cancel();
        dictation.decode(token, Ok(vec![0.5; 16000])).unwrap();
        assert_eq!(dictation.snapshot().revision, result.revision);
        let token = dictation.begin().unwrap();
        assert_eq!(
            dictation.decode(token, Ok(vec![0.0; 32000])),
            Err("No speech was detected.")
        );
        assert_eq!(dictation.snapshot().text, result.text);
    }
}
