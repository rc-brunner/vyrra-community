use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::shortcuts::NativeShortcutState;

#[derive(Clone, Default)]
pub struct NativeActionState {
    quick_clip_busy: Arc<AtomicBool>,
    pub(crate) shortcuts: NativeShortcutState,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NativePermission {
    InputMonitoring,
    ScreenCapture,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PermissionState {
    Granted,
    NotGranted,
    #[cfg(not(target_os = "macos"))]
    Unsupported,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NativePermissionStatus {
    input_monitoring: PermissionState,
    screen_capture: PermissionState,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum QuickClipStatus {
    Success,
    Cancelled,
    Busy,
    PermissionNotGranted,
    ExternalConflict,
    CaptureFailed,
    ClipboardReplaced,
    TimedOut,
    #[cfg(not(target_os = "macos"))]
    Unsupported,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct QuickClipOutcome {
    status: QuickClipStatus,
    clipboard_updated: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeCommandError {
    code: &'static str,
    message: &'static str,
}

impl NativeCommandError {
    fn task_failed() -> Self {
        Self {
            code: "native_task_failed",
            message: "The native action could not complete.",
        }
    }
}

#[tauri::command]
pub fn native_permission_status() -> NativePermissionStatus {
    platform::permission_status()
}

#[tauri::command]
pub fn request_native_permission(permission: NativePermission) -> NativePermissionStatus {
    platform::request_permission(permission)
}

#[tauri::command]
pub async fn quick_clip(
    prompt_for_permission: bool,
    state: State<'_, NativeActionState>,
) -> Result<QuickClipOutcome, NativeCommandError> {
    if state.quick_clip_busy.swap(true, Ordering::AcqRel) {
        return Ok(QuickClipOutcome {
            status: QuickClipStatus::Busy,
            clipboard_updated: false,
        });
    }

    let busy = Arc::clone(&state.quick_clip_busy);
    tauri::async_runtime::spawn_blocking(move || {
        let _busy_guard = BusyGuard(busy);
        platform::run_quick_clip(prompt_for_permission)
    })
    .await
    .map_err(|_| NativeCommandError::task_failed())
}

pub(crate) fn trigger_quick_clip(app: AppHandle, state: NativeActionState) {
    if state.quick_clip_busy.swap(true, Ordering::AcqRel) {
        let _ = app.emit(
            "native-quick-clip-outcome",
            QuickClipOutcome {
                status: QuickClipStatus::Busy,
                clipboard_updated: false,
            },
        );
        return;
    }

    let busy = Arc::clone(&state.quick_clip_busy);
    tauri::async_runtime::spawn(async move {
        let outcome = tauri::async_runtime::spawn_blocking(move || {
            let _busy_guard = BusyGuard(busy);
            platform::run_quick_clip(false)
        })
        .await
        .unwrap_or(QuickClipOutcome {
            status: QuickClipStatus::CaptureFailed,
            clipboard_updated: false,
        });
        let _ = app.emit("native-quick-clip-outcome", outcome);
    });
}

pub(crate) fn emit_quick_clip_external_conflict(app: &AppHandle) {
    let _ = app.emit(
        "native-quick-clip-outcome",
        QuickClipOutcome {
            status: QuickClipStatus::ExternalConflict,
            clipboard_updated: false,
        },
    );
}

pub(crate) fn input_monitoring_granted() -> bool {
    platform::input_monitoring_granted()
}

struct BusyGuard(Arc<AtomicBool>);

impl Drop for BusyGuard {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use std::{
        process::{Command, Stdio},
        thread,
        time::{Duration, Instant},
    };

    use objc2_app_kit::{NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeTIFF};
    use objc2_foundation::NSArray;

    use super::{
        NativePermission, NativePermissionStatus, PermissionState, QuickClipOutcome,
        QuickClipStatus,
    };

    const SCREENSHOT_EXECUTABLE: &str = "/usr/sbin/screencapture";
    const SCREENSHOT_ARGS: [&str; 4] = ["-i", "-s", "-c", "-x"];
    const CAPTURE_TIMEOUT: Duration = Duration::from_secs(120);
    const POLL_INTERVAL: Duration = Duration::from_millis(50);

    #[link(name = "CoreGraphics", kind = "framework")]
    unsafe extern "C" {
        fn CGPreflightListenEventAccess() -> bool;
        fn CGRequestListenEventAccess() -> bool;
        fn CGPreflightScreenCaptureAccess() -> bool;
        fn CGRequestScreenCaptureAccess() -> bool;
    }

    pub fn permission_status() -> NativePermissionStatus {
        NativePermissionStatus {
            input_monitoring: bool_to_permission(unsafe { CGPreflightListenEventAccess() }),
            screen_capture: bool_to_permission(unsafe { CGPreflightScreenCaptureAccess() }),
        }
    }

    pub fn request_permission(permission: NativePermission) -> NativePermissionStatus {
        match permission {
            NativePermission::InputMonitoring => {
                unsafe { CGRequestListenEventAccess() };
            }
            NativePermission::ScreenCapture => {
                unsafe { CGRequestScreenCaptureAccess() };
            }
        }

        permission_status()
    }

    pub fn input_monitoring_granted() -> bool {
        unsafe { CGPreflightListenEventAccess() }
    }

    pub fn run_quick_clip(prompt_for_permission: bool) -> QuickClipOutcome {
        let mut screen_capture_granted = unsafe { CGPreflightScreenCaptureAccess() };
        if !screen_capture_granted && prompt_for_permission {
            screen_capture_granted = unsafe { CGRequestScreenCaptureAccess() };
        }

        if !screen_capture_granted {
            return outcome(QuickClipStatus::PermissionNotGranted, false);
        }

        let pasteboard = NSPasteboard::generalPasteboard();
        let previous_change_count = pasteboard.changeCount();

        let mut child = match Command::new(SCREENSHOT_EXECUTABLE)
            .args(SCREENSHOT_ARGS)
            .env_clear()
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => child,
            Err(_) => return outcome(QuickClipStatus::CaptureFailed, false),
        };

        let deadline = Instant::now() + CAPTURE_TIMEOUT;
        let exit_status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break Some(status),
                Ok(None) if Instant::now() < deadline => thread::sleep(POLL_INTERVAL),
                Ok(None) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    break None;
                }
                Err(_) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return outcome(QuickClipStatus::CaptureFailed, false);
                }
            }
        };

        let Some(exit_status) = exit_status else {
            return outcome(QuickClipStatus::TimedOut, false);
        };

        let clipboard_changed = pasteboard.changeCount() != previous_change_count;
        if !clipboard_changed {
            return if exit_status.success() {
                outcome(QuickClipStatus::Cancelled, false)
            } else {
                outcome(QuickClipStatus::CaptureFailed, false)
            };
        }

        // SAFETY: these are immutable AppKit pasteboard type constants.
        let image_types = NSArray::from_slice(&[unsafe { NSPasteboardTypePNG }, unsafe {
            NSPasteboardTypeTIFF
        }]);
        let contains_image = pasteboard.availableTypeFromArray(&image_types).is_some();

        if !exit_status.success() {
            return outcome(QuickClipStatus::CaptureFailed, contains_image);
        }

        if !contains_image {
            return outcome(QuickClipStatus::ClipboardReplaced, true);
        }

        outcome(QuickClipStatus::Success, true)
    }

    fn bool_to_permission(value: bool) -> PermissionState {
        if value {
            PermissionState::Granted
        } else {
            PermissionState::NotGranted
        }
    }

    fn outcome(status: QuickClipStatus, clipboard_updated: bool) -> QuickClipOutcome {
        QuickClipOutcome {
            status,
            clipboard_updated,
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn quick_clip_uses_only_the_fixed_system_tool_contract() {
            assert_eq!(SCREENSHOT_EXECUTABLE, "/usr/sbin/screencapture");
            assert_eq!(SCREENSHOT_ARGS, ["-i", "-s", "-c", "-x"]);
            assert!(
                !SCREENSHOT_ARGS
                    .iter()
                    .any(|argument| argument.contains('/'))
            );
        }

        #[test]
        fn expected_outcomes_never_carry_clipboard_content() {
            let result = outcome(QuickClipStatus::Success, true);

            assert_eq!(result.status, QuickClipStatus::Success);
            assert!(result.clipboard_updated);
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::{
        NativePermission, NativePermissionStatus, PermissionState, QuickClipOutcome,
        QuickClipStatus,
    };

    pub fn permission_status() -> NativePermissionStatus {
        NativePermissionStatus {
            input_monitoring: PermissionState::Unsupported,
            screen_capture: PermissionState::Unsupported,
        }
    }

    pub fn request_permission(_permission: NativePermission) -> NativePermissionStatus {
        permission_status()
    }

    pub fn input_monitoring_granted() -> bool {
        false
    }

    pub fn run_quick_clip(_prompt_for_permission: bool) -> QuickClipOutcome {
        QuickClipOutcome {
            status: QuickClipStatus::Unsupported,
            clipboard_updated: false,
        }
    }
}
