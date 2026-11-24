import Accessibility
import Foundation
import UIKit

/// What VoiceOver hears as the record loop moves between phases.
///
/// Design review C3 (2026-10-08): the Speak screen changed silently, so a
/// VoiceOver user learned that dictation finished only from a haptic.
/// "Recording" is posted separately, just before capture begins, so the
/// spoken word lands before the microphone is live (see
/// `DictationSessionController.startRecording`).
struct DictationAnnouncement: Equatable {
    enum Priority: Equatable {
        case normal
        case high
    }

    let message: String
    let priority: Priority

    static let recordingStarted = DictationAnnouncement(message: "Recording", priority: .normal)

    /// Longest transcript excerpt read back after "Copied".
    static let transcriptExcerptLength = 80

    static func forTransition(
        from oldPhase: RecordingPhase,
        to newPhase: RecordingPhase,
        polishedText: String,
        hasRecoverableRecording: Bool
    ) -> DictationAnnouncement? {
        guard oldPhase != newPhase else { return nil }

        switch newPhase {
        case .processing, .transcribing:
            if oldPhase == .recording {
                return DictationAnnouncement(message: "Stopped. Transcribing.", priority: .normal)
            }
            // Processing and transcribing alternate while one recording is
            // worked on; announce only the first busy phase.
            guard oldPhase != .processing, oldPhase != .transcribing else { return nil }
            return DictationAnnouncement(message: "Transcribing.", priority: .normal)
        case .copied:
            let excerpt = Self.excerpt(of: polishedText)
            let message = excerpt.isEmpty ? "Copied." : "Copied. \(excerpt)"
            return DictationAnnouncement(message: message, priority: .high)
        case .idle where oldPhase == .recording:
            return DictationAnnouncement(message: "Recording canceled.", priority: .normal)
        case .emptyTranscript:
            return DictationAnnouncement(message: "No speech detected. Try again.", priority: .high)
        case .microphoneDenied:
            return DictationAnnouncement(message: "Microphone is off. Turn it on in Settings.", priority: .high)
        case .error(let message):
            let text = hasRecoverableRecording
                ? "Recording saved. Retry when ready."
                : "Try again. \(message)"
            return DictationAnnouncement(message: text, priority: .high)
        default:
            return nil
        }
    }

    static func excerpt(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > transcriptExcerptLength else { return trimmed }

        let prefix = trimmed.prefix(transcriptExcerptLength)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace])
        }
        return String(prefix)
    }

    @MainActor
    func post() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = priority == .high ? .high : .default
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// Posts the announcement and returns once VoiceOver has finished speaking
    /// it, or after `timeout`. Returns at once when VoiceOver is off or the
    /// app is not in the foreground (background announcements aren't spoken).
    @MainActor
    func postAndWaitUntilSpoken(timeout: TimeInterval = 1.0) async {
        guard UIAccessibility.isVoiceOverRunning,
              UIApplication.shared.applicationState == .active
        else { return }

        let message = message
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var didFinish = false
            var observer: NSObjectProtocol?
            let finish = {
                guard !didFinish else { return }
                didFinish = true
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                continuation.resume()
            }
            observer = NotificationCenter.default.addObserver(
                forName: UIAccessibility.announcementDidFinishNotification,
                object: nil,
                queue: .main
            ) { notification in
                let spoken = notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
                guard spoken == nil || spoken == message else { return }
                finish()
            }
            post()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
        }
    }
}
