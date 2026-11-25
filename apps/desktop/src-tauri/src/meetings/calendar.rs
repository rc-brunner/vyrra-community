use super::{Event, Result};
#[cfg(target_os = "macos")]
pub(super) fn calls(prompt: bool) -> Result<Vec<Event>> {
    use std::ffi::{CStr, c_char};
    unsafe extern "C" {
        fn vyrra_calendar_calls(prompt: bool) -> *mut c_char;
        fn vyrra_calendar_free(bytes: *mut c_char);
    }
    let raw = unsafe { vyrra_calendar_calls(prompt) };
    if raw.is_null() {
        return Err("Allow Calendar access in System Settings, or import a calendar file.");
    }
    let data = unsafe { CStr::from_ptr(raw) };
    let events = serde_json::from_slice::<Vec<Event>>(data.to_bytes());
    unsafe { vyrra_calendar_free(raw) };
    let mut items = events.map_err(|_| "The calendar could not be read.")?;
    items.retain(|e| super::valid_link(&e.url));
    items.sort_by_key(|e| e.start_ms);
    let mut seen = std::collections::HashSet::new();
    items.retain(|e| seen.insert(e.uid.clone()));
    Ok(items)
}
#[cfg(not(target_os = "macos"))]
pub(super) fn calls(_: bool) -> Result<Vec<Event>> {
    Err("Import an .ics calendar file on this computer.")
}
#[tauri::command]
pub async fn meeting_calendar() -> Result<Vec<Event>> {
    super::work(|| calls(true)).await
}
