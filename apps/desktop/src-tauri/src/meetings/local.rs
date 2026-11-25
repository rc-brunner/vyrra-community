use super::{Event, Meetings, Result};
use crate::dictation::{Dictation, audio::Microphone};
use std::{
    sync::atomic::Ordering,
    time::{Duration, Instant},
};
use tauri::{AppHandle, Manager};

pub fn sources() -> Vec<(&'static str, &'static str)> {
    #[cfg(target_os = "macos")]
    {
        vec![
            ("com.apple.Safari", "Safari"),
            ("com.google.Chrome", "Google Chrome"),
            ("com.microsoft.edgemac", "Microsoft Edge"),
            ("us.zoom.xos", "Zoom"),
            ("com.microsoft.teams2", "Microsoft Teams"),
        ]
    }
    #[cfg(target_os = "windows")]
    {
        vec![("system", "System audio · all apps")]
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        vec![]
    }
}
#[cfg(target_os = "macos")]
struct RemoteAudio(std::ptr::NonNull<std::ffi::c_void>);
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn vyrra_meeting_audio_open(id: *const std::ffi::c_char) -> *mut std::ffi::c_void;
    fn vyrra_meeting_audio_read(
        handle: *mut std::ffi::c_void,
        dest: *mut f32,
        capacity: i32,
    ) -> i32;
    fn vyrra_meeting_audio_close(handle: *mut std::ffi::c_void);
}
#[cfg(target_os = "macos")]
impl RemoteAudio {
    fn open(source: &str) -> Result<Self> {
        let id = std::ffi::CString::new(source).map_err(|_| "Unknown meeting audio source.")?;
        // Swift retains the stream until Drop on this same worker.
        let handle = unsafe { vyrra_meeting_audio_open(id.as_ptr()) };
        std::ptr::NonNull::new(handle).map(Self).ok_or("Meeting audio unavailable. Open the selected app and allow Screen & System Audio Recording in System Settings.")
    }
    fn drain(&self) -> Result<Vec<f32>> {
        let mut samples = vec![0.0; 16000 * 120];
        let n = unsafe {
            vyrra_meeting_audio_read(self.0.as_ptr(), samples.as_mut_ptr(), samples.len() as i32)
        };
        if n < 0 {
            return Err("Meeting audio was interrupted.");
        }
        samples.truncate(n as usize);
        Ok(samples)
    }
}
#[cfg(target_os = "macos")]
impl Drop for RemoteAudio {
    fn drop(&mut self) {
        unsafe { vyrra_meeting_audio_close(self.0.as_ptr()) };
    }
}
#[cfg(not(target_os = "macos"))]
struct RemoteAudio(Microphone);
#[cfg(not(target_os = "macos"))]
impl RemoteAudio {
    fn open(_source: &str) -> Result<Self> {
        #[cfg(target_os = "windows")]
        {
            Microphone::loopback().map(Self)
        }
        #[cfg(not(target_os = "windows"))]
        {
            Err("Local meeting audio is unavailable on this platform.")
        }
    }
    fn drain(&self) -> Result<Vec<f32>> {
        self.0.drain()
    }
}
fn launch(event: &Event, source: &str) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        let s = std::process::Command::new("/usr/bin/open")
            .args(["-b", source, &event.url])
            .status();
        if s.is_ok_and(|s| s.success()) {
            return Ok(());
        }
        Err("The selected meeting application could not open the call.")
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = source;
        open::that_detached(&event.url).map_err(|_| "The meeting link could not be opened.")
    }
}
fn append(d: &Dictation, label: &str, pcm: Vec<f32>, lines: &mut Vec<String>) -> Result<()> {
    match d.meeting_text(&pcm) {
        Ok(s) => lines.push(format!("{label}: {s}")),
        Err("No speech was detected.") => (),
        Err(error) => return Err(error),
    };
    Ok(())
}
pub fn run(
    app: &AppHandle,
    state: &Meetings,
    event: &Event,
    source: &str,
    key: &str,
) -> Result<()> {
    let d = app.state::<Dictation>();
    if !d.meeting_ready() {
        return Err("Install the local speech model before the meeting starts.");
    }
    let panel = app
        .get_webview_window("meeting-indicator")
        .ok_or("The meeting indicator is unavailable.")?;
    panel
        .show()
        .map_err(|_| "The visible meeting indicator could not open.")?;
    launch(event, source)?;
    // Wait for the chosen application to open. The always-on-top stop control is already visible.
    for _ in 0..12 {
        if state.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    let remote = RemoteAudio::open(source)?;
    if state.stop.load(Ordering::Acquire) {
        return Ok(());
    }
    let mic = Microphone::open()?;
    state.change(key, |p| {
        p.phase = "taking_notes".into();
        Ok(())
    })?;
    let mut last = Instant::now();
    loop {
        let done = state.stop.load(Ordering::Acquire) || super::now() >= event.end_ms;
        if done || last.elapsed() >= Duration::from_secs(24) {
            let remote_pcm = remote.drain()?;
            let mic_pcm = mic.drain()?;
            let mut lines = Vec::new();
            append(&d, "Meeting audio", remote_pcm, &mut lines)?;
            append(&d, "Microphone", mic_pcm, &mut lines)?;
            if !lines.is_empty() {
                state.change(key, |p| {
                    if !p.transcript.is_empty() {
                        p.transcript.push('\n');
                    }
                    p.transcript.push_str(&lines.join("\n"));
                    Ok(())
                })?;
            }
            last = Instant::now();
        }
        if done {
            break;
        }
        std::thread::sleep(Duration::from_millis(180));
    }
    Ok(())
}
