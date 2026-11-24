import UIKit

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
#if KEYBOARD_TESTING
@testable import Vyrra
#endif

enum KeyboardMode {
    case letters
    case symbols
    case alternateSymbols
}

enum KeyKind {
    case text(String)
    case shift
    case delete
    case modeSwitch(String)
    case space
    case `return`
    case globe
}

struct KeySpec {
    let kind: KeyKind
    let width: CGFloat

    static func text(_ value: String, width: CGFloat = 1) -> KeySpec {
        KeySpec(kind: .text(value), width: width)
    }
}

struct KeyboardRowSpec {
    let keys: [KeySpec]
    let referenceUnitCount: CGFloat?
    let height: CGFloat
    let letterControls: Bool

    init(
        keys: [KeySpec],
        referenceUnitCount: CGFloat? = nil,
        height: CGFloat = KeyboardGeometry.keyHeight,
        letterControls: Bool = false
    ) {
        self.keys = keys
        self.referenceUnitCount = referenceUnitCount
        self.height = height
        self.letterControls = letterControls
    }
}

final class KeyboardKeyRowView: UIView {
    private let weightedButtons: [(button: UIButton, weight: CGFloat)]
    private let referenceUnitCount: CGFloat?
    private let rowHeight: CGFloat
    private let letterControls: Bool

    init(buttons: [(UIButton, CGFloat)], referenceUnitCount: CGFloat?, height: CGFloat, letterControls: Bool) {
        weightedButtons = buttons.map { (button: $0.0, weight: $0.1) }
        self.referenceUnitCount = referenceUnitCount
        rowHeight = height
        self.letterControls = letterControls
        super.init(frame: .zero)

        weightedButtons.forEach { addSubview($0.button) }
        heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: rowHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = letterControls ? KeyboardGeometry.letterControlFrames(in: bounds) : KeyboardGeometry.frames(
            for: weightedButtons.map { $0.weight },
            in: bounds,
            referenceUnitCount: referenceUnitCount
        )

        zip(weightedButtons, frames).forEach { weightedButton, frame in
            weightedButton.button.frame = frame
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let directHit = super.hitTest(point, with: event), directHit !== self {
            return directHit
        }

        guard bounds.contains(point) else { return nil }
        return weightedButtons
            .filter { !$0.button.isHidden && $0.button.isUserInteractionEnabled && $0.button.isEnabled }
            .min { lhs, rhs in
                abs(lhs.button.frame.midX - point.x) < abs(rhs.button.frame.midX - point.x)
            }?
            .button
    }
}

/// Keep touch ownership on the original key while letting the finger choose a
/// neighbor on release. Accessibility activation still uses the normal action.
final class KeyboardKeyButton: UIButton {
    enum Behavior { case regular, delete, space }
    var behavior: Behavior = .regular
    var neighborAtPoint: ((CGPoint, UIView) -> KeyboardKeyButton?)?
    var touchActivity: ((Bool) -> Void)?
    var moveCursor: ((Int) -> Void)?
    var previewChanged: ((KeyboardKeyButton?) -> Void)?
    var trackpadActivity: ((Bool) -> Void)?
    private var configurationBeforeTrackpad: UIButton.Configuration?
    var previewText: String?
    private weak var candidate: KeyboardKeyButton?
    private var holdTimer: Timer?
    private var repeatTimer: Timer?
    private var startPoint = CGPoint.zero
    private var cursorMovement: KeyboardCursorMovement?
    private var trackingFinger = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, let touch = touches.first else { return }
        trackingFinger = true
        touchActivity?(true)
        startPoint = touch.location(in: self)
        setCandidate(self)
        UIDevice.current.playInputClick()
        if behavior == .delete {
            sendActions(for: .touchUpInside)
        }
        guard behavior != .regular else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.trackingFinger else { return }
            if self.behavior == .delete {
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in
                    self?.sendActions(for: .touchUpInside)
                    UIDevice.current.playInputClick()
                }
                if let timer = self.repeatTimer { RunLoop.main.add(timer, forMode: .common) }
            } else {
                self.cursorMovement = KeyboardCursorMovement(origin: self.startPoint.x)
                self.trackpadActivity?(true)
                self.previewChanged?(nil)
            }
        }
        if let timer = holdTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingFinger, let touch = touches.first else { return }
        let point = touch.location(in: self)
        if behavior == .space, cursorMovement != nil {
            let offset = cursorMovement?.offset(at: point.x) ?? 0
            if offset != 0 { moveCursor?(offset) }
            return
        }
        if behavior == .delete {
            if !bounds.insetBy(dx: -20, dy: -20).contains(point) {
                holdTimer?.invalidate(); repeatTimer?.invalidate(); setCandidate(nil)
            }
            return
        }
        if behavior == .space, abs(point.x - startPoint.x) + abs(point.y - startPoint.y) > 12 {
            holdTimer?.invalidate()
        }
        setCandidate(neighborAtPoint?(point, self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingFinger else { return }
        if behavior != .delete, cursorMovement == nil, let touch = touches.first {
            setCandidate(neighborAtPoint?(touch.location(in: self), self))
        }
        let chosen = candidate
        let shouldInsert = behavior != .delete && cursorMovement == nil
        finishTracking()
        if shouldInsert { chosen?.sendActions(for: .touchUpInside) }
        touchActivity?(false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingFinger else { return }
        finishTracking()
        touchActivity?(false)
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        UIDevice.current.playInputClick()
        sendActions(for: .touchUpInside)
        return true
    }

    func showTrackpad(_ active: Bool) {
        if active {
            guard configurationBeforeTrackpad == nil else { return }
            configurationBeforeTrackpad = configuration
            configuration?.title = ""
            configuration?.image = nil
        } else if let saved = configurationBeforeTrackpad {
            configuration = saved
            configurationBeforeTrackpad = nil
        }
    }

    func cancelTrackingTouch() {
        guard trackingFinger else { return }
        finishTracking()
        touchActivity?(false)
    }

    private func setCandidate(_ key: KeyboardKeyButton?) {
        guard candidate !== key else { return }
        candidate?.isHighlighted = false
        candidate = key
        key?.isHighlighted = true
        previewChanged?(key)
    }

    private func finishTracking() {
        trackingFinger = false
        holdTimer?.invalidate(); holdTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
        if cursorMovement != nil { trackpadActivity?(false) }
        cursorMovement = nil
        setCandidate(nil)
    }

    deinit { holdTimer?.invalidate(); repeatTimer?.invalidate() }
}


/// Rows have visual spacing, but the typing surface must not have dead strips.
final class KeyboardTouchRegion: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, bounds.contains(point) else { return nil }
        let hit = super.hitTest(point, with: event)
        if hit is UIControl { return hit }
        func controls(in view: UIView) -> [UIControl] {
            view.subviews.flatMap { child -> [UIControl] in
                if let control = child as? UIControl {
                    return control.isEnabled && !control.isHidden ? [control] : []
                }
                return controls(in: child)
            }
        }
        return controls(in: self).min { lhs, rhs in
            func distance(_ control: UIControl) -> CGFloat {
                let frame = control.convert(control.bounds, to: self)
                let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
                let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
                return hypot(dx, dy)
            }
            return distance(lhs) < distance(rhs)
        } ?? hit
    }
}
