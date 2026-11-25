import XCTest
import UIKit
@testable import Vyrra

/// Exercise the real extension controller with an in-memory host document.
/// No system settings, user text, network or audio are involved.
@MainActor
final class KeyboardControllerTests: XCTestCase {
    private func keyboard(type: UIKeyboardType = .default, action: UIReturnKeyType = .default) -> TestKeyboard {
        let keyboard = TestKeyboard()
        keyboard.host.keyboardType = type
        keyboard.host.returnKeyType = action
        keyboard.loadViewIfNeeded()
        keyboard.textDidChange(nil)
        keyboard.view.frame = CGRect(x: 0, y: 0, width: 402, height: KeyboardGeometry.preferredContentHeight)
        keyboard.view.layoutIfNeeded()
        return keyboard
    }

    private func keys(_ keyboard: TestKeyboard) -> [UIButton] {
        func descend(_ view: UIView) -> [UIButton] {
            view.subviews.flatMap { child -> [UIButton] in
                guard !child.isHidden, !child.accessibilityElementsHidden else { return [] }
                if let button = child as? UIButton { return [button] }
                return descend(child)
            }
        }
        return descend(keyboard.view)
    }

    private func tap(_ label: String, on keyboard: TestKeyboard, file: StaticString = #filePath, line: UInt = #line) throws {
        let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == label }, file: file, line: line)
        key.sendActions(for: .touchUpInside)
    }

    func testKeyboardFitsNarrowAndStandardWidths() {
        for width: CGFloat in [320, 402] {
            let keyboard = keyboard()
            keyboard.view.frame.size.width = width
            keyboard.view.setNeedsLayout()
            keyboard.view.layoutIfNeeded()
            XCTAssertEqual((keyboard.inputView as? UIInputViewAudioFeedback)?.enableInputClicksWhenVisible, true)
            for button in keys(keyboard) {
                let frame = button.convert(button.bounds, to: keyboard.view)
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width + 0.01)
                XCTAssertLessThanOrEqual(frame.maxY, KeyboardGeometry.preferredContentHeight + 0.01)
            }
            // Offscreen UIKit render for visual review; not a host-app/device screenshot.
            let rendered = UIGraphicsImageRenderer(size: keyboard.view.bounds.size).image { context in
                keyboard.view.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "keyboard-controller-render-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testFirstLetterCapitalizesThenTypingReturnsToLowercase() throws {
        let keyboard = keyboard()
        XCTAssertNil(keyboard.host.documentContextBeforeInput)
        XCTAssertEqual(keys(keyboard).first { $0.accessibilityLabel == "h" }?.configuration?.title, "H")
        try tap("h", on: keyboard); try tap("i", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "Hi")
        XCTAssertEqual(keys(keyboard).first { $0.accessibilityLabel == "h" }?.configuration?.title, "h")
    }

    func testTextWithoutHostContextStaysLowercase() throws {
        let keyboard = keyboard()
        keyboard.host.text = "Pasted text"
        keyboard.host.reportsContext = false
        keyboard.textDidChange(nil)
        try tap("s", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "Pasted texts")
    }

    func testDoubleSpacePeriodCapitalizesNextSentence() throws {
        let keyboard = keyboard()
        try tap("h", on: keyboard); try tap("i", on: keyboard)
        try tap("Space", on: keyboard)
        // Some hosts report selection changes after our own insertion.
        keyboard.selectionDidChange(nil)
        try tap("Space", on: keyboard)
        try tap("h", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "Hi. H")
    }

    func testCapsLockSurvivesLettersAndUnlocks() throws {
        let keyboard = keyboard()
        try tap("Shift", on: keyboard); try tap("Shift", on: keyboard)
        try tap("a", on: keyboard); try tap("b", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "AB")
        try tap("Shift", on: keyboard); try tap("c", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "ABc")
    }

    func testNumbersSpaceReturnsToLettersAndDeleteRemovesOneGrapheme() throws {
        let keyboard = keyboard()
        try tap("Numbers", on: keyboard); try tap("1", on: keyboard); try tap("Space", on: keyboard)
        try tap("a", on: keyboard); try tap("Delete", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "1 ")
        keyboard.host.text = "Hi👨‍👩‍👧‍👦"
        try tap("Delete", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "Hi")
    }

    func testHostFieldSwitchResetsModeAndUsesSearchReturn() throws {
        let keyboard = keyboard(type: .decimalPad)
        try tap("1", on: keyboard)
        keyboard.host.documentIdentifier = UUID()
        keyboard.host.keyboardType = .webSearch
        keyboard.host.returnKeyType = .search
        keyboard.host.text = ""
        keyboard.textDidChange(nil)
        try tap("a", on: keyboard); try tap("Search", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "A\n")
    }

    func testEmailHasAddressKeysAndRespectsNoCapitalization() throws {
        let keyboard = keyboard(type: .emailAddress)
        keyboard.host.autocapitalizationType = .none
        keyboard.textDidChange(nil)
        try tap("a", on: keyboard); try tap("At sign", on: keyboard); try tap("b", on: keyboard); try tap("Period", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "a@b.")
    }

    func testFingerReleaseTypesOnceAndDraggingRetargetsToNeighbor() throws {
        let keyboard = keyboard()
        let a = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "a" } as? KeyboardKeyButton)
        let b = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "b" } as? KeyboardKeyButton)
        let touch = KeyboardTestTouch(view: keyboard.view, point: a.convert(CGPoint(x: a.bounds.midX, y: a.bounds.midY), to: keyboard.view))
        a.touchesBegan([touch], with: nil)
        XCTAssertEqual(keyboard.host.text, "")
        touch.point = b.convert(CGPoint(x: b.bounds.midX, y: b.bounds.midY), to: keyboard.view)
        a.touchesMoved([touch], with: nil)
        a.touchesEnded([touch], with: nil)
        XCTAssertEqual(keyboard.host.text, "B")
    }

    func testCancelledTouchDoesNotType() throws {
        let keyboard = keyboard()
        let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "a" } as? KeyboardKeyButton)
        let touch = KeyboardTestTouch(view: key, point: CGPoint(x: key.bounds.midX, y: key.bounds.midY))
        key.touchesBegan([touch], with: nil)
        key.touchesCancelled([touch], with: nil)
        XCTAssertEqual(keyboard.host.text, "")
    }

    func testCharacterPopUpShowsOnPressTracksFingerAndHidesOnRelease() throws {
        let keyboard = keyboard()
        let a = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "a" } as? KeyboardKeyButton)
        let j = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "j" } as? KeyboardKeyButton)
        let preview = try XCTUnwrap(keyboard.view.subviews.first {
            $0.accessibilityIdentifier == "key-character-preview"
        } as? UILabel)
        let touch = KeyboardTestTouch(view: keyboard.view, point: a.convert(CGPoint(x: a.bounds.midX, y: a.bounds.midY), to: keyboard.view))
        a.touchesBegan([touch], with: nil)
        XCTAssertFalse(preview.isHidden)
        XCTAssertEqual(preview.text, "A")
        XCTAssertGreaterThan(preview.bounds.width, a.bounds.width)
        XCTAssertEqual(keyboard.host.text, "")

        touch.point = j.convert(CGPoint(x: j.bounds.midX, y: j.bounds.midY), to: keyboard.view)
        a.touchesMoved([touch], with: nil)
        XCTAssertEqual(preview.text, "J")
        let rendered = UIGraphicsImageRenderer(size: keyboard.view.bounds.size).image { context in
            keyboard.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "keyboard-character-pop-up-J"
        attachment.lifetime = .keepAlways
        add(attachment)

        a.touchesEnded([touch], with: nil)
        XCTAssertTrue(preview.isHidden)
        XCTAssertEqual(keyboard.host.text, "J")
    }

    func testCharacterPopUpsStayWithinKeyboardAtBothEdgesAndCancelCleanly() throws {
        for width: CGFloat in [320, 402] {
            let keyboard = keyboard()
            keyboard.view.frame.size.width = width
            keyboard.view.layoutIfNeeded()
            let preview = try XCTUnwrap(keyboard.view.subviews.first {
                $0.accessibilityIdentifier == "key-character-preview"
            })
            for letter in ["q", "p"] {
                let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == letter } as? KeyboardKeyButton)
                let touch = KeyboardTestTouch(view: key, point: CGPoint(x: key.bounds.midX, y: key.bounds.midY))
                key.touchesBegan([touch], with: nil)
                XCTAssertFalse(preview.isHidden)
                XCTAssertTrue(keyboard.view.bounds.contains(preview.frame))
                key.touchesCancelled([touch], with: nil)
                XCTAssertTrue(preview.isHidden)
                XCTAssertEqual(keyboard.host.text, "")
            }
        }
    }

    func testHoldingDeleteRepeatsAndStopsOnRelease() throws {
        let keyboard = keyboard()
        keyboard.host.text = "abcdefghij"
        let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "Delete" } as? KeyboardKeyButton)
        let touch = KeyboardTestTouch(view: key, point: CGPoint(x: key.bounds.midX, y: key.bounds.midY))
        key.touchesBegan([touch], with: nil)
        XCTAssertEqual(keyboard.host.text, "abcdefghi")
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        key.touchesEnded([touch], with: nil)
        let afterRelease = keyboard.host.text
        XCTAssertLessThan(afterRelease.count, 9)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(keyboard.host.text, afterRelease)
    }

    func testSpaceHoldMovesCursorWithoutInsertingASpace() throws {
        let keyboard = keyboard()
        keyboard.host.text = "some sample text"
        let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "Space" } as? KeyboardKeyButton)
        let center = CGPoint(x: key.bounds.midX, y: key.bounds.midY)
        let touch = KeyboardTestTouch(view: key, point: center)
        key.touchesBegan([touch], with: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        XCTAssertEqual(keys(keyboard).first { $0.accessibilityLabel == "a" }?.configuration?.title, "")
        touch.point.x += 18
        key.touchesMoved([touch], with: nil)
        touch.point.x -= 6
        key.touchesMoved([touch], with: nil)
        key.touchesEnded([touch], with: nil)
        XCTAssertNotEqual(keys(keyboard).first { $0.accessibilityLabel == "a" }?.configuration?.title, "")
        XCTAssertEqual(keyboard.host.cursorOffsets, [3, -1])
        XCTAssertEqual(keyboard.host.text, "some sample text")
    }

    func testRowSpacingIsAnActiveTypingArea() throws {
        let keyboard = keyboard()
        let q = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "q" })
        let belowTopRow = q.convert(CGPoint(x: q.bounds.midX, y: q.bounds.maxY + 4), to: keyboard.view)
        XCTAssertTrue(keyboard.view.hitTest(belowTopRow, with: nil) is UIButton)
    }

    func testAutomaticallyEnabledReturnIsDisabledForEmptyField() throws {
        let keyboard = keyboard(action: .go)
        keyboard.host.enablesReturnKeyAutomatically = true
        keyboard.textDidChange(nil)
        XCTAssertEqual(keys(keyboard).first { $0.accessibilityLabel == "Go" }?.isEnabled, false)
        try tap("x", on: keyboard)
        XCTAssertEqual(keys(keyboard).first { $0.accessibilityLabel == "Go" }?.isEnabled, true)
    }

    func testOnlyActivePhrasesReplaceTheKeysAtTheSameHeight() throws {
        let now = Date()
        let liveSession = KeyboardActivationPayload(id: "keyboard-session", expiresAt: nil, updatedAt: now)
        func phrase(_ state: KeyboardSessionState, result: String? = nil) -> KeyboardSessionPayload {
            KeyboardSessionPayload(
                state: state, startedAt: now, resultText: result, errorText: nil,
                updatedAt: now, sessionID: "phrase"
            )
        }
        let states: [(name: String, containerOn: Bool, session: KeyboardSessionPayload?, activation: KeyboardActivationPayload?)] = [
            ("full-access-off", false, nil, nil),
            ("no-session", true, .ready(updatedAt: now), nil),
            ("session-mic-on", true, .ready(updatedAt: now), liveSession),
            ("starting", true, phrase(.opening), liveSession),
            ("preparing-voice", true, phrase(.warming), liveSession),
            ("listening", true, phrase(.listening), liveSession),
            ("paused", true, phrase(.paused), liveSession),
            ("preparing-text", true, phrase(.processing), liveSession),
            ("insert-ready", true, phrase(.insertReady, result: "Move the launch checklist to Friday."), liveSession),
            ("needs-attention", true, phrase(.error), liveSession)
        ]

        for state in states {
            for width: CGFloat in [320, 402] {
                for style: UIUserInterfaceStyle in [.light, .dark] {
                    let keyboard = TestKeyboard()
                    keyboard.overrideUserInterfaceStyle = style
                    keyboard.testSharedContainer = (state.containerOn, state.session.map {
                        KeyboardSharedPayload(
                            latestDraft: nil, shortcuts: [], session: $0,
                            activation: state.activation, updatedAt: now
                        )
                    })
                    keyboard.loadViewIfNeeded()
                    keyboard.view.frame = CGRect(x: 0, y: 0, width: width, height: KeyboardGeometry.preferredContentHeight)
                    keyboard.view.layoutIfNeeded()
                    let panel = try XCTUnwrap(keyboard.view.subviews.compactMap { $0 as? KeyboardDictationPanel }.first)
                    let active = state.session?.state == .listening || state.session?.state == .paused
                    let buttons = keys(keyboard)
                    XCTAssertEqual(panel.isHidden, !active)
                    XCTAssertEqual(panel.accessibilityElementsHidden, !active)
                    XCTAssertEqual(buttons.contains { $0.accessibilityLabel == "q" }, !active)
                    XCTAssertEqual(keyboard.view.bounds.height, KeyboardGeometry.preferredContentHeight)
                    if active {
                        XCTAssertEqual(panel.frame, keyboard.view.bounds)
                        XCTAssertEqual(panel.waveform.center.x, width / 2, accuracy: 0.01)
                        XCTAssertEqual(panel.cancelButton.frame.minX, 12, accuracy: 0.01)
                        XCTAssertEqual(width - panel.finishButton.frame.maxX, 12, accuracy: 0.01)
                        XCTAssertGreaterThanOrEqual(panel.finishButton.bounds.width, 44)
                        XCTAssertEqual(panel.waveform.isHidden, state.session?.state == .paused)
                        XCTAssertEqual(panel.waveform.activity, state.session?.state == .listening ? .listening : .idle)
                        XCTAssertEqual(panel.finishButton.accessibilityValue, state.session?.state == .paused ? "Paused" : "Listening")
                    } else {
                        let button = try XCTUnwrap(buttons.first)
                        XCTAssertEqual(button.convert(button.bounds, to: keyboard.view).minX, KeyboardGeometry.horizontalInset, accuracy: 0.01)
                        XCTAssertTrue(button.configuration?.image?.isSymbolImage == true)
                    }
                    XCTAssertNil(visibleGuidanceLabel(keyboard))

                    if width == 402 {
                        let rendered = UIGraphicsImageRenderer(size: keyboard.view.bounds.size).image { context in
                            keyboard.view.layer.render(in: context.cgContext)
                        }
                        let attachment = XCTAttachment(image: rendered)
                        attachment.name = "keyboard-\(state.name)-\(style == .dark ? "dark" : "light")"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }

                    let helpStates = ["full-access-off", "no-session", "needs-attention"]
                    if helpStates.contains(state.name) {
                        let button = try XCTUnwrap(buttons.first)
                        let frame = button.convert(button.bounds, to: keyboard.view)
                        button.sendActions(for: .touchUpInside)
                        keyboard.view.layoutIfNeeded()
                        let tip = try XCTUnwrap(visibleGuidanceLabel(keyboard))
                        let tipFrame = tip.convert(tip.bounds, to: keyboard.view)
                        XCTAssertGreaterThanOrEqual(tipFrame.minY, frame.maxY)
                        XCTAssertLessThanOrEqual(tipFrame.maxX, width)
                        try tap("q", on: keyboard)
                        XCTAssertNil(visibleGuidanceLabel(keyboard))
                    }
                }
            }
        }
    }

    func testDictationControlsKeepPendingStateAcrossDelayedAppUpdates() throws {
        let keyboard = TestKeyboard()
        let activationID = "keyboard-activation"
        let phraseID = "phrase"
        func publish(_ state: KeyboardSessionState, acknowledgment: KeyboardSessionCommandAcknowledgment? = nil) {
            let now = Date()
            let sessionID: String? = switch state {
            case .inserted: "previous-phrase"
            case .ready: nil
            default: phraseID
            }
            keyboard.testSharedContainer = (true, KeyboardSharedPayload(
                latestDraft: nil,
                shortcuts: [],
                session: KeyboardSessionPayload(
                    state: state, startedAt: now, resultText: nil, errorText: nil, updatedAt: now,
                    sessionID: sessionID
                ),
                activation: KeyboardActivationPayload(id: activationID, expiresAt: nil, updatedAt: now),
                commandAcknowledgment: acknowledgment,
                updatedAt: now
            ))
            keyboard.loadViewIfNeeded()
            keyboard.reloadPayload()
        }

        publish(.inserted)
        let button = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "Start Vyrra dictation" })
        XCTAssertEqual(button.accessibilityValue, "Microphone on")
        let panel = try XCTUnwrap(keyboard.view.subviews.compactMap { $0 as? KeyboardDictationPanel }.first)
        let background = button.configuration?.baseBackgroundColor
        try tap("Start Vyrra dictation", on: keyboard)
        let start = try XCTUnwrap(keyboard.writtenCommands.last)
        XCTAssertEqual(start.type, .start)
        XCTAssertEqual(start.sessionID, activationID)

        publish(.inserted, acknowledgment: .init(commandID: "another-command", accepted: false))
        XCTAssertEqual(button.accessibilityLabel, "Vyrra is starting dictation")
        try tap("Vyrra is starting dictation", on: keyboard)
        XCTAssertEqual(keyboard.writtenCommands.count, 1)

        publish(.ready, acknowledgment: .init(commandID: start.id, accepted: true))
        XCTAssertEqual(button.accessibilityLabel, "Vyrra is starting dictation")
        publish(.opening, acknowledgment: .init(commandID: start.id, accepted: true))
        XCTAssertEqual(button.accessibilityLabel, "Vyrra is starting dictation")
        XCTAssertTrue(panel.isHidden)
        publish(.listening)
        XCTAssertFalse(panel.isHidden)
        XCTAssertEqual(panel.finishButton.accessibilityValue, "Listening")
        let waveColor = panel.waveform.tintColor

        try tap("Finish Vyrra dictation", on: keyboard)
        let finish = try XCTUnwrap(keyboard.writtenCommands.last)
        XCTAssertEqual(finish.type, .finish)
        XCTAssertEqual(finish.sessionID, phraseID)
        publish(.listening)
        XCTAssertEqual(panel.finishButton.accessibilityValue, "Finishing")
        XCTAssertFalse(panel.cancelButton.isEnabled)
        XCTAssertEqual(panel.waveform.tintColor, waveColor)
        XCTAssertEqual(keyboard.finishFeedbackCount, 0)
        try tap("Cancel Vyrra dictation", on: keyboard)
        try tap("Finish Vyrra dictation", on: keyboard)
        XCTAssertEqual(keyboard.writtenCommands.count, 2)

        publish(.listening, acknowledgment: .init(commandID: finish.id, accepted: false))
        XCTAssertEqual(visibleGuidanceLabel(keyboard)?.text, "Couldn’t finish. Try again.")
        XCTAssertTrue(panel.finishButton.isEnabled)
        XCTAssertTrue(panel.cancelButton.isEnabled)
        XCTAssertEqual(keyboard.finishFeedbackCount, 0)

        try tap("Finish Vyrra dictation", on: keyboard)
        let retry = try XCTUnwrap(keyboard.writtenCommands.last)
        publish(.processing, acknowledgment: .init(commandID: retry.id, accepted: true))
        XCTAssertFalse(panel.isHidden)
        XCTAssertFalse(panel.finishButton.isEnabled)
        XCTAssertFalse(panel.cancelButton.isEnabled)
        XCTAssertEqual(panel.finishButton.accessibilityValue, "Finishing")
        XCTAssertEqual(keyboard.host.text, "")
        XCTAssertNil(visibleGuidanceLabel(keyboard))
        XCTAssertEqual(button.configuration?.baseBackgroundColor, background)
        XCTAssertEqual(keyboard.finishFeedbackCount, 1)
        publish(.processing, acknowledgment: .init(commandID: retry.id, accepted: true))
        XCTAssertEqual(keyboard.finishFeedbackCount, 1)

        publish(.listening)
        try tap("Cancel Vyrra dictation", on: keyboard)
        let cancel = try XCTUnwrap(keyboard.writtenCommands.last)
        XCTAssertEqual(cancel.type, .cancel)
        XCTAssertEqual(cancel.sessionID, phraseID)
        XCTAssertNotNil(cancel.expiresAt)
        publish(.listening)
        try tap("Finish Vyrra dictation", on: keyboard)
        XCTAssertEqual(keyboard.writtenCommands.last?.id, cancel.id)
        publish(.listening, acknowledgment: .init(commandID: cancel.id, accepted: false))
        XCTAssertEqual(visibleGuidanceLabel(keyboard)?.text, "Couldn’t cancel. Try again.")
        try tap("Cancel Vyrra dictation", on: keyboard)
        let secondCancel = try XCTUnwrap(keyboard.writtenCommands.last)
        publish(.ready, acknowledgment: .init(commandID: secondCancel.id, accepted: true))
        XCTAssertTrue(panel.isHidden)
        XCTAssertEqual(keyboard.host.text, "")
        XCTAssertEqual(keyboard.finishFeedbackCount, 1)
    }

    func testSurfaceTransitionCanReverseMidflightAndHonorsReduceMotion() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        let keyboard = TestKeyboard()
        keyboard.requiresGlobe = true
        keyboard.host.autocapitalizationType = .none
        host.addChild(keyboard)
        keyboard.view.frame = CGRect(x: 0, y: 100, width: 402, height: KeyboardGeometry.preferredContentHeight)
        host.view.addSubview(keyboard.view)
        keyboard.didMove(toParent: host)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        keyboard.view.layoutIfNeeded()
        let panel = try XCTUnwrap(keyboard.view.subviews.compactMap { $0 as? KeyboardDictationPanel }.first)
        var reduceMotion = false
        panel.waveform.reduceMotionEnabled = { reduceMotion }
        let key = try XCTUnwrap(keys(keyboard).first { $0.accessibilityLabel == "q" } as? KeyboardKeyButton)
        let touch = KeyboardTestTouch(view: key, point: CGPoint(x: key.bounds.midX, y: key.bounds.midY))
        key.touchesBegan([touch], with: nil)
        func publish(_ state: KeyboardSessionState) {
            let now = Date()
            keyboard.testSharedContainer = (true, KeyboardSharedPayload(
                latestDraft: nil, shortcuts: [], session: KeyboardSessionPayload(state: state,
                    startedAt: now, resultText: nil, errorText: nil, updatedAt: now, sessionID: "phrase"),
                updatedAt: now))
            keyboard.reloadPayload()
            CATransaction.flush()
        }

        let originalFrame = keyboard.view.frame
        publish(.listening)
        XCTAssertFalse(panel.layer.animationKeys()?.isEmpty ?? true)
        XCTAssertTrue(panel.isUserInteractionEnabled)
        XCTAssertFalse(panel.inputModeButton.isHidden)
        key.touchesEnded([touch], with: nil)
        XCTAssertTrue(keyboard.host.text.isEmpty)
        XCTAssertFalse(keys(keyboard).contains(key))
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        publish(.processing)
        publish(.listening)
        reduceMotion = true
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertFalse(panel.isHidden)
        XCTAssertEqual(panel.alpha, 1)
        XCTAssertEqual(panel.transform, .identity)
        XCTAssertTrue(panel.layer.animationKeys()?.isEmpty != false)
        XCTAssertTrue(panel.waveform.layer.sublayers?.allSatisfy { $0.animationKeys()?.isEmpty != false } == true)
        XCTAssertTrue(keyboard.view.hitTest(panel.convert(panel.finishButton.center, to: keyboard.view), with: nil) === panel.finishButton)
        keyboard.requiresGlobe = false
        keyboard.textDidChange(nil)
        XCTAssertTrue(panel.inputModeButton.isHidden)
        publish(.error)
        XCTAssertTrue(panel.isHidden)
        XCTAssertFalse(panel.isUserInteractionEnabled)
        XCTAssertEqual(keyboard.view.frame, originalFrame)
        try tap("q", on: keyboard)
        XCTAssertEqual(keyboard.host.text, "q")
    }

    private func visibleGuidanceLabel(_ keyboard: TestKeyboard) -> UILabel? {
        func find(in view: UIView) -> UILabel? {
            guard !view.isHidden, !(view is UIButton) else { return nil }
            if let label = view as? UILabel, label.accessibilityIdentifier == "keyboard-guidance" { return label }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        return find(in: keyboard.view)
    }

    private func waveform() throws -> (UIWindow, KeyboardWaveformView, [CALayer]) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        let wave = KeyboardWaveformView(frame: CGRect(x: 40, y: 100, width: 156, height: 50))
        wave.reduceMotionEnabled = { false }
        window.rootViewController?.view.addSubview(wave)
        wave.layoutIfNeeded()
        let bars = try XCTUnwrap(wave.layer.sublayers)
        XCTAssertEqual(bars.count, 11)
        return (window, wave, bars)
    }

    func testMicrophoneMeterShowsOnlyFreshLevelsAndDropsCancelledAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = try XCTUnwrap(KeyboardLevelMeter(writable: false, container: root))
        let writer = try XCTUnwrap(KeyboardLevelMeter(writable: true, container: root))
        XCTAssertEqual(reader.latest(now: 10), 0)
        writer.publish(0.75, now: 10)
        XCTAssertEqual(reader.latest(now: 10.1), 0.75, accuracy: 0.01)
        XCTAssertEqual(reader.latest(now: 10.5), 0)
        writer.publish(1, now: 11)
        XCTAssertEqual(reader.latest(now: 11), 1)
        writer.clear()
        XCTAssertEqual(reader.latest(now: 11.01), 0)
    }

    func testPanelBarsRespondToLevelAndHoldStillWithReduceMotion() throws {
        let (window, wave, bars) = try waveform()
        defer { window.isHidden = true }
        var amplitude: CGFloat = 0
        wave.levelSource = { amplitude }
        wave.activity = .listening
        let last = try XCTUnwrap(bars.last)
        let quiet = last.bounds.height
        amplitude = 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.22))
        XCTAssertGreaterThan(last.bounds.height, quiet + 4)
        wave.reduceMotionEnabled = { true }
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        let still = last.bounds.height
        amplitude = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))
        XCTAssertEqual(last.bounds.height, still)
    }

    func testListeningWaveformMovesOverTimeAndStopsWhenFinished() throws {
        let (window, wave, bars) = try waveform()
        defer { window.isHidden = true }
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
        wave.activity = .listening
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        let firstHeights = try bars.map { try XCTUnwrap($0.presentation()).bounds.height }
        RunLoop.main.run(until: Date().addingTimeInterval(0.20))
        let changes = try zip(bars, firstHeights).map { bar, first in
            abs(try XCTUnwrap(bar.presentation()).bounds.height - first)
        }
        XCTAssertGreaterThan(changes.max() ?? 0, 2, "The rendered waveform must actually move.")
        wave.activity = .idle
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
        XCTAssertTrue(bars.allSatisfy { $0.bounds.height >= $0.bounds.width })
    }

    func testWaveformStopsWhenDetachedAndResumesAnActiveSession() throws {
        let (window, wave, bars) = try waveform()
        defer { window.isHidden = true }
        wave.activity = .listening
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty == false })
        wave.removeFromSuperview()
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
        window.rootViewController?.view.addSubview(wave)
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty == false })
    }

    func testReduceMotionChangesStopAndResumeVisibleWaveform() throws {
        let (window, wave, bars) = try waveform()
        defer { window.isHidden = true }
        var reduceMotion = true
        wave.reduceMotionEnabled = { reduceMotion }
        wave.activity = .listening
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
        reduceMotion = false
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty == false })
        reduceMotion = true
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
    }
}

