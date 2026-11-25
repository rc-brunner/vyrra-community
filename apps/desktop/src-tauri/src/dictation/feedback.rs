use cpal::{
    FromSample, Sample, SizedSample,
    traits::{DeviceTrait, HostTrait, StreamTrait},
};
use serde::{Deserialize, Serialize};
use std::{io::Cursor, sync::mpsc, time::Duration};

#[derive(Clone, Copy, Default, Serialize, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Sound {
    #[default]
    Classic,
    Soft,
    Felt,
    Off,
}

impl Sound {
    fn sample(self, closing: bool) -> Option<&'static [u8]> {
        Some(match (self, closing) {
            (Self::Classic, false) => include_bytes!("../../sounds/engage.wav"),
            (Self::Classic, true) => include_bytes!("../../sounds/release.wav"),
            (Self::Soft, false) => include_bytes!("../../sounds/soft-engage.wav"),
            (Self::Soft, true) => include_bytes!("../../sounds/soft-release.wav"),
            (Self::Felt, false) => include_bytes!("../../sounds/felt-engage.wav"),
            (Self::Felt, true) => include_bytes!("../../sounds/felt-release.wav"),
            (Self::Off, _) => return None,
        })
    }
    pub fn play(self, closing: bool) {
        let Some(bytes) = self.sample(closing) else {
            return;
        };
        let Some(device) = cpal::default_host().default_output_device() else {
            return;
        };
        let Ok(format) = device.default_output_config() else {
            return;
        };
        let Ok(reader) = hound::WavReader::new(Cursor::new(bytes)) else {
            return;
        };
        let source = reader.spec();
        let samples: Vec<f32> = reader
            .into_samples::<i16>()
            .filter_map(std::result::Result::ok)
            .map(|s| s as f32 / 32768.0)
            .collect();
        let config = format.config();
        let channels = usize::from(source.channels);
        let rate = source.sample_rate;
        if channels == 0 || config.channels == 0 {
            return;
        }
        let source: Vec<f32> = samples
            .chunks_exact(channels)
            .map(|f| f.iter().sum::<f32>() / channels as f32)
            .collect();
        macro_rules! play {
            ($t:ty) => {
                output::<$t>(&device, &config, source, rate)
            };
        }
        match format.sample_format() {
            cpal::SampleFormat::F32 => play!(f32),
            cpal::SampleFormat::I16 => play!(i16),
            cpal::SampleFormat::U16 => play!(u16),
            cpal::SampleFormat::I32 => play!(i32),
            cpal::SampleFormat::F64 => play!(f64),
            _ => {}
        }
    }
}

fn output<T: Sample + SizedSample + FromSample<f32>>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    data: Vec<f32>,
    rate: u32,
) {
    let step = f64::from(rate) / f64::from(config.sample_rate.0);
    let mut pos = 0.0;
    let channels = usize::from(config.channels);
    let (sent, done) = mpsc::sync_channel(1);
    let Ok(stream) = device.build_output_stream(
        config,
        move |samples: &mut [T], _| {
            let silent = pos as usize >= data.len();
            for frame in samples.chunks_mut(channels) {
                let n = pos as usize;
                let a = data.get(n).copied().unwrap_or(0.0);
                let b = data.get(n + 1).copied().unwrap_or(0.0);
                frame.fill(T::from_sample(a + (b - a) * (pos - n as f64) as f32));
                pos += step;
            }
            if silent {
                let _ = sent.try_send(());
            }
        },
        |_| {},
        None,
    ) else {
        return;
    };
    if stream.play().is_ok() {
        let _ = done.recv_timeout(Duration::from_millis(180));
    }
}

#[tauri::command]
pub async fn dictation_preview_sound(
    sound: Sound,
    state: tauri::State<'_, super::Dictation>,
    meetings: tauri::State<'_, crate::meetings::Meetings>,
) -> super::engine::Result<()> {
    if state.lock().phase != super::Phase::Idle || meetings.is_recording() {
        return Ok(());
    }

    let _ = tauri::async_runtime::spawn_blocking(move || {
        sound.play(false);
        if sound != Sound::Off {
            std::thread::sleep(Duration::from_millis(150));
            sound.play(true);
        }
    })
    .await
    .map_err(|_| "The audio preview was interrupted.")?;
    Ok(())
}

#[tauri::command]
pub fn dictation_set_feedback(
    state: tauri::State<'_, super::Dictation>,
    sound: Sound,
    panel_sounds: bool,
) -> super::engine::Result<()> {
    super::library::update(&state.dir, |db| {
        db.options.sound = sound;
        db.options.panel_sounds = panel_sounds;
        Ok(())
    })
}
#[tauri::command]
pub async fn panel_sound(
    state: tauri::State<'_, super::Dictation>,
    meetings: tauri::State<'_, crate::meetings::Meetings>,
    closing: bool,
) -> super::engine::Result<()> {
    if state.lock().phase != super::Phase::Idle || meetings.is_recording() {
        return Ok(());
    }
    let dir = state.dir.clone();
    let _ = tauri::async_runtime::spawn_blocking(move || {
        if let Ok(lib) = super::library::load(&dir)
            && lib.options.panel_sounds
        {
            lib.options.sound.play(closing);
        }
    })
    .await
    .map_err(|_| "The audio preview was interrupted.")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_preset_has_distinct_short_open_and_close_cues() {
        for sound in [Sound::Classic, Sound::Soft, Sound::Felt] {
            let open = sound.sample(false).unwrap();
            let close = sound.sample(true).unwrap();
            assert_ne!(open, close);
            for sample in [open, close] {
                let reader = hound::WavReader::new(Cursor::new(sample)).unwrap();
                assert!(reader.duration() * 10 < reader.spec().sample_rate);
            }
        }
        assert!(Sound::Off.sample(true).is_none());
    }
}
