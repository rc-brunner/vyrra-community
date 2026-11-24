// Platform accessibility handles stay on one thread from capture through delivery.
use std::sync::mpsc;

pub struct Insertion(mpsc::Sender<(String, mpsc::Sender<bool>)>);

impl Insertion {
    pub fn remember() -> Option<Self> {
        let (send, receive) = mpsc::channel::<(String, mpsc::Sender<bool>)>();
        let (ready, ack) = mpsc::sync_channel(1);
        std::thread::Builder::new().name("vyrra-text-insertion".into()).spawn(move || {
            let target = platform::Target::focused();
            let _ = ready.send(target.is_some());
            if let Some(target) = target && let Ok((text, answer)) = receive.recv() {
                let _ = answer.send(target.insert(&text));
            }
        }).ok()?;
        ack.recv().ok()?.then_some(Self(send))
    }

    pub fn insert(self, text: String) -> bool {
        let (answer, wait) = mpsc::channel();
        self.0.send((text, answer)).is_ok() && wait.recv().unwrap_or(false)
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use accessibility_sys::*;
    use core_foundation::{base::{CFType, TCFType}, string::CFString};
    use objc2_app_kit::NSWorkspace;

    pub struct Target(CFType);

    fn attribute(element: AXUIElementRef, name: &str) -> Option<CFType> {
        let key = CFString::new(name);
        let mut value = std::ptr::null();
        // Copy returns one owned CF object on success.
        let code = unsafe { AXUIElementCopyAttributeValue(element, key.as_concrete_TypeRef(), &mut value) };
        if code != kAXErrorSuccess || value.is_null() { return None; }
        Some(unsafe { CFType::wrap_under_create_rule(value) })
    }

    impl Target {
        fn element(&self) -> AXUIElementRef { self.0.as_CFTypeRef() as AXUIElementRef }

        pub fn focused() -> Option<Self> {
            if !unsafe { AXIsProcessTrusted() } { return None; }
            let front = NSWorkspace::sharedWorkspace().frontmostApplication()?;
            if front.processIdentifier() as u32 == std::process::id() { return None; }
            let system = unsafe { AXUIElementCreateApplication(front.processIdentifier()) };
            if system.is_null() { return None; }
            let _owner = unsafe { CFType::wrap_under_create_rule(system.cast()) };
            unsafe { AXUIElementSetMessagingTimeout(system, 0.4) };
            let focused = attribute(system, kAXFocusedUIElementAttribute)?;
            if focused.type_of() != unsafe { AXUIElementGetTypeID() } { return None; }
            let target = Self(focused);
            let element = target.element();
            unsafe { AXUIElementSetMessagingTimeout(element, 0.4) };
            let mut pid = 0;
            if unsafe { AXUIElementGetPid(element, &mut pid) } != kAXErrorSuccess || pid as u32 == std::process::id() { return None; }
            let role = attribute(element, kAXRoleAttribute)?.downcast_into::<CFString>()?.to_string();
            if !matches!(role.as_str(), "AXTextField" | "AXTextArea" | "AXComboBox") { return None; }
            let subrole = attribute(element, kAXSubroleAttribute).and_then(|s| s.downcast_into::<CFString>());
            if subrole.is_some_and(|r| r.to_string() == kAXSecureTextFieldSubrole) { return None; }
            let mut editable = 0;
            let key = CFString::new(kAXSelectedTextAttribute);
            let status = unsafe { AXUIElementIsAttributeSettable(element, key.as_concrete_TypeRef(), &mut editable) };
            (status == kAXErrorSuccess && editable != 0).then_some(target)
        }

        pub fn insert(self, text: &str) -> bool {
            if !Self::focused().is_some_and(|current| current.0 == self.0) { return false; }
            let key = CFString::new(kAXSelectedTextAttribute);
            let value = CFString::new(text);
            unsafe { AXUIElementSetAttributeValue(self.element(), key.as_concrete_TypeRef(), value.as_CFTypeRef()) == kAXErrorSuccess }
        }
    }
    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        #[ignore = "requires a frontmost disposable TextEdit document named in VYRRA_TEST_TEXTEDIT"]
        fn inserts_only_into_the_controlled_frontmost_document() {
            let expected_title = std::env::var("VYRRA_TEST_TEXTEDIT").unwrap();
            assert!(expected_title.starts_with("vyrra-insertion-smoke-"));
            let original = Target::focused().expect("Expected an accessible editable field");
            let window = attribute(original.element(), kAXWindowAttribute).expect("Expected a window");
            let window_title = attribute(window.as_CFTypeRef() as AXUIElementRef, kAXTitleAttribute)
                .and_then(|name| name.downcast_into::<CFString>()).expect("Expected a title").to_string();
            assert!(window_title.starts_with(&expected_title), "The controlled test document lost focus");
            assert!(original.insert("Vyrra inserted this sentence privately."));
        }
    }

}

#[cfg(target_os = "windows")]
mod platform {
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
    use windows::Win32::UI::Accessibility::{CUIAutomation, IUIAutomation, IUIAutomationElement, UIA_EditControlTypeId, UIA_DocumentControlTypeId};
    use windows::Win32::UI::Input::KeyboardAndMouse::{SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE};

    struct Apartment;
    impl Drop for Apartment { fn drop(&mut self) { unsafe { CoUninitialize() }; } }
    pub struct Target { ui: IUIAutomation, element: IUIAutomationElement, _apartment: Apartment }

    fn editable(element: &IUIAutomationElement) -> Option<()> {
        unsafe {
            if element.CurrentProcessId().ok()? as u32 == std::process::id() || element.CurrentIsPassword().ok()?.as_bool() || !element.CurrentIsEnabled().ok()?.as_bool() { return None; }
            let role = element.CurrentControlType().ok()?;
            if role != UIA_EditControlTypeId && role != UIA_DocumentControlTypeId { return None; }
            if let Ok(value) = element.GetCurrentPatternAs::<windows::Win32::UI::Accessibility::IUIAutomationValuePattern>(windows::Win32::UI::Accessibility::UIA_ValuePatternId)
                && value.CurrentIsReadOnly().ok()?.as_bool() { return None; }
            Some(())
        }
    }

    impl Target {
        pub fn focused() -> Option<Self> {
            unsafe {
                CoInitializeEx(None, COINIT_APARTMENTTHREADED).ok().ok()?;
                let apartment = Apartment;
                let ui: IUIAutomation = CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER).ok()?;
                let element = ui.GetFocusedElement().ok()?;
                editable(&element)?;
                Some(Self { ui, element, _apartment: apartment })
            }
        }
        pub fn insert(self, text: &str) -> bool {
            let Ok(current) = (unsafe { self.ui.GetFocusedElement() }) else { return false; };
            if editable(&current).is_none() || !unsafe { self.ui.CompareElements(&self.element, &current) }.is_ok_and(|same| same.as_bool()) { return false; }
            let events: Vec<_> = text.encode_utf16().flat_map(|unit| [KEYEVENTF_UNICODE, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP].map(|flags| INPUT {
                r#type: INPUT_KEYBOARD, Anonymous: INPUT_0 { ki: KEYBDINPUT { wScan: unit, dwFlags: flags, ..Default::default() } }
            })).collect();
            unsafe { SendInput(&events, std::mem::size_of::<INPUT>() as i32) as usize == events.len() }
        }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod platform {
    pub struct Target;
    impl Target {
        pub fn focused() -> Option<Self> { None }
        pub fn insert(self, _: &str) -> bool { false }
    }
}