@MainActor
private final class TestKeyboard: KeyboardViewController {
    let host = KeyboardTestDocument()
    /// Stands in for the App Group: on with a payload, or off like Full Access off.
    var testSharedContainer: (hasSharedContainer: Bool, payload: KeyboardSharedPayload?) = (false, nil)
    var requiresGlobe: Bool?
    private(set) var writtenCommands: [KeyboardSessionCommand] = []
    private(set) var finishFeedbackCount = 0
    override var textDocumentProxy: UITextDocumentProxy { host }
    override var hasFullAccess: Bool { false }
    override var needsInputModeSwitchKey: Bool { requiresGlobe ?? super.needsInputModeSwitchKey }
    override func readSharedPayload() -> (hasSharedContainer: Bool, payload: KeyboardSharedPayload?) {
        testSharedContainer
    }

    override func writeSharedCommand(_ command: KeyboardSessionCommand) throws {
        writtenCommands.append(command)
    }

    override func playFinishFeedback() {
        finishFeedbackCount += 1
    }
}

@MainActor
private final class KeyboardTestDocument: NSObject, UITextDocumentProxy {
    var text = ""
    /// Off stands in for a host that has text but can't say what is around the caret.
    var reportsContext = true
    var cursorOffsets: [Int] = []
    var documentIdentifier = UUID()
    /// Like Reminders, nil rather than "" when nothing is before the caret.
    var documentContextBeforeInput: String? { reportsContext && !text.isEmpty ? text : nil }
    var documentContextAfterInput: String? { reportsContext ? "" : nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !text.isEmpty }
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .sentences
    var enablesReturnKeyAutomatically = false
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) { cursorOffsets.append(offset) }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}


@MainActor
private final class KeyboardTestTouch: UITouch {
    weak var coordinateView: UIView?
    var point: CGPoint
    init(view: UIView, point: CGPoint) {
        coordinateView = view
        self.point = point
        super.init()
    }
    override func location(in view: UIView?) -> CGPoint {
        coordinateView?.convert(point, to: view) ?? point
    }
}
