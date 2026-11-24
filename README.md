# Vyrra

Vyrra is a free, local-first voice keyboard for iPhone and a desktop dictation app. Speech processing runs on your device after you install the speech model. You can bring the model from another computer. Dictation uses no account, subscription, word meter, or cloud API key.

## Desktop

Install Node as specified in `.node-version`, pnpm 10.14.0, the Rust toolchain in `rust-toolchain.toml`, CMake, Clang, and the platform prerequisites for Tauri 2. From the repository root, run `pnpm install --frozen-lockfile` followed by `pnpm dev`. On first use, choose **Download speech model** or select the verified multilingual Whisper base file. The first download is approximately 148 MB.

The desktop app includes a microphone, push-to-talk and hands-free shortcuts, WAV import, a personal dictionary, spoken snippets, and an editable local transcript library. Allow macOS microphone access for dictation and Accessibility access for insertion into other apps. A transcript remains available to copy when insertion is unavailable.

## iPhone

Open `iphone/Vyrra.xcodeproj` in Xcode, select the **Vyrra** scheme and run on an iPhone simulator. On a physical device, select your own development team and use bundle and shared App Group identifiers registered to that team across all three targets. The source includes the keyboard extension, Live Activity and tests. The App Store release and this source tree can move at different speeds.

## License

Runner Concepts releases the Vyrra source under Apache-2.0. See LICENSE and NOTICE for details.
