import XCTest
@testable import Vyrra

final class KeyboardGeometryTests: XCTestCase {
    func testPreferredContentHeightClosesExactly() {
        XCTAssertEqual(
            KeyboardGeometry.preferredContentHeight,
            KeyboardGeometry.topInset
                + KeyboardGeometry.commandBarHeight
                + KeyboardGeometry.sectionGap
                + KeyboardGeometry.keyRowsHeight
                + KeyboardGeometry.bottomInset,
            accuracy: 0.001
        )
        XCTAssertEqual(KeyboardGeometry.preferredContentHeight, 262, accuracy: 0.001)
    }

    func testToolbarKeepsControlsTappableWithoutOversizing() {
        XCTAssertEqual(KeyboardGeometry.compactKeyHeight, 44, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(KeyboardGeometry.compactKeyHeight, 44)
        XCTAssertEqual(KeyboardGeometry.commandBarHeight, 44, accuracy: 0.001)
        XCTAssertEqual(KeyboardGeometry.primaryControlSize, 44, accuracy: 0.001)
        XCTAssertLessThanOrEqual(
            KeyboardGeometry.primaryControlSize,
            KeyboardGeometry.commandBarHeight
        )
    }

    func testAlphabetRowsHaveEqualHeightWithoutChangingSymbolRows() {
        let alphabetRows = Array(repeating: KeyboardGeometry.letterKeyHeight, count: 3)
        let symbolRows = [
            KeyboardGeometry.compactKeyHeight,
            KeyboardGeometry.compactKeyHeight,
            KeyboardGeometry.keyHeight,
            KeyboardGeometry.keyHeight
        ]

        XCTAssertEqual(alphabetRows, [44, 44, 44])
        XCTAssertEqual(symbolRows, [44, 44, 44, 44])
        XCTAssertEqual(KeyboardGeometry.letterKeyRowsHeight, KeyboardGeometry.keyRowsHeight)
        XCTAssertEqual(KeyboardGeometry.symbolKeyRowsHeight, KeyboardGeometry.keyRowsHeight)
        XCTAssertEqual(KeyboardGeometry.preferredContentHeight, 262, accuracy: 0.001)
    }

    func testTenKeyRowsRemainTappableAtSupportedPortraitAndLandscapeWidths() {
        for width in containerWidths {
            let frames = KeyboardGeometry.frames(
                for: Array(repeating: 1, count: 10),
                in: CGRect(x: 0, y: 0, width: width, height: KeyboardGeometry.compactKeyHeight)
            )

            XCTAssertEqual(frames.count, 10)
            XCTAssertGreaterThanOrEqual(frames.map(\.width).min() ?? 0, 23)
            XCTAssertEqual(frames.last?.maxX ?? 0, width, accuracy: 0.001)
        }
    }

    private let containerWidths: [CGFloat] = [292, 315, 347, 374, 402, 858]

    func testTenKeyRowsFillEverySupportedWidthWithoutOverlap() {
        for width in containerWidths {
            let bounds = CGRect(x: 0, y: 0, width: width, height: KeyboardGeometry.compactKeyHeight)
            let frames = KeyboardGeometry.frames(for: Array(repeating: 1, count: 10), in: bounds)

            XCTAssertEqual(frames.count, 10)
            XCTAssertEqual(frames.first!.minX, bounds.minX, accuracy: 0.001)
            XCTAssertEqual(frames.last!.maxX, bounds.maxX, accuracy: 0.001)
            assertConsistentGaps(frames)
            assertNoOverlap(frames)
            XCTAssertTrue(frames.allSatisfy { $0.width >= 23 })
            XCTAssertTrue(frames.allSatisfy { $0.height == KeyboardGeometry.compactKeyHeight })
        }
    }

    func testHomeRowIsCenteredAndMatchesTopRowKeyWidth() {
        for width in containerWidths {
            let bounds = CGRect(x: 0, y: 0, width: width, height: KeyboardGeometry.keyHeight)
            let topFrames = KeyboardGeometry.frames(for: Array(repeating: 1, count: 10), in: bounds)
            let homeFrames = KeyboardGeometry.frames(
                for: Array(repeating: 1, count: 9),
                in: bounds,
                referenceUnitCount: 10
            )

            XCTAssertEqual(homeFrames.count, 9)
            XCTAssertEqual(homeFrames.first!.width, topFrames.first!.width, accuracy: 0.001)
            XCTAssertEqual(homeFrames.first!.minX, bounds.maxX - homeFrames.last!.maxX, accuracy: 0.001)
            XCTAssertGreaterThan(homeFrames.first!.minX, 0)
            assertConsistentGaps(homeFrames)
            assertNoOverlap(homeFrames)
        }
    }

    func testWeightedRowsPreserveRatiosAndFillWidth() {
        let weights: [CGFloat] = [1.25, 1, 1, 1, 1, 1, 1, 1, 1.25]

        for width in containerWidths {
            let bounds = CGRect(x: 0, y: 0, width: width, height: KeyboardGeometry.keyHeight)
            let frames = KeyboardGeometry.frames(for: weights, in: bounds)

            XCTAssertEqual(frames.first!.minX, bounds.minX, accuracy: 0.001)
            XCTAssertEqual(frames.last!.maxX, bounds.maxX, accuracy: 0.001)
            XCTAssertEqual(frames.first!.width / frames[1].width, 1.25, accuracy: 0.001)
            XCTAssertEqual(frames.last!.width / frames[1].width, 1.25, accuracy: 0.001)
            assertConsistentGaps(frames)
            assertNoOverlap(frames)
        }
    }

    func testBottomLettersMatchTheTopRowWidthAndStayCentered() {
        for width in containerWidths {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 44)
            let top = KeyboardGeometry.frames(for: Array(repeating: 1, count: 10), in: bounds)
            let bottom = KeyboardGeometry.letterControlFrames(in: bounds)
            XCTAssertEqual(bottom.count, 9)
            XCTAssertEqual(bottom[1].width, top[0].width, accuracy: 0.001)
            XCTAssertEqual(bottom[1].minX, width - bottom[7].maxX, accuracy: 0.001)
            XCTAssertEqual(bottom[0].minX, 0, accuracy: 0.001)
            XCTAssertEqual(bottom[8].maxX, width, accuracy: 0.001)
            assertNoOverlap(bottom)
        }
    }

    func testInvalidGeometryReturnsNoFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: KeyboardGeometry.keyHeight)

        XCTAssertTrue(KeyboardGeometry.frames(for: [], in: bounds).isEmpty)
        XCTAssertTrue(KeyboardGeometry.frames(for: [1, 0, 1], in: bounds).isEmpty)
        XCTAssertTrue(KeyboardGeometry.frames(for: [1, -1, 1], in: bounds).isEmpty)
        XCTAssertTrue(KeyboardGeometry.frames(for: [1], in: .zero).isEmpty)
    }

    private func assertConsistentGaps(
        _ frames: [CGRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in frames.indices.dropLast() {
            XCTAssertEqual(
                frames[index + 1].minX - frames[index].maxX,
                KeyboardGeometry.keyGap,
                accuracy: 0.001,
                file: file,
                line: line
            )
        }
    }

    private func assertNoOverlap(
        _ frames: [CGRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for index in frames.indices.dropLast() {
            XCTAssertGreaterThanOrEqual(
                frames[index + 1].minX,
                frames[index].maxX,
                file: file,
                line: line
            )
        }
    }
}
