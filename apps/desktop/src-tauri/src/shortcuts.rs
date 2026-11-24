use std::{
    fs,
    path::PathBuf,
    sync::{
        Arc, RwLock,
        atomic::{AtomicBool, Ordering},
    },
};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};

use crate::native::{self, NativeActionState};

const SHORTCUT_SCHEMA_VERSION: u8 = 1;
const SHORTCUT_FILE_NAME: &str = "shortcuts-v1.json";
const MAX_BINDINGS: usize = 8;
const MIN_INTERVAL_MS: u64 = 150;
const MAX_INTERVAL_MS: u64 = 1_000;
const MIN_PRESS_MS: u64 = 40;
const MAX_PRESS_MS: u64 = 750;

#[derive(Clone, Default)]
pub struct NativeShortcutState {
    bindings: Arc<RwLock<Vec<NativeShortcutBinding>>>,
    compiled: Arc<RwLock<Vec<CompiledDoubleTap>>>,
    listener_started: Arc<AtomicBool>,
    listener_active: Arc<AtomicBool>,
    listener_failed: Arc<AtomicBool>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum NativeShortcutAction {
    QuickClip,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum NativeShortcutKeyLocation {
    Standard,
    Left,
    Right,
    Either,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NativeShortcutKey {
    code: String,
    location: NativeShortcutKeyLocation,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum NativeShortcutGesture {
    DoubleTap {
        key: NativeShortcutKey,
        #[serde(rename = "intervalMs")]
        interval_ms: u64,
        #[serde(rename = "maxPressMs")]
        max_press_ms: u64,
    },
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NativeShortcutBinding {
    action_id: NativeShortcutAction,
    enabled: bool,
    gesture: NativeShortcutGesture,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct ShortcutPreferences {
    schema_version: u8,
    bindings: Vec<NativeShortcutBinding>,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NativeShortcutListenerState {
    Active,
    Starting,
    PermissionRequired,
    ExternalConflict,
    Disabled,
    Failed,
    Unsupported,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NativeExternalShortcutConflict {
    ControlShot,
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NativeShortcutSnapshot {
    bindings: Vec<NativeShortcutBinding>,
    configured_bindings: usize,
    effective_bindings: usize,
    listener_state: NativeShortcutListenerState,
    external_conflict: Option<NativeExternalShortcutConflict>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeShortcutError {
    code: &'static str,
    message: &'static str,
}

impl NativeShortcutError {
    fn new(code: &'static str, message: &'static str) -> Self {
        Self { code, message }
    }

    fn invalid_binding() -> Self {
        Self::new(
            "invalid_shortcut_binding",
            "The shortcut binding is invalid or unsupported.",
        )
    }

    fn duplicate_binding() -> Self {
        Self::new(
            "duplicate_shortcut_binding",
            "Two shortcut bindings overlap.",
        )
    }

    fn persistence_failed() -> Self {
        Self::new(
            "shortcut_persistence_failed",
            "The shortcut preference could not be saved.",
        )
    }
}

#[derive(Clone, Debug)]
struct CompiledDoubleTap {
    action_id: NativeShortcutAction,
    key_code: String,
    virtual_key_codes: Vec<u16>,
    interval_ms: u64,
    max_press_ms: u64,
}

#[tauri::command]
pub fn native_shortcut_configuration(
    state: State<'_, NativeActionState>,
) -> NativeShortcutSnapshot {
    snapshot(&state)
}

#[tauri::command]
pub fn configure_native_shortcuts(
    bindings: Vec<NativeShortcutBinding>,
    app: AppHandle,
    state: State<'_, NativeActionState>,
) -> Result<NativeShortcutSnapshot, NativeShortcutError> {
    let compiled = validate_and_compile(&bindings)?;
    persist_bindings(&app, &bindings)?;

    *state
        .shortcuts
        .bindings
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = bindings;
    set_effective_bindings(&state, compiled);
    ensure_listener(&app, &state);

    Ok(snapshot(&state))
}

#[tauri::command]
pub fn activate_native_shortcuts(
    app: AppHandle,
    state: State<'_, NativeActionState>,
) -> NativeShortcutSnapshot {
    refresh_effective_bindings(&state);
    ensure_listener(&app, &state);
    snapshot(&state)
}

pub fn initialize_native_shortcuts(app: &AppHandle, state: &NativeActionState) {
    match load_bindings(app).and_then(|bindings| {
        let compiled = validate_and_compile(&bindings)?;
        *state
            .shortcuts
            .bindings
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner()) = bindings;
        set_effective_bindings(state, compiled);
        Ok(())
    }) {
        Ok(()) => ensure_listener(app, state),
        Err(error) => {
            state
                .shortcuts
                .listener_failed
                .store(true, Ordering::Release);
            let _ = app.emit("native-shortcut-runtime-error", error);
        }
    }
}

fn validate_and_compile(
    bindings: &[NativeShortcutBinding],
) -> Result<Vec<CompiledDoubleTap>, NativeShortcutError> {
    if bindings.len() > MAX_BINDINGS {
        return Err(NativeShortcutError::invalid_binding());
    }

    let mut compiled = Vec::with_capacity(bindings.len());
    for binding in bindings {
        let NativeShortcutGesture::DoubleTap {
            key,
            interval_ms,
            max_press_ms,
        } = &binding.gesture;

        if *interval_ms < MIN_INTERVAL_MS
            || *interval_ms > MAX_INTERVAL_MS
            || *max_press_ms < MIN_PRESS_MS
            || *max_press_ms > MAX_PRESS_MS
            || max_press_ms > interval_ms
        {
            return Err(NativeShortcutError::invalid_binding());
        }

        let virtual_key_codes =
            platform::virtual_key_codes(key).ok_or_else(NativeShortcutError::invalid_binding)?;
        if virtual_key_codes.is_empty() {
            return Err(NativeShortcutError::invalid_binding());
        }

        if binding.enabled {
            compiled.push(CompiledDoubleTap {
                action_id: binding.action_id,
                key_code: key.code.clone(),
                virtual_key_codes,
                interval_ms: *interval_ms,
                max_press_ms: *max_press_ms,
            });
        }
    }

    for (index, candidate) in compiled.iter().enumerate() {
        if compiled.iter().skip(index + 1).any(|existing| {
            candidate
                .virtual_key_codes
                .iter()
                .any(|key_code| existing.virtual_key_codes.contains(key_code))
        }) {
            return Err(NativeShortcutError::duplicate_binding());
        }
    }

    Ok(compiled)
}

fn refresh_effective_bindings(state: &NativeActionState) {
    let bindings = state
        .shortcuts
        .bindings
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();

    if let Ok(compiled) = validate_and_compile(&bindings) {
        set_effective_bindings(state, compiled);
    }
}

fn set_effective_bindings(state: &NativeActionState, compiled: Vec<CompiledDoubleTap>) {
    let effective = compiled
        .into_iter()
        .filter_map(|compiled| {
            if platform::has_external_conflict(&compiled.key_code) {
                None
            } else {
                Some(compiled)
            }
        })
        .collect();

    *state
        .shortcuts
        .compiled
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = effective;
}

fn snapshot(state: &NativeActionState) -> NativeShortcutSnapshot {
    let bindings = state
        .shortcuts
        .bindings
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    let configured_bindings = bindings.iter().filter(|binding| binding.enabled).count();
    let effective_bindings = state
        .shortcuts
        .compiled
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .len();
    let external_conflict = bindings
        .iter()
        .filter(|binding| binding.enabled)
        .any(|binding| {
            let NativeShortcutGesture::DoubleTap { key, .. } = &binding.gesture;
            platform::has_external_conflict(&key.code)
        })
        .then_some(NativeExternalShortcutConflict::ControlShot);

    let listener_state = if configured_bindings == 0 {
        NativeShortcutListenerState::Disabled
    } else if external_conflict.is_some() && effective_bindings == 0 {
        NativeShortcutListenerState::ExternalConflict
    } else if !platform::supported() {
        NativeShortcutListenerState::Unsupported
    } else if !native::input_monitoring_granted() {
        NativeShortcutListenerState::PermissionRequired
    } else if state.shortcuts.listener_active.load(Ordering::Acquire) {
        NativeShortcutListenerState::Active
    } else if state.shortcuts.listener_failed.load(Ordering::Acquire) {
        NativeShortcutListenerState::Failed
    } else {
        NativeShortcutListenerState::Starting
    };

    NativeShortcutSnapshot {
        bindings,
        configured_bindings,
        effective_bindings,
        listener_state,
        external_conflict,
    }
}

fn ensure_listener(app: &AppHandle, state: &NativeActionState) {
    let has_effective_binding = !state
        .shortcuts
        .compiled
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .is_empty();
    if !has_effective_binding || !native::input_monitoring_granted() {
        return;
    }

    if state
        .shortcuts
        .listener_started
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }

    state
        .shortcuts
        .listener_failed
        .store(false, Ordering::Release);
    platform::start_listener(app.clone(), state.clone());
}

fn shortcut_path(app: &AppHandle) -> Result<PathBuf, NativeShortcutError> {
    app.path()
        .app_config_dir()
        .map(|directory| directory.join(SHORTCUT_FILE_NAME))
        .map_err(|_| NativeShortcutError::persistence_failed())
}

fn load_bindings(app: &AppHandle) -> Result<Vec<NativeShortcutBinding>, NativeShortcutError> {
    let path = shortcut_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }

    let serialized =
        fs::read_to_string(path).map_err(|_| NativeShortcutError::persistence_failed())?;
    let preferences: ShortcutPreferences =
        serde_json::from_str(&serialized).map_err(|_| NativeShortcutError::invalid_binding())?;
    if preferences.schema_version != SHORTCUT_SCHEMA_VERSION {
        return Err(NativeShortcutError::invalid_binding());
    }
    Ok(preferences.bindings)
}

fn persist_bindings(
    app: &AppHandle,
    bindings: &[NativeShortcutBinding],
) -> Result<(), NativeShortcutError> {
    let path = shortcut_path(app)?;
    let directory = path
        .parent()
        .ok_or_else(NativeShortcutError::persistence_failed)?;
    fs::create_dir_all(directory).map_err(|_| NativeShortcutError::persistence_failed())?;

    let preferences = ShortcutPreferences {
        schema_version: SHORTCUT_SCHEMA_VERSION,
        bindings: bindings.to_vec(),
    };
    let serialized = serde_json::to_vec_pretty(&preferences)
        .map_err(|_| NativeShortcutError::persistence_failed())?;
    let temporary_path = path.with_extension("json.tmp");
    fs::write(&temporary_path, serialized)
        .map_err(|_| NativeShortcutError::persistence_failed())?;
    fs::rename(&temporary_path, &path).map_err(|_| NativeShortcutError::persistence_failed())
}

#[cfg(target_os = "macos")]
mod platform {
    use std::{
        collections::HashSet,
        sync::{Arc, Mutex, atomic::Ordering},
        thread,
        time::Instant,
    };

    use core_foundation::runloop::CFRunLoop;
    use core_graphics::event::{
        CGEvent, CGEventTap, CGEventTapLocation, CGEventTapOptions, CGEventTapPlacement,
        CGEventType, CallbackResult, EventField, KeyCode,
    };
    use objc2_app_kit::NSRunningApplication;
    use objc2_foundation::NSString;
    use tauri::{AppHandle, Emitter};

    use crate::native;

    use super::{
        CompiledDoubleTap, DoubleTapDetector, KeyPhase, NativeActionState, NativeShortcutKey,
        NativeShortcutKeyLocation,
    };

    pub fn supported() -> bool {
        true
    }

    pub fn has_external_conflict(key_code: &str) -> bool {
        matches!(key_code, "Meta" | "Control") && control_shot_is_running()
    }

    pub fn start_listener(app: AppHandle, state: NativeActionState) {
        let started = Arc::clone(&state.shortcuts.listener_started);
        let active = Arc::clone(&state.shortcuts.listener_active);
        let failed = Arc::clone(&state.shortcuts.listener_failed);
        let fallback_started = Arc::clone(&started);
        let fallback_active = Arc::clone(&active);
        let fallback_failed = Arc::clone(&failed);

        let spawn_result = thread::Builder::new()
            .name("vyrra-double-tap-listener".to_owned())
            .spawn(move || {
                let detector = Mutex::new(DoubleTapDetector::default());
                let modifier_keys_down = Mutex::new(HashSet::<u16>::new());
                let clock = Instant::now();
                let callback_app = app.clone();
                let callback_state = state.clone();

                let result = CGEventTap::with_enabled(
                    CGEventTapLocation::Session,
                    CGEventTapPlacement::HeadInsertEventTap,
                    CGEventTapOptions::ListenOnly,
                    vec![
                        CGEventType::KeyDown,
                        CGEventType::KeyUp,
                        CGEventType::FlagsChanged,
                    ],
                    move |_proxy, event_type, event| {
                        process_event(
                            &callback_app,
                            &callback_state,
                            &detector,
                            &modifier_keys_down,
                            clock,
                            event_type,
                            event,
                        );
                        CallbackResult::Keep
                    },
                    || {
                        active.store(true, Ordering::Release);
                        let _ = app.emit("native-shortcut-runtime-ready", ());
                        CFRunLoop::run_current();
                    },
                );

                active.store(false, Ordering::Release);
                started.store(false, Ordering::Release);
                if result.is_err() {
                    failed.store(true, Ordering::Release);
                    let _ = app.emit("native-shortcut-runtime-error", "event_tap_unavailable");
                }
            });

        if spawn_result.is_err() {
            fallback_active.store(false, Ordering::Release);
            fallback_started.store(false, Ordering::Release);
            fallback_failed.store(true, Ordering::Release);
        }
    }

    fn process_event(
        app: &AppHandle,
        state: &NativeActionState,
        detector: &Mutex<DoubleTapDetector>,
        modifier_keys_down: &Mutex<HashSet<u16>>,
        clock: Instant,
        event_type: CGEventType,
        event: &CGEvent,
    ) {
        let key_code = event.get_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE) as u16;
        let phase = match event_type {
            CGEventType::KeyDown => {
                if event.get_integer_value_field(EventField::KEYBOARD_EVENT_AUTOREPEAT) != 0 {
                    detector
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner())
                        .interrupt();
                    return;
                }
                KeyPhase::Down
            }
            CGEventType::KeyUp => KeyPhase::Up,
            CGEventType::FlagsChanged => {
                let mut down = modifier_keys_down
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                if down.remove(&key_code) {
                    KeyPhase::Up
                } else {
                    down.insert(key_code);
                    KeyPhase::Down
                }
            }
            _ => return,
        };

        let binding = state
            .shortcuts
            .compiled
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .iter()
            .find(|binding| binding.virtual_key_codes.contains(&key_code))
            .cloned();

        let Some(binding) = binding else {
            detector
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .interrupt();
            return;
        };

        let elapsed_ms = clock.elapsed().as_millis().min(u128::from(u64::MAX)) as u64;
        let triggered = detector
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .handle(
                key_code,
                phase,
                elapsed_ms,
                binding.interval_ms,
                binding.max_press_ms,
            );

        if triggered {
            dispatch_binding(app, state, &binding);
        }
    }

    fn dispatch_binding(app: &AppHandle, state: &NativeActionState, binding: &CompiledDoubleTap) {
        if has_external_conflict(&binding.key_code) {
            native::emit_quick_clip_external_conflict(app);
            return;
        }

        match binding.action_id {
            super::NativeShortcutAction::QuickClip => {
                native::trigger_quick_clip(app.clone(), state.clone());
            }
        }
    }

    pub fn virtual_key_codes(key: &NativeShortcutKey) -> Option<Vec<u16>> {
        use NativeShortcutKeyLocation::{Either, Left, Right, Standard};

        let modifier = match key.code.as_str() {
            "Meta" => Some((KeyCode::COMMAND, KeyCode::RIGHT_COMMAND)),
            "Control" => Some((KeyCode::CONTROL, KeyCode::RIGHT_CONTROL)),
            "Shift" => Some((KeyCode::SHIFT, KeyCode::RIGHT_SHIFT)),
            "Alt" => Some((KeyCode::OPTION, KeyCode::RIGHT_OPTION)),
            _ => None,
        };
        if let Some((left, right)) = modifier {
            return match key.location {
                Left => Some(vec![left]),
                Right => Some(vec![right]),
                Either => Some(vec![left, right]),
                Standard => None,
            };
        }

        if key.location != Standard {
            return None;
        }

        let code = match key.code.as_str() {
            "KeyA" => KeyCode::ANSI_A,
            "KeyB" => KeyCode::ANSI_B,
            "KeyC" => KeyCode::ANSI_C,
            "KeyD" => KeyCode::ANSI_D,
            "KeyE" => KeyCode::ANSI_E,
            "KeyF" => KeyCode::ANSI_F,
            "KeyG" => KeyCode::ANSI_G,
            "KeyH" => KeyCode::ANSI_H,
            "KeyI" => KeyCode::ANSI_I,
            "KeyJ" => KeyCode::ANSI_J,
            "KeyK" => KeyCode::ANSI_K,
            "KeyL" => KeyCode::ANSI_L,
            "KeyM" => KeyCode::ANSI_M,
            "KeyN" => KeyCode::ANSI_N,
            "KeyO" => KeyCode::ANSI_O,
            "KeyP" => KeyCode::ANSI_P,
            "KeyQ" => KeyCode::ANSI_Q,
            "KeyR" => KeyCode::ANSI_R,
            "KeyS" => KeyCode::ANSI_S,
            "KeyT" => KeyCode::ANSI_T,
            "KeyU" => KeyCode::ANSI_U,
            "KeyV" => KeyCode::ANSI_V,
            "KeyW" => KeyCode::ANSI_W,
            "KeyX" => KeyCode::ANSI_X,
            "KeyY" => KeyCode::ANSI_Y,
            "KeyZ" => KeyCode::ANSI_Z,
            "Digit0" => KeyCode::ANSI_0,
            "Digit1" => KeyCode::ANSI_1,
            "Digit2" => KeyCode::ANSI_2,
            "Digit3" => KeyCode::ANSI_3,
            "Digit4" => KeyCode::ANSI_4,
            "Digit5" => KeyCode::ANSI_5,
            "Digit6" => KeyCode::ANSI_6,
            "Digit7" => KeyCode::ANSI_7,
            "Digit8" => KeyCode::ANSI_8,
            "Digit9" => KeyCode::ANSI_9,
            "Numpad0" => KeyCode::ANSI_KEYPAD_0,
            "Numpad1" => KeyCode::ANSI_KEYPAD_1,
            "Numpad2" => KeyCode::ANSI_KEYPAD_2,
            "Numpad3" => KeyCode::ANSI_KEYPAD_3,
            "Numpad4" => KeyCode::ANSI_KEYPAD_4,
            "Numpad5" => KeyCode::ANSI_KEYPAD_5,
            "Numpad6" => KeyCode::ANSI_KEYPAD_6,
            "Numpad7" => KeyCode::ANSI_KEYPAD_7,
            "Numpad8" => KeyCode::ANSI_KEYPAD_8,
            "Numpad9" => KeyCode::ANSI_KEYPAD_9,
            "NumpadDecimal" => KeyCode::ANSI_KEYPAD_DECIMAL,
            "NumpadAdd" => KeyCode::ANSI_KEYPAD_PLUS,
            "NumpadSubtract" => KeyCode::ANSI_KEYPAD_MINUS,
            "NumpadMultiply" => KeyCode::ANSI_KEYPAD_MULTIPLY,
            "NumpadDivide" => KeyCode::ANSI_KEYPAD_DIVIDE,
            "NumpadEnter" => KeyCode::ANSI_KEYPAD_ENTER,
            "Backquote" => KeyCode::ANSI_GRAVE,
            "Minus" => KeyCode::ANSI_MINUS,
            "Equal" => KeyCode::ANSI_EQUAL,
            "BracketLeft" => KeyCode::ANSI_LEFT_BRACKET,
            "BracketRight" => KeyCode::ANSI_RIGHT_BRACKET,
            "Backslash" => KeyCode::ANSI_BACKSLASH,
            "Semicolon" => KeyCode::ANSI_SEMICOLON,
            "Quote" => KeyCode::ANSI_QUOTE,
            "Comma" => KeyCode::ANSI_COMMA,
            "Period" => KeyCode::ANSI_PERIOD,
            "Slash" => KeyCode::ANSI_SLASH,
            "Space" => KeyCode::SPACE,
            "Enter" => KeyCode::RETURN,
            "Tab" => KeyCode::TAB,
            "Backspace" => KeyCode::DELETE,
            "Delete" => KeyCode::FORWARD_DELETE,
            "Escape" => KeyCode::ESCAPE,
            "CapsLock" => KeyCode::CAPS_LOCK,
            "Home" => KeyCode::HOME,
            "End" => KeyCode::END,
            "PageUp" => KeyCode::PAGE_UP,
            "PageDown" => KeyCode::PAGE_DOWN,
            "ArrowLeft" => KeyCode::LEFT_ARROW,
            "ArrowRight" => KeyCode::RIGHT_ARROW,
            "ArrowDown" => KeyCode::DOWN_ARROW,
            "ArrowUp" => KeyCode::UP_ARROW,
            "F1" => KeyCode::F1,
            "F2" => KeyCode::F2,
            "F3" => KeyCode::F3,
            "F4" => KeyCode::F4,
            "F5" => KeyCode::F5,
            "F6" => KeyCode::F6,
            "F7" => KeyCode::F7,
            "F8" => KeyCode::F8,
            "F9" => KeyCode::F9,
            "F10" => KeyCode::F10,
            "F11" => KeyCode::F11,
            "F12" => KeyCode::F12,
            "F13" => KeyCode::F13,
            "F14" => KeyCode::F14,
            "F15" => KeyCode::F15,
            "F16" => KeyCode::F16,
            "F17" => KeyCode::F17,
            "F18" => KeyCode::F18,
            "F19" => KeyCode::F19,
            "F20" => KeyCode::F20,
            _ => return None,
        };
        Some(vec![code])
    }

    fn control_shot_is_running() -> bool {
        let bundle_identifier = NSString::from_str("com.brandonrunner.controlshot");
        !NSRunningApplication::runningApplicationsWithBundleIdentifier(&bundle_identifier)
            .is_empty()
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use tauri::AppHandle;

    use super::{NativeActionState, NativeShortcutKey};

    pub fn supported() -> bool {
        false
    }

    pub fn has_external_conflict(_key_code: &str) -> bool {
        false
    }

    pub fn start_listener(_app: AppHandle, state: NativeActionState) {
        state
            .shortcuts
            .listener_started
            .store(false, std::sync::atomic::Ordering::Release);
        state
            .shortcuts
            .listener_failed
            .store(true, std::sync::atomic::Ordering::Release);
    }

    pub fn virtual_key_codes(_key: &NativeShortcutKey) -> Option<Vec<u16>> {
        None
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeyPhase {
    Down,
    Up,
}

#[derive(Clone, Copy, Debug)]
struct PressState {
    key_code: u16,
    pressed_at_ms: u64,
    is_second_tap: bool,
}

#[derive(Default)]
struct DoubleTapDetector {
    press: Option<PressState>,
    last_release: Option<(u16, u64)>,
}

impl DoubleTapDetector {
    fn handle(
        &mut self,
        key_code: u16,
        phase: KeyPhase,
        now_ms: u64,
        interval_ms: u64,
        max_press_ms: u64,
    ) -> bool {
        match phase {
            KeyPhase::Down => {
                if self.press.is_some() {
                    self.interrupt();
                    return false;
                }

                let is_second_tap = self
                    .last_release
                    .is_some_and(|(released_key, released_at)| {
                        released_key == key_code
                            && now_ms.saturating_sub(released_at) <= interval_ms
                    });
                if !is_second_tap {
                    self.last_release = None;
                }
                self.press = Some(PressState {
                    key_code,
                    pressed_at_ms: now_ms,
                    is_second_tap,
                });
                false
            }
            KeyPhase::Up => {
                let Some(press) = self.press.take() else {
                    self.interrupt();
                    return false;
                };
                if press.key_code != key_code
                    || now_ms.saturating_sub(press.pressed_at_ms) > max_press_ms
                {
                    self.interrupt();
                    return false;
                }

                if press.is_second_tap {
                    self.last_release = None;
                    true
                } else {
                    self.last_release = Some((key_code, now_ms));
                    false
                }
            }
        }
    }

    fn interrupt(&mut self) {
        self.press = None;
        self.last_release = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn detector() -> DoubleTapDetector {
        DoubleTapDetector::default()
    }

    #[test]
    fn triggers_only_after_two_complete_taps() {
        let mut detector = detector();
        assert!(!detector.handle(55, KeyPhase::Down, 0, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 40, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Down, 150, 350, 250));
        assert!(detector.handle(55, KeyPhase::Up, 190, 350, 250));
    }

    #[test]
    fn does_not_cross_physical_sides() {
        let mut detector = detector();
        assert!(!detector.handle(55, KeyPhase::Down, 0, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 40, 350, 250));
        assert!(!detector.handle(54, KeyPhase::Down, 120, 350, 250));
        assert!(!detector.handle(54, KeyPhase::Up, 160, 350, 250));
    }

    #[test]
    fn intervening_key_resets_the_sequence() {
        let mut detector = detector();
        assert!(!detector.handle(55, KeyPhase::Down, 0, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 40, 350, 250));
        detector.interrupt();
        assert!(!detector.handle(55, KeyPhase::Down, 120, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 160, 350, 250));
    }

    #[test]
    fn long_press_and_slow_second_tap_do_not_trigger() {
        let mut detector = detector();
        assert!(!detector.handle(55, KeyPhase::Down, 0, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 251, 350, 250));

        assert!(!detector.handle(55, KeyPhase::Down, 500, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 520, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Down, 871, 350, 250));
        assert!(!detector.handle(55, KeyPhase::Up, 900, 350, 250));
    }

    #[test]
    fn rejects_overlapping_either_side_and_side_specific_bindings() {
        let bindings = vec![
            NativeShortcutBinding {
                action_id: NativeShortcutAction::QuickClip,
                enabled: true,
                gesture: NativeShortcutGesture::DoubleTap {
                    key: NativeShortcutKey {
                        code: "Meta".to_owned(),
                        location: NativeShortcutKeyLocation::Either,
                    },
                    interval_ms: 350,
                    max_press_ms: 250,
                },
            },
            NativeShortcutBinding {
                action_id: NativeShortcutAction::QuickClip,
                enabled: true,
                gesture: NativeShortcutGesture::DoubleTap {
                    key: NativeShortcutKey {
                        code: "Meta".to_owned(),
                        location: NativeShortcutKeyLocation::Left,
                    },
                    interval_ms: 350,
                    max_press_ms: 250,
                },
            },
        ];

        assert_eq!(
            validate_and_compile(&bindings)
                .expect_err("overlap must fail")
                .code,
            "duplicate_shortcut_binding"
        );
    }
}
