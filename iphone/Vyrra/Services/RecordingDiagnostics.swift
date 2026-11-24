import Foundation

struct RecordingTimingSummary: Equatable {
    let capturedAt: Date
    let recordingDuration: TimeInterval
    let modelPrepareDuration: TimeInterval
    let transcriptionDuration: TimeInterval
    let polishAndCopyDuration: TimeInterval
    let releaseToCopiedDuration: TimeInterval

    var rows: [(title: String, value: String)] {
        [
            ("Recording", Self.formatted(recordingDuration)),
            ("Model Prepare", Self.formatted(modelPrepareDuration)),
            ("Transcription", Self.formatted(transcriptionDuration)),
            ("Polish + Copy", Self.formatted(polishAndCopyDuration)),
            ("Release to Copied", Self.formatted(releaseToCopiedDuration))
        ]
    }

    static func formatted(_ duration: TimeInterval) -> String {
        let safeDuration = max(duration, 0)
        if safeDuration < 10 {
            return String(format: "%.1fs", safeDuration)
        }
        return String(format: "%.0fs", safeDuration)
    }
}

@MainActor
final class RecordingDiagnostics: ObservableObject {
    @Published private(set) var lastTiming: RecordingTimingSummary?

    func record(_ timing: RecordingTimingSummary) {
        lastTiming = timing
    }

    func clear() {
        lastTiming = nil
    }
}
