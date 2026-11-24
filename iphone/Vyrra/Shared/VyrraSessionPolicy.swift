import Foundation

enum VyrraSessionPolicy {
    static let maximumRecordingDuration: TimeInterval = 5 * 60
    static let automaticInsertionWindow: TimeInterval = 20
    static let commandFreshnessWindow: TimeInterval = 30
    static let keyboardTapResponseWindow: TimeInterval = 3
    static let keyboardHeartbeatWindow: TimeInterval = 8

    // A quick-access launch should become visible almost immediately. Stale
    // shared state collapses instead of trapping the keyboard in an active state.
    static let openingStaleInterval: TimeInterval = 8
    static let warmingStaleInterval: TimeInterval = 4 * 60
    static let listeningStaleInterval: TimeInterval = maximumRecordingDuration + 45
    static let processingStaleInterval: TimeInterval = 5 * 60
    static let insertReadyStaleInterval: TimeInterval = 5 * 60

    static let liveActivityCompletionVisibility: TimeInterval = 8
}

enum KeyboardInactivityTimeout: String, CaseIterable, Identifiable {
    case immediately
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case never

    static let defaultsKey = "keyboardInactivityTimeout"
    static let enabledKey = "keyboardDictationEnabled"
    static let consentKey = "keyboardDictationConsentGranted"

    var id: String { rawValue }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .fiveMinutes
    }

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .immediately: 0
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        case .oneHour: 60 * 60
        case .never: nil
        }
    }

    func permitsResume(after interruption: Date, now: Date = Date()) -> Bool {
        guard self != .immediately, now >= interruption else { return false }
        return interval.map { now.timeIntervalSince(interruption) < $0 } ?? true
    }
}

struct KeyboardInactivityTracker {
    private(set) var idleSince: Date?

    mutating func deadline(
        timeout: KeyboardInactivityTimeout,
        appIsActive: Bool,
        keyboardIsVisible: Bool,
        phraseIsBusy: Bool,
        now: Date = Date()
    ) -> Date? {
        guard !appIsActive, !keyboardIsVisible, !phraseIsBusy else {
            idleSince = nil
            return nil
        }
        if idleSince == nil { idleSince = now }
        guard let interval = timeout.interval else { return nil }
        return idleSince?.addingTimeInterval(interval)
    }
}
