import UIKit

/// Only field traits and the text immediately around the caret are used. Never persisted.
enum KeyboardInputPolicy {
    static func startsWithNumbers(_ type: UIKeyboardType) -> Bool {
        [.numberPad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad, .phonePad].contains(type)
    }

    static func capitalizes(_ type: UITextAutocapitalizationType, before context: String?, hasText: Bool) -> Bool {
        guard type != .none else { return false }
        if type == .allCharacters { return true }
        // Hosts report nil for an empty field, but also mid-text when they can't
        // say (Mail after a paste), so nil is only a start in an empty field.
        guard let context else { return !hasText }
        guard let last = context.last else { return true }
        if last.isNewline { return true }
        if type == .words { return last.isWhitespace }
        guard last.isWhitespace else { return false }
        let preceding = context.trimmingCharacters(in: .whitespaces)
        guard let lastContent = preceding.last else { return true }
        return lastContent.isNewline || ".!?".contains(lastContent)
    }

    static func returnTitle(_ type: UIReturnKeyType) -> String? {
        switch type {
        case .go: "go"
        case .google, .yahoo, .search: "search"
        case .join: "join"
        case .next: "next"
        case .route: "route"
        case .send: "send"
        case .done: "done"
        case .emergencyCall: "emergency call"
        case .continue: "continue"
        default: nil
        }
    }
}

enum KeyboardShiftState {
    case lower, upper, locked
    var isUpper: Bool { self != .lower }

    func tapped(at time: TimeInterval, after previousTap: TimeInterval?) -> Self {
        if self == .locked { return .lower }
        if let previousTap, (0...0.35).contains(time - previousTap) { return .locked }
        return isUpper ? .lower : .upper
    }
}


struct KeyboardCursorMovement {
    private var previousStep = 0
    let origin: CGFloat

    init(origin: CGFloat) { self.origin = origin }

    mutating func offset(at position: CGFloat) -> Int {
        let step = Int((position - origin) / 6)
        defer { previousStep = step }
        return step - previousStep
    }
}
