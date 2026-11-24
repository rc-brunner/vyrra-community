import SwiftUI
import UIKit
import XCTest
@testable import Vyrra

/// Guards the C1 fix from the 2026-10-08 design review: every custom color
/// resolves to a light, dark and Increase Contrast variant that meets WCAG
/// contrast, both as text on the page and under the system-background label
/// the app draws on accent fills (the Hold disc, primary buttons, the toast).
final class VyrraColorContrastTests: XCTestCase {
    private static let white: UInt32 = 0xFFFFFF
    private static let black: UInt32 = 0x000000
    private static let elevatedDark: UInt32 = 0x1C1C1E

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)
    private let lightHighContrast = UITraitCollection { traits in
        traits.userInterfaceStyle = .light
        traits.accessibilityContrast = .high
    }
    private let darkHighContrast = UITraitCollection { traits in
        traits.userInterfaceStyle = .dark
        traits.accessibilityContrast = .high
    }

    private var palettes: [(String, VyrraAdaptiveColor)] {
        let accents = VyrraAccent.allCases.compactMap { accent in
            accent.palette.map { (accent.title, $0) }
        }
        return accents + [
            ("success", VyrraTheme.successPalette),
            ("warning", VyrraTheme.warningPalette),
            ("danger", VyrraTheme.dangerPalette)
        ]
    }

    func testMonoFollowsPrimaryAndEveryOtherAccentIsAdaptive() {
        XCTAssertNil(VyrraAccent.monochrome.palette)
        for accent in VyrraAccent.allCases where accent != .monochrome {
            XCTAssertNotNil(accent.palette, "\(accent.title) must be adaptive")
        }
    }

    func testDynamicProviderResolvesEachVariant() {
        for (name, palette) in palettes {
            XCTAssertEqual(resolvedHex(palette, light), palette.light, name)
            XCTAssertEqual(resolvedHex(palette, dark), palette.dark, name)
            XCTAssertEqual(resolvedHex(palette, lightHighContrast), palette.lightHighContrast, name)
            XCTAssertEqual(resolvedHex(palette, darkHighContrast), palette.darkHighContrast, name)
        }
    }

    func testLightVariantsMeetTextContrastOnWhiteAndUnderWhiteLabels() {
        for (name, palette) in palettes {
            XCTAssertGreaterThanOrEqual(contrast(palette.light, Self.white), 4.5, name)
        }
    }

    func testDarkVariantsMeetTextContrastOnBlackAndElevatedSurfaces() {
        for (name, palette) in palettes {
            // Text on black, and a black (systemBackground) label on the fill.
            XCTAssertGreaterThanOrEqual(contrast(palette.dark, Self.black), 5.5, name)
            // Text on grouped and elevated dark surfaces.
            XCTAssertGreaterThanOrEqual(contrast(palette.dark, Self.elevatedDark), 4.5, name)
        }
    }

    func testIncreaseContrastVariantsReachSevenToOne() {
        for (name, palette) in palettes {
            XCTAssertGreaterThanOrEqual(contrast(palette.lightHighContrast, Self.white), 7, name)
            XCTAssertGreaterThanOrEqual(contrast(palette.darkHighContrast, Self.black), 7, name)
            XCTAssertGreaterThanOrEqual(contrast(palette.darkHighContrast, Self.elevatedDark), 7, name)
        }
    }

    func testDangerTextOnBlackClearsTheReviewedFailure() {
        // Fixed #BF2424 measured 3.49:1 on black in the review.
        XCTAssertLessThan(contrast(0xBF2424, Self.black), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(resolvedHex(VyrraTheme.dangerPalette, dark), Self.black), 4.5)
    }

    // MARK: - Helpers

    private func resolvedHex(_ palette: VyrraAdaptiveColor, _ traits: UITraitCollection) -> UInt32 {
        let color = palette.uiColor.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let channels = [red, green, blue].map { UInt32(($0 * 255).rounded()) }
        return (channels[0] << 16) | (channels[1] << 8) | channels[2]
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 0xFF)
            + 0.7152 * linear((hex >> 8) & 0xFF)
            + 0.0722 * linear(hex & 0xFF)
    }
}
