use std::{path::Path, sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}}};

use std::{sync::mpsc, thread};
use cpal::{FromSample, Sample, SampleFormat, SizedSample, traits::{DeviceTrait, HostTrait, StreamTrait}};
use super::engine::Result;

const OUTPUT_RATE: u32 = 16_000;

// Integrate each source frame across its share of a 16 kHz output frame.
// The fractional phase survives callback boundaries, including at 44.1 kHz.
struct Pcm {
    rate: u32,
    filled: u32,
    sum: f64,
    samples: Vec<f32>,
    peak: f32,
}

impl Pcm {
    fn new(rate: u32) -> Result<Self> {
        if !(1_000..=768_000).contains(&rate) { return Err("This audio sample rate is unsupported."); }
        Ok(Self { rate, filled: 0, sum: 0.0, samples: Vec::new(), peak: 0.0 })
    }

    fn frame(&mut self, value: f32) {
        let value = if value.is_finite() { value.clamp(-1.0, 1.0) } else { 0.0 };
        let mut weight = OUTPUT_RATE;
        while weight > 0 {
            let used = weight.min(self.rate - self.filled);
            self.sum += f64::from(value) * f64::from(used);
            self.filled += used;
            weight -= used;
            if self.filled == self.rate {
                self.samples.push((self.sum / f64::from(self.rate)) as f32);
                self.filled = 0;
                self.sum = 0.0;
            }
        }
    }
}

type AudioBuffer = Arc<Mutex<Pcm>>;
type Failure = Arc<AtomicBool>;
enum Control { Pause(mpsc::Sender<Result<()>>), Resume(mpsc::Sender<Result<()>>), Stop }

pub struct Microphone {
    commands: mpsc::Sender<Control>,
    owner: Option<thread::JoinHandle<()>>,
    pcm: AudioBuffer,
    failed: Failure,
}

fn open_stream() -> Result<(cpal::Stream, AudioBuffer, Failure)> {
        #[cfg(target_os = "macos")]
        authorize_microphone()?;
        let device = cpal::default_host().default_input_device().ok_or("Connect a microphone and try again.")?;
        let format = device.default_input_config().map_err(|_| "Microphone unavailable. Check device and microphone permissions.")?;
        let config = format.config();
        let pcm = Arc::new(Mutex::new(Pcm::new(config.sample_rate.0)?));
        let failed = Arc::new(AtomicBool::new(false));
        macro_rules! build {
            ($sample:ty) => { input::<$sample>(&device, &config, pcm.clone(), failed.clone()) };
        }
        let stream = match format.sample_format() {
            SampleFormat::I8 => build!(i8),
            SampleFormat::I16 => build!(i16),
            SampleFormat::I32 => build!(i32),
            SampleFormat::I64 => build!(i64),
            SampleFormat::U8 => build!(u8),
            SampleFormat::U16 => build!(u16),
            SampleFormat::U32 => build!(u32),
            SampleFormat::U64 => build!(u64),
            SampleFormat::F32 => build!(f32),
            SampleFormat::F64 => build!(f64),
            _ => return Err("This microphone sample format is unsupported."),
        }?;
        stream.play().map_err(|_| "The microphone could not start. Check microphone access.")?;
        Ok((stream, pcm, failed))
}

#[cfg(target_os = "macos")]
fn authorize_microphone() -> Result<()> {
    use objc2_av_foundation::{AVAuthorizationStatus as Status, AVCaptureDevice, AVMediaTypeAudio};
    let kind = unsafe { AVMediaTypeAudio }.ok_or("The microphone is unavailable.")?;
    let allowed = match unsafe { AVCaptureDevice::authorizationStatusForMediaType(kind) } {
        Status::Authorized => true,
        Status::NotDetermined => {
            let (send, receive) = mpsc::channel();
            let answer = block2::RcBlock::new(move |granted: objc2::runtime::Bool| { let _ = send.send(granted.as_bool()); });
            unsafe { AVCaptureDevice::requestAccessForMediaType_completionHandler(kind, &answer); }
            receive.recv().unwrap_or(false)
        }
        _ => false,
    };
    allowed.then_some(()).ok_or("Allow Vyrra Desktop in System Settings → Privacy & Security → Microphone.")
}

impl Microphone {
    pub fn open() -> Result<Self> {
        let (commands, controls) = mpsc::channel();
        let (ready, opened) = mpsc::sync_channel(1);
        // CoreAudio and WASAPI streams must stay on their owning thread.
        let owner = thread::Builder::new().name("vyrra-microphone".into()).spawn(move || {
            let (stream, pcm, failed) = match open_stream() {
                Ok(opened) => opened,
                Err(err) => { let _ = ready.send(Err(err)); return; }
            };
            if ready.send(Ok((pcm, failed))).is_err() { return; }
            for control in controls {
                match control {
                    Control::Pause(reply) => { let _ = reply.send(stream.pause().map_err(|_| "The microphone could not pause.")); }
                    Control::Resume(reply) => { let _ = reply.send(stream.play().map_err(|_| "The microphone could not resume.")); }
                    Control::Stop => break,
                }
            }
        }).map_err(|_| "The microphone worker could not start.")?;
        let (pcm, failed) = opened.recv().map_err(|_| "The microphone worker was interrupted.")??;
        Ok(Self { commands, owner: Some(owner), pcm, failed })
    }

