mod dictation;
mod meetings;
mod native;
mod runtime;
mod shortcuts;

use native::{NativeActionState, native_permission_status, quick_clip, request_native_permission};
use runtime::runtime_status;
use shortcuts::{
    activate_native_shortcuts, configure_native_shortcuts, native_shortcut_configuration,
};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let native_state = NativeActionState::default();
    let startup_state = native_state.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(native_state)
        .on_window_event(|window, event| {
            use tauri::Manager;
            if window.label() == "main"
                && matches!(event, tauri::WindowEvent::CloseRequested { .. })
            {
                if let Some(state) = window.try_state::<meetings::Meetings>() {
                    state.shutdown();
                }
                if let Some(panel) = window.get_webview_window("meeting-indicator") {
                    let _ = panel.destroy();
                }
                if let Some(state) = window.try_state::<dictation::Dictation>() {
                    state.cancel();
                }
                if let Some(panel) = window.get_webview_window("indicator") {
                    let _ = panel.destroy();
                }
            }
        })
        .setup(move |app| {
            shortcuts::initialize_native_shortcuts(app.handle(), &startup_state);
            dictation::setup(app.handle())?;
            meetings::setup(app.handle())?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            meetings::calendar::meeting_calendar,
            meetings::meeting_list,
            meetings::meeting_profile,
            meetings::meeting_picture,
            meetings::meeting_key,
            meetings::meeting_schedule,
            meetings::meeting_action,
            meetings::meeting_stop_active,
            meetings::meeting_indicator_phase,
            runtime_status,
            native_permission_status,
            request_native_permission,
            quick_clip,
            native_shortcut_configuration,
            configure_native_shortcuts,
            activate_native_shortcuts,
            dictation::writing::writing_status,
            dictation::writing::writing_install,
            dictation::writing::writing_remove,
            dictation::writing::writing_cancel,
            dictation::writing::writing_run,
            dictation::feedback::dictation_preview_sound,
            dictation::feedback::dictation_set_feedback,
            dictation::feedback::panel_sound,
            dictation::dictation_status,
            dictation::dictation_install,
            dictation::catalog::dictation_models,
            dictation::catalog::dictation_select_model,
            dictation::catalog::dictation_remove_model,
            dictation::catalog::dictation_cancel_setup,
            dictation::catalog::model_source,
            dictation::hotkeys::dictation_hotkeys,
            dictation::hotkeys::dictation_set_hotkeys,
            dictation::dictation_import,
            dictation::dictation_action,
            dictation::dictation_options,
            dictation::dictation_languages,
            dictation::dictation_export,
            dictation::dictation_set_options,
            dictation::dictation_entries,
            dictation::dictation_save,
            dictation::dictation_mark,
            dictation::dictation_delete
        ])
        .run(tauri::generate_context!())
        .expect("Vyrra Desktop failed to start");
}
