import XCTest
import UIKit
@testable import Vyrra

final class KeyboardInputPolicyTests: XCTestCase {
    func testSentenceCapitalizationAtStartAndAfterPunctuation() {
        for text in ["", "   ", "Hello. ", "Really? ", "Yes!  ", "Hello\n", "Hello\n  "] {
            XCTAssertTrue(KeyboardInputPolicy.capitalizes(.sentences, before: text, hasText: !text.isEmpty), text)
        }
        for text in ["hello", "hello ", "hello.", "example.com "] {
            XCTAssertFalse(KeyboardInputPolicy.capitalizes(.sentences, before: text, hasText: true), text)
        }
    }

    /// Reminders reports no context, not "", for a new empty item.
    func testMissingContextCapitalizesOnlyAnEmptyField() {
        for type: UITextAutocapitalizationType in [.sentences, .words] {
            XCTAssertTrue(KeyboardInputPolicy.capitalizes(type, before: nil, hasText: false))
            // A host can also report nothing mid-text, such as Mail after a paste.
            XCTAssertFalse(KeyboardInputPolicy.capitalizes(type, before: nil, hasText: true))
        }
        XCTAssertFalse(KeyboardInputPolicy.capitalizes(.none, before: nil, hasText: false))
        XCTAssertTrue(KeyboardInputPolicy.capitalizes(.allCharacters, before: nil, hasText: true))
    }

    func testHostCapitalizationTraits() {
        XCTAssertFalse(KeyboardInputPolicy.capitalizes(.none, before: "", hasText: false))
        XCTAssertTrue(KeyboardInputPolicy.capitalizes(.words, before: "two ", hasText: true))
        XCTAssertFalse(KeyboardInputPolicy.capitalizes(.words, before: "two", hasText: true))
        XCTAssertTrue(KeyboardInputPolicy.capitalizes(.allCharacters, before: "ABC", hasText: true))
    }

    func testShiftTapDoubleTapLockAndUnlock() {
        XCTAssertEqual(KeyboardShiftState.lower.tapped(at: 1, after: nil), .upper)
        XCTAssertEqual(KeyboardShiftState.upper.tapped(at: 1.2, after: 1), .locked)
        // First tap on automatic shift turns it off; the second still locks.
        XCTAssertEqual(KeyboardShiftState.lower.tapped(at: 1.2, after: 1), .locked)
        XCTAssertEqual(KeyboardShiftState.upper.tapped(at: 2, after: 1), .lower)
        XCTAssertEqual(KeyboardShiftState.locked.tapped(at: 1.3, after: 1.2), .lower)
    }

    func testInputTypeChoosesAnAppropriateInitialPage() {
        for type: UIKeyboardType in [.numberPad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad] {
            XCTAssertTrue(KeyboardInputPolicy.startsWithNumbers(type))
        }
        for type: UIKeyboardType in [.default, .emailAddress, .URL, .webSearch] {
            XCTAssertFalse(KeyboardInputPolicy.startsWithNumbers(type))
        }
    }

    func testCursorMovementEmitsIncrementalOffsetsAndReversesWithoutDrift() {
        var movement = KeyboardCursorMovement(origin: 100)
        XCTAssertEqual(movement.offset(at: 104), 0)
        XCTAssertEqual(movement.offset(at: 118), 3)
        XCTAssertEqual(movement.offset(at: 124), 1)
        XCTAssertEqual(movement.offset(at: 124), 0)
        XCTAssertEqual(movement.offset(at: 106), -3)
        XCTAssertEqual(movement.offset(at: 94), -2)
        XCTAssertEqual(movement.offset(at: 100), 1)
    }

    func testReturnActionsMatchTheHost() {
        XCTAssertNil(KeyboardInputPolicy.returnTitle(.default))
        XCTAssertEqual(KeyboardInputPolicy.returnTitle(.search), "search")
        XCTAssertEqual(KeyboardInputPolicy.returnTitle(.go), "go")
        XCTAssertEqual(KeyboardInputPolicy.returnTitle(.done), "done")
        XCTAssertEqual(KeyboardInputPolicy.returnTitle(.send), "send")
        XCTAssertEqual(KeyboardInputPolicy.returnTitle(.next), "next")
    }
}
