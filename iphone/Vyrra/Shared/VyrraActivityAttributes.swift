import ActivityKit
import Foundation

struct VyrraActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let state: VyrraLiveActivityState
        let startedAt: Date
        let updatedAt: Date
        let keyboardSessionExpiresAt: Date?
        let keyboardSessionIsActive: Bool?

        var hasKeyboardSession: Bool {
            keyboardSessionIsActive ?? (keyboardSessionExpiresAt != nil || state == .keyboardReady)
        }

        init(state: VyrraLiveActivityState, startedAt: Date, updatedAt: Date, keyboardSessionExpiresAt: Date? = nil, keyboardSessionIsActive: Bool? = nil) {
            self.state = state
            self.startedAt = startedAt
            self.updatedAt = updatedAt
            self.keyboardSessionExpiresAt = keyboardSessionExpiresAt
            self.keyboardSessionIsActive = keyboardSessionIsActive
        }
    }

    let sessionID: String
}

enum VyrraLiveActivityState: String, Codable, Hashable {
    case keyboardReady
    case listening
    case polishing
    case copied
    case attention

    var title: String {
        switch self {
        case .keyboardReady:
            "Keyboard ready · Mic on"
        case .listening:
            "Listening"
        case .polishing:
            "Processing"
        case .copied:
            "Copied"
        case .attention:
            "Check Vyrra"
        }
    }

    var compactTitle: String {
        switch self {
        case .keyboardReady:
            "Mic on"
        case .listening:
            "Live"
        case .polishing:
            "Text"
        case .copied:
            "Done"
        case .attention:
            "Open"
        }
    }

    var systemImage: String {
        switch self {
        case .keyboardReady:
            "mic.fill"
        case .listening:
            "waveform"
        case .polishing:
            "ellipsis"
        case .copied:
            "checkmark"
        case .attention:
            "exclamationmark"
        }
    }

    var shouldShowTimer: Bool {
        switch self {
        case .listening, .polishing:
            true
        case .keyboardReady, .copied, .attention:
            false
        }
    }
}
