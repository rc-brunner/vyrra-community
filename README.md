# Vyrra

Vyrra is a free, local-first voice keyboard for iPhone and Android and a desktop dictation app. On iPhone and desktop, install the speech model once to dictate on your device. Android uses the phone’s on-device speech recognizer and needs a supported language pack. Dictation requires no account or subscription and has no word limit.

## Downloads

| Platform | Public download |
| --- | --- |
| iPhone | [App Store](https://apps.apple.com/app/id6793320385) |
| Android 12 and later | [Signed APK preview](https://github.com/rc-brunner/vyrra-community/releases/download/android-v0.1.0-alpha01/Vyrra-Android.apk) |
| Apple silicon Mac, macOS 13 and later | [Notarized desktop preview](https://github.com/rc-brunner/vyrra-community/releases/download/macos-v0.1.0/Vyrra-macOS-Apple-Silicon.zip) |
| Ubuntu 24.04, Intel or AMD 64-bit | [Desktop 0.1.1 preview (.deb)](https://github.com/rc-brunner/vyrra-community/releases/download/linux-v0.1.1/Vyrra-Linux-x86_64.deb) |

If you install the direct Android APK, use GitHub for updates. The Google Play edition uses a different signing certificate. On Linux, copy transcripts from the library. See the [Linux release notes](https://github.com/rc-brunner/vyrra-community/releases/tag/linux-v0.1.1) for the supported features and installation steps.

## Desktop

Install Node as specified in `.node-version`, pnpm 10.14.0, the Rust toolchain in `rust-toolchain.toml`, CMake 3.19 or later, Clang, and the platform prerequisites for Tauri 2. From the repository root, run `pnpm install --frozen-lockfile` followed by `pnpm dev`. On first use, choose **Download speech model** or select the verified multilingual Whisper base file. The first download is approximately 148 MB.

The desktop app includes a microphone, push-to-talk and hands-free shortcuts, WAV import, a personal dictionary, spoken snippets, and an editable local transcript library. Allow macOS microphone access for dictation and Accessibility access for insertion into other apps. A transcript remains available to copy when insertion is unavailable.

Read how the Windows app handles audio, saved transcripts, model downloads and optional meeting participants in [Windows privacy](docs/windows-privacy.md).

## Meetings and feedback

Choose an accepted calendar call to open locally, or schedule a named participant on your own Attendee server. Choose a participant picture under **Settings → Meetings**. The local writing model supports summaries and transcript questions. Core dictation stays free and uncapped. See the setup and platform limits in the [meeting guide](docs/meetings.md).

**Settings → Dictation** offers Studio latch, Classic, Soft click, Felt thud, Porcelain and Off, with a preview of both cues. Desktop panel sounds are optional. The iPhone sound picker is in Style and Profile.

## iPhone

Open `iphone/Vyrra.xcodeproj` in Xcode, select the **Vyrra** scheme and run on an iPhone simulator. On a physical device, select your own development team and use bundle and shared App Group identifiers registered to that team across all three targets. The source includes the keyboard extension, Live Activity and tests. The App Store release and this source tree can move at different speeds.

## License

Runner Concepts releases the Vyrra source under Apache-2.0. See LICENSE and NOTICE for details.
