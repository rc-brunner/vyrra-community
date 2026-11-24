import AudioToolbox
import Foundation

@MainActor
enum DictationSound {
    nonisolated static let preferenceKey = "dictationSoundsEnabled"
    private static let releaseID = load("release")

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    private static func load(_ name: String) -> SystemSoundID? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "DictationSounds")
        else { return nil }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return nil }
        return sound
    }

    static func engageBeforeCapture() async {
        guard isEnabled, let sound = load("engage") else { return }
        defer { AudioServicesDisposeSystemSoundID(sound) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var waiting: CheckedContinuation<Void, Never>? = continuation
            let finish: @MainActor @Sendable () -> Void = {
                waiting?.resume()
                waiting = nil
            }
            AudioServicesPlaySystemSoundWithCompletion(sound) { DispatchQueue.main.async { finish() } }
            // A silenced or interrupted system sound must never hold the microphone closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { finish() }
        }
    }

    static func releaseAfterCapture() {
        guard isEnabled, let releaseID else { return }
        AudioServicesPlaySystemSound(releaseID)
    }
}
