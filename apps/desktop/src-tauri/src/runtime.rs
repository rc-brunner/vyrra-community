use serde::Serialize;

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeStatus {
    shell: &'static str,
    version: &'static str,
    platform: &'static str,
    distribution_channel: &'static str,
    native_shortcuts_available: bool,
    quick_clip_available: bool,
    audio_capture_available: bool,
}
#[tauri::command]
pub fn runtime_status() -> RuntimeStatus {
    RuntimeStatus {
        shell: "tauri",
        version: env!("CARGO_PKG_VERSION"),
        platform: std::env::consts::OS,
        distribution_channel: if cfg!(debug_assertions) {
            "development"
        } else {
            "internal"
        },
        native_shortcuts_available: cfg!(target_os = "macos"),
        quick_clip_available: cfg!(target_os = "macos"),
        audio_capture_available: cfg!(any(
            target_os = "macos",
            target_os = "windows",
            target_os = "linux"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_reports_only_the_connected_platform_capabilities() {
        let status = runtime_status();

        assert_eq!(status.shell, "tauri");
        assert_eq!(status.native_shortcuts_available, cfg!(target_os = "macos"));
        assert_eq!(status.quick_clip_available, cfg!(target_os = "macos"));
        assert_eq!(
            status.audio_capture_available,
            cfg!(any(
                target_os = "macos",
                target_os = "windows",
                target_os = "linux"
            ))
        );
    }
}
