import AppIntents
import Foundation

struct OpenSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Speak"
    static var description = IntentDescription("Open Vyrra to the recording screen.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRequest.request(.speak)
        return .result()
    }
}

struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description = IntentDescription("Open Vyrra to saved notes.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRequest.request(.library)
        return .result()
    }
}

struct StartDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Dictation"
    static var description = IntentDescription("Open Vyrra and start a new dictation when the speech model is ready.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigationRequest.request(.speak, action: .startDictation)
        return .result()
    }
}

struct VyrraAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayBlue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start dictation in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Start Dictation",
            systemImageName: "mic.circle"
        )

        AppShortcut(
            intent: OpenSpeakIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open Speak in \(.applicationName)",
                "Show Speak in \(.applicationName)"
            ],
            shortTitle: "Open Speak",
            systemImageName: "record.circle"
        )

        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open \(.applicationName) library",
                "Show \(.applicationName) notes"
            ],
            shortTitle: "Open Library",
            systemImageName: "tray.full"
        )
    }
}
