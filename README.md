# Vyrra

Vyrra is a free, local-first voice keyboard for iPhone and a desktop dictation app. Speech processing runs on your device after you install the speech model. You can bring the model from another computer. Dictation uses no account, subscription, word meter, or cloud API key.

## Desktop

Install Node as specified in `.node-version`, pnpm 10.14.0, the Rust toolchain in `rust-toolchain.toml`, CMake, Clang, and the platform prerequisites for Tauri 2. From the repository root, run `pnpm install --frozen-lockfile` followed by `pnpm dev`. On first use, choose **Download speech model** or select the verified multilingual Whisper base file. The first download is approximately 148 MB.

The desktop app includes a microphone, push-to-talk and hands-free shortcuts, WAV import, a personal dictionary, spoken snippets, and an editable local transcript library. Allow macOS microphone access for dictation and Accessibility access for insertion into other apps. A transcript remains available to copy when insertion is unavailable.

## Meetings and feedback

Choose an accepted calendar call to open locally, or schedule a named participant on your own Attendee server. Choose a participant picture under **Settings → Meetings**. The local writing model supports summaries and transcript questions. Core dictation stays free and uncapped. See the setup and platform limits in the [meeting guide](docs/meetings.md).

**Settings → Dictation** offers Classic, Soft click, Felt thud and Off, with a preview of both cues. Desktop panel sounds are optional. The iPhone sound picker is in Style and Profile.

## iPhone

Open `iphone/Vyrra.xcodeproj` in Xcode, select the **Vyrra** scheme and run on an iPhone simulator. On a physical device, select your own development team and use bundle and shared App Group identifiers registered to that team across all three targets. The source includes the keyboard extension, Live Activity and tests. The App Store release and this source tree can move at different speeds.

## License

Runner Concepts releases the Vyrra source under Apache-2.0. See LICENSE and NOTICE for details.
