use std::{sync::{Mutex, mpsc}, thread, time::Duration};
use tauri::{AppHandle, Manager, PhysicalPosition};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

use super::{Dictation, Phase, engine::Result, insertion::Insertion, library};

#[derive(Default)]
pub struct Hotkeys(Mutex<bool>);

fn keys() -> [Shortcut; 2] {
    [Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::Space),
     Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::Space)]
}

fn show_indicator(app: &AppHandle) -> Result<()> {
    let panel = app.get_webview_window("indicator").ok_or("The recording indicator is unavailable.")?;
    if let Ok(Some(monitor)) = panel.current_monitor() {
        let frame = monitor.work_area();
        let scale = monitor.scale_factor();
        let width = (254.0 * scale) as i32;
        let bottom = (86.0 * scale) as i32;
        let _ = panel.set_position(PhysicalPosition::new(
            frame.position.x + (frame.size.width as i32 - width) / 2,
            frame.position.y + frame.size.height as i32 - bottom));
    }
    panel.show().map_err(|_| "The recording indicator could not be shown.")
}

fn watch_indicator(app: AppHandle, d: Dictation, token: u64) {
    thread::spawn(move || {
        loop {
            thread::sleep(Duration::from_millis(150));
            let session = d.lock();
            if session.token != token || session.phase == Phase::Idle { break; }
        }
        thread::sleep(Duration::from_millis(1400));
        if d.lock().phase == Phase::Idle && let Some(panel) = app.get_webview_window("indicator") { let _ = panel.hide(); }
    });
}

fn set(app: &AppHandle, enable: bool) -> Result<()> {
    let state = app.state::<Hotkeys>();
    let mut installed = state.0.lock().unwrap_or_else(|e| e.into_inner());
    if *installed == enable { return Ok(()); }
    let [hold, toggle] = keys();
    let global = app.global_shortcut();
    if !enable {
        global.unregister_multiple([hold, toggle]).map_err(|_| "The shortcuts could not be released.")?;
        app.state::<Dictation>().cancel_external();
        *installed = false;
        return Ok(());
    }
    let (sender, events) = mpsc::channel();
    for (i, key) in [hold, toggle].into_iter().enumerate() {
        let tx = sender.clone();
        if global.on_shortcut(key, move |_, shortcut, event| { let _ = tx.send((shortcut.id(), event.state)); }).is_err() {
            if i == 1 { let _ = global.unregister(hold); }
            return Err("Another app is using a dictation shortcut. Release it in that app and retry.");
        }
    }
    let app = app.clone();
    thread::spawn(move || {
        let d = app.state::<Dictation>().inner().clone();
        let mut down = [false; 2];
        let mut active: Option<(usize, u64)> = None;
        for (id, event) in events {
            let index = usize::from(id == toggle.id());
            let pressed = event == ShortcutState::Pressed;
            if down[index] == pressed { continue; }
            down[index] = pressed;
            let (phase, current) = { let s = d.lock(); (s.phase, s.token) };
            if phase == Phase::Idle || !active.is_some_and(|(_, token)| token == current) { active = None; }
            if let Some((kind, token)) = active {
                if kind == index && ((index == 0 && !pressed) || (index == 1 && pressed)) {
                    active = None;
                    let d = d.clone();
                    tauri::async_runtime::spawn_blocking(move || { let _ = d.finish_external(token); });
                }
                continue;
            }
            if !pressed || phase != Phase::Idle { continue; }
            let Ok(token) = d.begin() else { continue; };
            // Capture only the identity of the original editable control before showing the panel.
            let target = Insertion::remember();
            {
                let mut s = d.lock();
                if s.token != token { continue; }
                s.external = true;
                s.target = target;
            }
            if let Err(error) = show_indicator(&app) {
                d.cancel();
                d.lock().error = Some(error.into());
                continue;
            }
            active = Some((index, token));
            watch_indicator(app.clone(), d.clone(), token);
            let d = d.clone();
            tauri::async_runtime::spawn_blocking(move || { let _ = d.open_microphone(token); });
        }
    });
    *installed = true;
    Ok(())
}

pub fn restore(app: AppHandle, d: &Dictation) {
    app.manage(Hotkeys::default());
    if library::load(&d.dir).is_ok_and(|db| db.shortcuts) {
        let d = d.clone();
        tauri::async_runtime::spawn_blocking(move || {
            if let Err(message) = set(&app, true) { d.lock().error = Some(message.into()); }
        });
    }
}

#[tauri::command]
pub fn dictation_hotkeys(state: tauri::State<'_, Hotkeys>) -> bool {
    *state.0.lock().unwrap_or_else(|e| e.into_inner())
}

#[tauri::command]
pub async fn dictation_set_hotkeys(app: AppHandle, enabled: bool) -> Result<()> {
    super::blocking(move || {
        let d = app.state::<Dictation>();
        if enabled && d.lock().model != super::Model::Ready { return Err("Install the local speech model before enabling shortcuts."); }
        set(&app, enabled)?;
        if let Err(error) = library::update(&d.dir, |db| { db.shortcuts = enabled; Ok(()) }) {
            let _ = set(&app, !enabled);
            return Err(error);
        }
        Ok(())
    }).await
}
