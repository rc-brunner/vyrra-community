use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tempfile::NamedTempFile;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

pub const MODEL_FILE: &str = "ggml-base.bin";
const MODEL_BYTES: u64 = 147_951_465;
const MODEL_SHA256: &str = "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe";
const MODEL_URL: &str = "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin";
const DAMAGED: &str = "The speech model failed its integrity check. Install it again.";

pub type Result<T> = std::result::Result<T, &'static str>;

fn load_bytes(bytes: &[u8]) -> Result<WhisperContext> {
    // The default C debug logger writes individual recognized tokens to stderr.
    // Both hooks discard output with our logging backend features disabled.
    whisper_rs::install_logging_hooks();
    if bytes.len() as u64 != MODEL_BYTES || format!("{:x}", Sha256::digest(bytes)) != MODEL_SHA256 {
        return Err(DAMAGED);
    }
    let mut options = WhisperContextParameters::default();
    options.use_gpu(false);
    WhisperContext::new_from_buffer_with_params(bytes, options)
        .map_err(|_| "The local speech engine could not load the model.")
}

pub fn load_model(path: &Path) -> Result<WhisperContext> {
    let file = File::open(path).map_err(|_| "Install the speech model on this device first.")?;
    let mut bytes = Vec::new();
    file.take(MODEL_BYTES + 1).read_to_end(&mut bytes).map_err(|_| DAMAGED)?;
    load_bytes(&bytes)
}

pub fn install_model(path: &Path, offline: Option<&Path>) -> Result<WhisperContext> {
    let parent = path.parent().ok_or("The model folder is unavailable.")?;
    fs::create_dir_all(parent).map_err(|_| "The model folder could not be opened.")?;
    let mut file = NamedTempFile::new_in(parent).map_err(|_| "There is no space for the model.")?;
    let source: Box<dyn Read> = if let Some(local) = offline {
        Box::new(File::open(local).map_err(|_| "The selected model could not be opened.")?)
    } else {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(900)))
            .https_only(true)
            .build()
            .into();
        let response = agent.get(MODEL_URL).call()
            .map_err(|_| "The model download failed. Retry or choose a downloaded model.")?;
        Box::new(response.into_body().into_reader())
    };
    let bytes = std::io::copy(&mut source.take(MODEL_BYTES + 1), &mut file)
        .map_err(|_| "The model transfer was interrupted. Please retry.")?;
    if bytes != MODEL_BYTES { return Err(DAMAGED); }
    file.flush().map_err(|_| "The model could not be saved.")?;
    let model = load_model(file.path())?;
    file.persist(path).map_err(|_| "The verified model could not be installed.")?;
    Ok(model)
}

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SpeechOptions {
    pub language: Option<String>,
    pub translate_to_english: bool,
    pub vocabulary: Vec<String>,
    pub snippets: Vec<Snippet>,
}

#[derive(Clone, Deserialize, Serialize)]
pub struct Snippet { pub phrase: String, pub text: String }

impl SpeechOptions {
    pub fn validate(&self) -> Result<()> {
        if let Some(lang) = &self.language
            && (lang.is_empty() || lang.len() > 12 || !lang.bytes().all(|b| b.is_ascii_lowercase()) || !whisper_rs::get_lang_id(lang).is_some_and(|id| (0..99).contains(&id))) {
            return Err("Choose a supported source language.");
        }
        if self.vocabulary.len() > 128 || self.vocabulary.iter().any(|word| word.contains('\0') || word.trim().is_empty() || word.chars().count() > 80)
            || self.snippets.len() > 256 || self.snippets.iter().any(|s| s.phrase.trim().is_empty() || s.phrase.chars().count() > 160 || s.text.trim().is_empty() || s.text.len() > 8192) {
            return Err("Check the length and contents of your dictionary or snippets.");
        }
        Ok(())
    }
}

fn spoken_phrase(s: &str) -> String {
    s.trim().trim_end_matches(['.', '?', '!']).trim_end().to_lowercase()
}

pub fn transcribe(model: &WhisperContext, audio: &[f32], options: &SpeechOptions) -> Result<String> {
    options.validate()?;
    // Silence and very short clicks otherwise cause Whisper to invent a closing phrase.
    if audio.len() < 3_200 || !audio.chunks(320).any(|frame| frame.iter().map(|s| s*s).sum::<f32>() / frame.len() as f32 > 0.000004) {
        return Err("No speech was detected.");
    }
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_n_threads(std::thread::available_parallelism().map_or(2, |v| v.get().clamp(1, 6)) as i32);
    params.set_language(options.language.as_deref());
    params.set_translate(options.translate_to_english);
    params.set_no_context(true);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_suppress_blank(true);
    if !options.vocabulary.is_empty() { params.set_initial_prompt(&options.vocabulary.join(", ")); }
    let mut state = model.create_state().map_err(|_| "The device could not allocate memory for transcription.")?;
    // Whisper requires roughly a second of input, including for a single spoken word.
    let mut padded = Vec::new();
    let input = if audio.len() < 16_000 {
        padded.extend_from_slice(audio);
        padded.resize(16_000, 0.0);
        &padded[..]
    } else { audio };
    state.full(params, input).map_err(|_| "Local transcription failed.")?;
    let mut text = String::new();
    for segment in state.as_iter() {
        if segment.no_speech_probability() < 0.8 {
            text.push_str(&segment.to_str_lossy().map_err(|_| "A transcript segment could not be read.")?);
        }
    }
    let text = text.trim();
    if text.is_empty() { return Err("No speech was detected."); }
    let phrase = spoken_phrase(text);
    Ok(options.snippets.iter().find(|s| spoken_phrase(&s.phrase) == phrase)
        .map_or_else(|| text.to_owned(), |s| s.text.clone()))
}
