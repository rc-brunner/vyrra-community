import AppIntents
import SwiftData
import SwiftUI

@main
struct VyrraApp: App {
    init() {
        AudioRecorder.cleanupTemporaryRecordings()
        _ = try? KeyboardSharedStore.bootstrapIfNeeded()
        _ = try? KeyboardSharedStore.sanitizeDiagnostics()
        VyrraAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ])
    }
}
