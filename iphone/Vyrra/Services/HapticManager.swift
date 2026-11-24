import UIKit

enum HapticManager {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepareForRecordButton() {
        guard isEnabled else { return }
        runOnMain {
            lightImpact.prepare()
            mediumImpact.prepare()
        }
    }

    static func buttonPressed() {
        guard isEnabled else { return }
        runOnMain {
            lightImpact.impactOccurred(intensity: 0.62)
            lightImpact.prepare()
        }
    }

    static func recordingStarted() {
        guard isEnabled else { return }
        runOnMain {
            mediumImpact.impactOccurred(intensity: 0.82)
            mediumImpact.prepare()
        }
    }

    static func completed() {
        guard isEnabled else { return }
        runOnMain {
            notification.notificationOccurred(.success)
            notification.prepare()
        }
    }

    static func selected() {
        guard isEnabled else { return }
        runOnMain {
            selection.selectionChanged()
            selection.prepare()
        }
    }

    static func warning() {
        guard isEnabled else { return }
        runOnMain {
            notification.notificationOccurred(.warning)
            notification.prepare()
        }
    }

    static func error() {
        guard isEnabled else { return }
        runOnMain {
            notification.notificationOccurred(.error)
            notification.prepare()
        }
    }

    private static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool) ?? true
    }

    private static func runOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async {
                guard isEnabled else { return }
                action()
            }
        }
    }
}
