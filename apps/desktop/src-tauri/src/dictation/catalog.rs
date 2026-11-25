// The allowlist is compiled into the app. Downloads never choose a runtime or a destination.
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock},
};
use tauri::State;
use whisper_rs::WhisperContext;

use super::{
    Dictation, Model, Phase, blocking,
    engine::{self, Result, SpeechOptions},
    library,
};

pub const DEFAULT_ID: &str = "base";
const RELEASE: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1";
static MODELS: LazyLock<Vec<SpeechModel>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../../speech-models.json"))
        .expect("compiled speech manifest")
});

#[derive(Deserialize)]
pub struct SpeechModel {
    pub id: &'static str,
    pub name: &'static str,
    pub bytes: u64,
    pub sha256: &'static str,
    pub languages: i32,
    pub translation: bool,
}

pub fn find(id: &str) -> Result<&'static SpeechModel> {
    MODELS
        .iter()
        .find(|model| model.id == id)
        .ok_or("Unknown local speech model.")
}
impl SpeechModel {
    fn filename(&self) -> String {
        format!("ggml-{}.bin", self.id)
    }
    pub fn path(&self, dir: &Path) -> PathBuf {
        dir.join("models").join(self.filename())
    }
    pub fn url(&self) -> String {
        format!("{RELEASE}/{}", self.filename())
    }
    fn on_disk(&self, dir: &Path) -> bool {
        self.path(dir)
            .metadata()
            .is_ok_and(|file| file.is_file() && file.len() == self.bytes)
    }
    pub fn check_options(&self, options: &SpeechOptions) -> Result<()> {
        if options.translate_to_english && !self.translation {
            return Err(
                "Turn off English translation in Settings, or choose a multilingual model that supports it.",
            );
        }
        if let Some(code) = &options.language {
            let id = whisper_rs::get_lang_id(code).ok_or("Unknown spoken language.")?;
            if id >= self.languages {
                return Err(
                    "Choose a compatible spoken language in Settings, or use another speech model.",
                );
            }
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum Stage {
    Transferring,
    Importing,
    Verifying,
}
#[derive(Clone, Serialize)]
pub struct Job {
    id: &'static str,
    stage: Stage,
    received: u64,
    #[serde(skip)]
    cancel: bool,
}
#[derive(Serialize)]
pub struct Catalog {
    installed: Vec<&'static str>,
    active: Option<&'static str>,
    job: Option<Job>,
    idle: bool,
}

impl Dictation {
    fn catalog(&self) -> Catalog {
        let installed = MODELS
            .iter()
            .filter(|m| m.on_disk(&self.dir))
            .map(|m| m.id)
            .collect();
        let s = self.lock();
        Catalog {
            installed,
            active: s.active.map(|m| m.id),
            job: s.model_job.clone(),
            idle: s.phase == Phase::Idle,
        }
    }
    pub(super) fn prepare_existing(&self) {
        let result = library::load(&self.dir).and_then(|db| {
            let model = find(&db.speech_model)?;
            if model.path(&self.dir).is_file() {
                self.activate(model, Model::Checking, None)
            } else {
                Ok(())
            }
        });
        if let Err(error) = result {
            self.lock().error = Some(error.into());
        }
    }
    pub(super) fn activate(
        &self,
        model: &'static SpeechModel,
        mode: Model,
        import: Option<&Path>,
    ) -> Result<()> {
        {
            let mut s = self.lock();
            if s.phase != Phase::Idle || s.model_job.is_some() {
                return Err("Finish the current operation before changing models.");
            }
            if s.active.is_some_and(|m| m.id == model.id) && mode == Model::Checking {
                return Ok(());
            }
            model.check_options(&library::load(&self.dir)?.options)?;
            s.model_job = Some(Job {
                id: model.id,
                stage: if mode == Model::Checking {
                    Stage::Verifying
                } else {
                    Stage::Transferring
                },
                received: 0,
                cancel: false,
            });
            s.model = mode;
            s.error = None;
        }
        let progress = |stage: Stage, received: u64| {
            let mut s = self.lock();
            let job = s.model_job.as_mut().ok_or("Model setup ended.")?;
            if job.cancel {
                return Err("Model setup canceled.");
            }
            job.stage = if stage == Stage::Transferring && import.is_some() {
                Stage::Importing
            } else {
                stage
            };
            job.received = received;
            Ok(())
        };
        let path = model.path(&self.dir);
        let loaded = if mode == Model::Checking {
            engine::load_model(model, &path, progress)
        } else {
            engine::install_model(model, &path, import, progress)
        };
        let mut s = self.lock();
        let canceled = s.model_job.take().is_some_and(|j| j.cancel);
        let result = if canceled {
            Err("Model setup canceled.")
        } else {
            loaded.and_then(|context| {
                library::update(&self.dir, |db| {
                    model.check_options(&db.options)?;
                    db.speech_model = model.id.into();
                    Ok(())
                })?;
                s.engine = Some(Arc::new(context));
                s.active = Some(model);
                Ok(())
            })
        };
        s.model = if s.engine.is_some() {
            Model::Ready
        } else {
            Model::Missing
        };
        if let Err(msg) = result
            && !canceled
        {
            s.error = Some(msg.into());
        }
        result
    }
    fn remove_model(&self, model: &SpeechModel) -> Result<()> {
        let mut s = self.lock();
        if s.phase != Phase::Idle || s.model_job.is_some() {
            return Err("Finish the current operation before removing a model.");
        }
        match fs::remove_file(model.path(&self.dir)) {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Err("The model could not be removed."),
        }
        if s.active.is_some_and(|m| m.id == model.id) {
            s.active = None;
            s.engine = None;
            s.model = Model::Missing;
        }
        s.error = None;
        Ok(())
    }
}

#[tauri::command]
pub fn dictation_models(state: State<'_, Dictation>) -> Catalog {
    state.catalog()
}
#[tauri::command]
pub async fn dictation_select_model(id: String, state: State<'_, Dictation>) -> Result<()> {
    let state = state.inner().clone();
    let model = find(&id)?;
    blocking(move || state.activate(model, Model::Checking, None)).await
}
#[tauri::command]
pub fn dictation_remove_model(id: String, state: State<'_, Dictation>) -> Result<()> {
    state.remove_model(find(&id)?)
}
#[tauri::command]
pub fn dictation_cancel_setup(state: State<'_, Dictation>) {
    if let Some(job) = state.lock().model_job.as_mut() {
        job.cancel = true;
    }
}

pub(crate) struct MeetingDecoder {
    pub engine: Arc<WhisperContext>,
    pub options: SpeechOptions,
    pub worker: Arc<std::sync::Mutex<()>>,
}
impl MeetingDecoder {
    pub fn transcribe(&self, pcm: &[f32]) -> Result<String> {
        let _worker = self.worker.lock().unwrap_or_else(|e| e.into_inner());
        engine::transcribe(&self.engine, pcm, &self.options)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Source {
    Whisper,
    Qwen,
    Tokenizer,
    Folder,
}

#[tauri::command]
pub fn model_source(source: Source, state: State<'_, Dictation>) -> Result<()> {
    let result = match source {
        Source::Whisper => open::that_detached(
            "https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1",
        ),
        Source::Qwen => open::that_detached(
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/tree/91cad51170dc346986eccefdc2dd33a9da36ead9",
        ),
        Source::Tokenizer => open::that_detached(
            "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/blob/989aa7980e4cf806f80c7fef2b1adb7bc71aa306/tokenizer.json",
        ),
        Source::Folder => {
            let folder = state.dir.join("models");
            fs::create_dir_all(&folder).map_err(|_| "The models folder is unavailable.")?;
            open::that_detached(folder)
        }
    };
    result.map_err(|_| "The model source could not be opened.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    #[test]
    fn manifest_has_unique_files_and_matches_language_and_translation_choices() {
        let mut ids = HashSet::new();
        for model in MODELS.iter() {
            assert!(ids.insert(model.id));
            assert!(
                model.bytes > 0
                    && model.sha256.len() == 64
                    && model.sha256.bytes().all(|b| b.is_ascii_hexdigit())
            );
            assert!(model.url().starts_with(RELEASE));
        }
        assert!(find("../elsewhere").is_err());
        let spanish = SpeechOptions {
            language: Some("es".into()),
            ..Default::default()
        };
        assert!(find("tiny.en").unwrap().check_options(&spanish).is_err());
        let translate = SpeechOptions {
            translate_to_english: true,
            ..spanish
        };
        assert!(
            find("large-v3-turbo")
                .unwrap()
                .check_options(&translate)
                .is_err()
        );
        assert!(find(DEFAULT_ID).unwrap().check_options(&translate).is_ok());
        let dir = tempfile::tempdir().unwrap();
        fs::write(
            dir.path().join("dictation-v1.json"),
            r#"{"shortcuts":true,"entries":[]}"#,
        )
        .unwrap();
        let db = library::load(dir.path()).unwrap();
        assert_eq!(db.speech_model, DEFAULT_ID);
        assert!(db.shortcuts);
    }
    #[test]
    fn interrupted_truncated_or_corrupt_imports_leave_the_original_file_intact() {
        let dir = tempfile::tempdir().unwrap();
        let model = SpeechModel {
            id: "test",
            name: "Test",
            bytes: 4,
            sha256: "0",
            languages: 1,
            translation: false,
        };
        let dest = model.path(dir.path());
        fs::create_dir_all(dest.parent().unwrap()).unwrap();
        fs::write(&dest, b"old").unwrap();
        let src = dir.path().join("incoming.bin");
        for data in [&b"bad"[..], &b"xxxx"[..], &b"toolong"[..]] {
            fs::write(&src, data).unwrap();
            assert!(engine::install_model(&model, &dest, Some(&src), |_, _| Ok(())).is_err());
            assert_eq!(fs::read(&dest).unwrap(), b"old");
        }
        assert!(matches!(
            engine::install_model(&model, &dest, Some(&src), |_, _| Err("canceled")),
            Err("canceled")
        ));
        assert_eq!(fs::read_dir(dest.parent().unwrap()).unwrap().count(), 1);
        assert_eq!(fs::read(&dest).unwrap(), b"old");
    }

    #[test]
    #[ignore = "requires VYRRA_TEST_MODELS_DIR and VYRRA_TEST_WAV"]
    fn every_catalog_model_transcribes_and_survives_switches_offline() {
        let files = PathBuf::from(std::env::var("VYRRA_TEST_MODELS_DIR").unwrap());
        let wav = PathBuf::from(std::env::var("VYRRA_TEST_WAV").unwrap());
        let dir = tempfile::tempdir().unwrap();
        let d = Dictation::new(dir.path().into());
        for model in MODELS.iter() {
            d.activate(
                model,
                Model::Installing,
                Some(&files.join(model.filename())),
            )
            .unwrap();
            assert_eq!(d.catalog().active, Some(model.id));
            d.import(&wav).unwrap();
            let text = d.snapshot().text.to_lowercase().replace(' ', "");
            println!("{}: {}", model.id, d.snapshot().text);
            assert!(
                text.contains("blue") && text.contains("notebook") && text.contains("friday"),
                "{}",
                model.id
            );
        }
        let last = MODELS.last().unwrap();
        let pinned = d.meeting_decoder().unwrap();
        assert!(
            d.activate(find(DEFAULT_ID).unwrap(), Model::Installing, Some(&wav))
                .is_err()
        );
        assert_eq!(d.catalog().active, Some(last.id));
        drop(d);
        let reopened = Dictation::new(dir.path().into());
        reopened.prepare_existing();
        assert_eq!(reopened.catalog().active, Some(last.id));
        reopened.remove_model(last).unwrap();
        assert!(reopened.catalog().active.is_none());
        assert!(
            pinned
                .transcribe(&super::super::audio::read_wav(&wav).unwrap())
                .unwrap()
                .to_lowercase()
                .contains("blue")
        );
        assert!(!last.path(dir.path()).exists());
        reopened
            .activate(find(DEFAULT_ID).unwrap(), Model::Checking, None)
            .unwrap();
        assert_eq!(reopened.catalog().active, Some(DEFAULT_ID));
    }
    #[test]
    #[ignore = "downloads one pinned public model, never records audio"]
    fn native_download_verifies_and_selects_tiny() {
        let dir = tempfile::tempdir().unwrap();
        let d = Dictation::new(dir.path().into());
        d.activate(find("tiny").unwrap(), Model::Installing, None)
            .unwrap();
        assert_eq!(d.catalog().active, Some("tiny"));
    }
    #[test]
    #[ignore = "requires VYRRA_TEST_MODEL and a synthetic Spanish VYRRA_TEST_SPANISH_WAV"]
    fn spanish_speech_and_english_translation_use_the_same_local_model() {
        let dir = tempfile::tempdir().unwrap();
        let d = Dictation::new(dir.path().into());
        let model = PathBuf::from(std::env::var("VYRRA_TEST_MODEL").unwrap());
        let wav = PathBuf::from(std::env::var("VYRRA_TEST_SPANISH_WAV").unwrap());
        d.activate(find(DEFAULT_ID).unwrap(), Model::Installing, Some(&model))
            .unwrap();
        for (translate, expected) in [(false, "biblioteca"), (true, "library")] {
            library::update(&d.dir, |db| {
                db.options.language = Some("es".into());
                db.options.translate_to_english = translate;
                Ok(())
            })
            .unwrap();
            d.import(&wav).unwrap();
            let text = d.snapshot().text.to_lowercase();
            println!("Translate {translate}: {text}");
            assert!(text.contains(expected));
        }
    }
}
