use std::{env, fs, time::Instant};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

fn main() {
    let model = fs::read(env::args_os().nth(1).unwrap()).unwrap();
    let bytes = fs::read(env::args_os().nth(2).unwrap()).unwrap();
    let audio: Vec<_> = bytes
        .chunks_exact(4)
        .map(|b| f32::from_le_bytes(b.try_into().unwrap()))
        .collect();
    let mut config = WhisperContextParameters::default();
    config.use_gpu(false);
    let ctx = WhisperContext::new_from_buffer_with_params(&model, config).unwrap();
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_n_threads(4);
    params.set_language(None);
    params.set_no_context(true);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_suppress_blank(true);
    let start = Instant::now();
    let mut state = ctx.create_state().unwrap();
    state.full(params, &audio).unwrap();
    let text: String = state
        .as_iter()
        .map(|s| s.to_str_lossy().unwrap().into_owned())
        .collect();
    println!(
        "Cargo speech engine took {:.2} seconds for {:.2} seconds of audio: {}",
        start.elapsed().as_secs_f64(),
        audio.len() as f64 / 16000.0,
        text.trim()
    );
    assert!(text.contains("blue notebook") && text.contains("design review"));
}