    fn request(&self, control: impl FnOnce(mpsc::Sender<Result<()>>) -> Control) -> Result<()> {
        let (tx, rx) = mpsc::channel();
        self.commands.send(control(tx)).map_err(|_| "The microphone disconnected.")?;
        rx.recv().map_err(|_| "The microphone disconnected.")?
    }
    pub fn pause(&self) -> Result<()> { self.request(Control::Pause) }
    pub fn resume(&self) -> Result<()> { self.request(Control::Resume) }
    fn stop(&mut self) {
        let _ = self.commands.send(Control::Stop);
        if let Some(owner) = self.owner.take() { let _ = owner.join(); }
    }

    pub fn metrics(&self) -> (u64, f32, bool) {
        let data = self.pcm.lock().unwrap_or_else(|e| e.into_inner());
        (data.samples.len() as u64 / 16, data.peak, self.failed.load(Ordering::Relaxed))
    }

    pub fn finish(mut self) -> Result<Vec<f32>> {
        self.stop();
        if self.failed.load(Ordering::Relaxed) { return Err("The microphone disconnected or ran out of memory. Try recording again."); }
        let mut data = self.pcm.lock().unwrap_or_else(|e| e.into_inner());
        Ok(std::mem::take(&mut data.samples))
    }
}

impl Drop for Microphone { fn drop(&mut self) { self.stop(); } }

fn input<T: Sample + SizedSample>(
    device: &cpal::Device, config: &cpal::StreamConfig, pcm: Arc<Mutex<Pcm>>, failed: Arc<AtomicBool>
) -> Result<cpal::Stream> where f32: FromSample<T> {
    let channels = usize::from(config.channels);
    if channels == 0 { return Err("The microphone has no input channels."); }
    let broken = failed.clone();
    device.build_input_stream(config, move |data: &[T], _| {
        if failed.load(Ordering::Relaxed) { return; }
        let mut pcm = pcm.lock().unwrap_or_else(|e| e.into_inner());
        let count = (data.len() / channels * OUTPUT_RATE as usize).div_ceil(pcm.rate as usize) + 1;
        if pcm.samples.try_reserve(count).is_err() {
            failed.store(true, Ordering::Relaxed);
            return;
        }
        let mut peak: f32 = 0.0;
        for frame in data.chunks_exact(channels) {
            let sample = frame.iter().map(|v| v.to_sample::<f32>()).sum::<f32>() / channels as f32;
            peak = peak.max(sample.abs());
            pcm.frame(sample);
        }
        pcm.peak = (peak * 3.0).min(1.0).max(pcm.peak * 0.75);
    }, move |_| broken.store(true, Ordering::Relaxed), None)
    .map_err(|_| "Microphone access failed. Allow Vyrra in your system microphone settings.")
}

pub fn read_wav(path: &Path) -> Result<Vec<f32>> {
    let mut reader = hound::WavReader::open(path).map_err(|_| "Choose an uncompressed WAV audio file.")?;
    let spec = reader.spec();
    if spec.channels == 0 || spec.channels > 32 { return Err("Unsupported audio channel layout."); }
    let mut pcm = Pcm::new(spec.sample_rate)?;
    let mut index = 0;
    let mut sum = 0.0;
    let mut consume = |sample: f32| -> Result<()> {
        sum += sample;
        index += 1;
        if index == spec.channels {
            if pcm.samples.len() == pcm.samples.capacity() {
                pcm.samples.try_reserve(OUTPUT_RATE as usize).map_err(|_| "The device ran out of memory reading this file.")?;
            }
            pcm.frame(sum / f32::from(index));
            index = 0;
            sum = 0.0;
        }
        Ok(())
    };
    const INVALID: &str = "The WAV audio data is incomplete or unsupported.";
    match spec.sample_format {
        hound::SampleFormat::Float => {
            for s in reader.samples::<f32>() { consume(s.map_err(|_| INVALID)?)?; }
        }
        hound::SampleFormat::Int if (1..=32).contains(&spec.bits_per_sample) => {
            let scale = (1u64 << (spec.bits_per_sample - 1)) as f32;
            for s in reader.samples::<i32>() { consume(s.map_err(|_| INVALID)? as f32 / scale)?; }
        }
        _ => return Err(INVALID),
    }
    if index != 0 { return Err(INVALID); }
    Ok(pcm.samples)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sample_rate_and_amplitude_are_preserved() {
        for rate in [8_000, 16_000, 44_100, 48_000, 96_000] {
            let mut pcm = Pcm::new(rate).unwrap();
            for _ in 0..rate { pcm.frame(0.25); }
            assert_eq!(pcm.samples.len(), 16_000);
            assert!(pcm.samples.iter().all(|s| (*s - 0.25).abs() < 0.0001));
        }
    }
}
