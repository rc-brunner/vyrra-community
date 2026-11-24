import CoreGraphics
import Foundation

enum KeyboardSize: String, Codable, CaseIterable, Identifiable {
    case compact, standard, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func rowHeight(_ standardHeight: CGFloat) -> CGFloat {
        switch self {
        case .compact: max(44, standardHeight - 6)
        case .standard: standardHeight
        case .large: standardHeight + 10
        }
    }

    var rowGap: CGFloat { self == .compact ? 6 : KeyboardGeometry.rowGap }

    var keyRowsHeight: CGFloat {
        max(
            rowHeight(KeyboardGeometry.compactKeyHeight) * 2 + rowHeight(KeyboardGeometry.keyHeight) * 2,
            rowHeight(KeyboardGeometry.letterKeyHeight) * 3 + rowHeight(KeyboardGeometry.keyHeight)
        ) + rowGap * 3
    }

    var contentHeight: CGFloat {
        KeyboardGeometry.preferredContentHeight - KeyboardGeometry.keyRowsHeight + keyRowsHeight
    }
}

enum KeyboardTextSize: String, Codable, CaseIterable, Identifiable {
    case small, standard, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .small: 0.88
        case .standard: 1
        case .large: 1.18
        }
    }
}

struct KeyboardAppearancePreferences: Codable, Equatable {
    var size: KeyboardSize = .standard
    var textSize: KeyboardTextSize = .standard
    // Optional for compatibility with preferences saved before this setting.
    var hapticsEnabled: Bool? = nil
}

enum KeyboardGeometry {
    static let horizontalInset: CGFloat = 6
    static let topInset: CGFloat = 4
    static let bottomInset: CGFloat = 4
    static let sectionGap: CGFloat = 4
    static let commandBarHeight: CGFloat = 44
    static let primaryControlSize: CGFloat = 44
    static let secondaryControlSize: CGFloat = 44
    static let compactKeyHeight: CGFloat = 44
    static let letterKeyHeight: CGFloat = 44
    static let keyHeight: CGFloat = 44
    static let keyGap: CGFloat = 6
    static let rowGap: CGFloat = 10
    static let cornerRadius: CGFloat = 8
    static let symbolKeyRowsHeight = (compactKeyHeight * 2) + (keyHeight * 2) + (rowGap * 3)
    static let letterKeyRowsHeight = (letterKeyHeight * 3) + keyHeight + (rowGap * 3)
    static let keyRowsHeight = max(symbolKeyRowsHeight, letterKeyRowsHeight)
    static let preferredContentHeight = topInset
        + commandBarHeight
        + sectionGap
        + keyRowsHeight
        + bottomInset

    /// Seven letters align with the ten-key row; shift and delete stay at the edges.
    static func letterControlFrames(in bounds: CGRect) -> [CGRect] {
        let letters = frames(for: Array(repeating: 1, count: 7), in: bounds, referenceUnitCount: 10)
        guard letters.count == 7, let first = letters.first, let last = letters.last else { return [] }
        let controlWidth = min(44, first.minX - bounds.minX - keyGap)
        guard controlWidth > 0 else { return [] }
        return [CGRect(x: bounds.minX, y: bounds.minY, width: controlWidth, height: bounds.height)]
            + letters
            + [CGRect(x: bounds.maxX - controlWidth, y: last.minY, width: controlWidth, height: bounds.height)]
    }

    static func frames(
        for weights: [CGFloat],
        in bounds: CGRect,
        gap: CGFloat = keyGap,
        referenceUnitCount: CGFloat? = nil
    ) -> [CGRect] {
        guard !weights.isEmpty,
              bounds.width > 0,
              bounds.height > 0,
              gap >= 0,
              weights.allSatisfy({ $0 > 0 }) else {
            return []
        }

        let totalWeight = weights.reduce(0, +)
        let gapWidth = gap * CGFloat(weights.count - 1)
        let availableWidth = bounds.width - gapWidth
        guard availableWidth > 0 else { return [] }

        var unitWidth = availableWidth / totalWeight
        var contentWidth = bounds.width

        if let referenceUnitCount, referenceUnitCount >= totalWeight {
            let referenceGapWidth = gap * max(0, referenceUnitCount - 1)
            let referenceAvailableWidth = bounds.width - referenceGapWidth
            if referenceAvailableWidth > 0 {
                let referenceUnitWidth = referenceAvailableWidth / referenceUnitCount
                let proposedContentWidth = (referenceUnitWidth * totalWeight) + gapWidth
                if proposedContentWidth <= bounds.width {
                    unitWidth = referenceUnitWidth
                    contentWidth = proposedContentWidth
                }
            }
        }

        var x = bounds.minX + ((bounds.width - contentWidth) / 2)
        let contentMaxX = x + contentWidth

        return weights.enumerated().map { index, weight in
            let width = index == weights.count - 1
                ? max(0, contentMaxX - x)
                : unitWidth * weight
            defer { x += width + gap }
            return CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
        }
    }
}
