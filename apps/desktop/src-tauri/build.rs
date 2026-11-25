fn main() {
    #[cfg(target_os = "macos")]
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        use std::{env, path::PathBuf, process::Command};
        let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
        let arch = if env::var("CARGO_CFG_TARGET_ARCH").unwrap() == "aarch64" {
            "arm64"
        } else {
            "x86_64"
        };
        let target = format!("{arch}-apple-macos13.0");
        println!("cargo:rerun-if-changed=native/MeetingAudio.swift");
        assert!(
            Command::new("xcrun")
                .args([
                    "swiftc",
                    "-parse-as-library",
                    "-swift-version",
                    "5",
                    "-O",
                    "-emit-library",
                    "-static",
                    "-target",
                    &target,
                    "native/MeetingAudio.swift",
                    "-o"
                ])
                .arg(out.join("libVyrraMeetingAudio.a"))
                .status()
                .unwrap()
                .success(),
            "Could not compile the macOS meeting-audio adapter"
        );
        let info = Command::new("xcrun")
            .args(["--find", "swiftc"])
            .output()
            .unwrap();
        let bin = PathBuf::from(std::str::from_utf8(&info.stdout).unwrap().trim());
        let swift = bin
            .parent()
            .unwrap()
            .parent()
            .unwrap()
            .join("lib/swift/macosx");
        println!("cargo:rustc-link-search=native={}", out.display());
        println!("cargo:rustc-link-search=native={}", swift.display());
        println!("cargo:rustc-link-search=native=/usr/lib/swift");
        println!("cargo:rustc-link-lib=static=VyrraMeetingAudio");
        for framework in [
            "ScreenCaptureKit",
            "CoreMedia",
            "Foundation",
            "CoreAudio",
            "EventKit",
        ] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
        println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
    }
    tauri_build::build()
}
