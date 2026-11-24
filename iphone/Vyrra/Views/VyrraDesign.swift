import SwiftUI
import UIKit

enum VyrraAccent: String, CaseIterable, Identifiable {
    case monochrome
    case forest
    case indigo
    case ocean
    case plum
    case ember

    static let storageKey = "vyrraAccentColor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome:
            "Mono"
        case .forest:
            "Forest"
        case .indigo:
            "Indigo"
        case .ocean:
            "Ocean"
        case .plum:
            "Plum"
        case .ember:
            "Ember"
        }
    }

    var subtitle: String {
        switch self {
        case .monochrome:
            "Classic"
        case .forest:
            "Calm"
        case .indigo:
            "Focused"
        case .ocean:
            "Clear"
        case .plum:
            "Warm"
        case .ember:
            "Bold"
        }
    }

    /// Light, dark and Increase Contrast values for each optional accent.
    /// Mono has no palette because it follows `.primary`, which already adapts.
    var palette: VyrraAdaptiveColor? {
        switch self {
        case .monochrome:
            nil
        case .forest:
            VyrraAdaptiveColor(light: 0x086338, dark: 0x0C9755, lightHighContrast: 0x086338, darkHighContrast: 0x0FBF6C)
        case .indigo:
            VyrraAdaptiveColor(light: 0x453DB0, dark: 0x7F79D1, lightHighContrast: 0x453DB0, darkHighContrast: 0xA4A0DE)
        case .ocean:
            VyrraAdaptiveColor(light: 0x0A579E, dark: 0x0F84F0, lightHighContrast: 0x0A579E, darkHighContrast: 0x5DACF5)
        case .plum:
            VyrraAdaptiveColor(light: 0x70338C, dark: 0xAA69C8, lightHighContrast: 0x70338C, darkHighContrast: 0xC496D9)
        case .ember:
            VyrraAdaptiveColor(light: 0xAB401F, dark: 0xDA5C35, lightHighContrast: 0x9A3A1C, darkHighContrast: 0xE69177)
        }
    }

    var color: Color {
        palette?.color ?? .primary
    }

    static func color(for rawValue: String) -> Color {
        (VyrraAccent(rawValue: rawValue) ?? .monochrome).color
    }
}

enum VyrraAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "vyrraAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func colorScheme(for rawValue: String) -> ColorScheme? {
        (VyrraAppearance(rawValue: rawValue) ?? .system).colorScheme
    }
}

private struct VyrraAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = VyrraAccent.monochrome.color
}

extension EnvironmentValues {
    var vyrraAccentColor: Color {
        get { self[VyrraAccentColorKey.self] }
        set { self[VyrraAccentColorKey.self] = newValue }
    }
}

/// A custom color with light, dark and Increase Contrast variants (sRGB hex).
///
/// Dark variants reach at least 4.5:1 against #1C1C1E and 5.5:1 against black,
/// so they work as text on dark surfaces and under a black label on a fill.
/// Increase Contrast variants reach at least 7:1 against their background.
/// Values come from the 2026-10-08 design review (C1).
struct VyrraAdaptiveColor: Equatable {
    let light: UInt32
    let dark: UInt32
    let lightHighContrast: UInt32
    let darkHighContrast: UInt32

    func hex(for traits: UITraitCollection) -> UInt32 {
        let highContrast = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return highContrast ? darkHighContrast : dark
        }
        return highContrast ? lightHighContrast : light
    }

    var uiColor: UIColor {
        let palette = self
        return UIColor { traits in
            UIColor(vyrraHex: palette.hex(for: traits))
        }
    }

    var color: Color {
        Color(uiColor: uiColor)
    }
}

extension UIColor {
    convenience init(vyrraHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum VyrraTheme {
    static let successPalette = VyrraAdaptiveColor(light: 0x056E38, dark: 0x07984D, lightHighContrast: 0x056735, darkHighContrast: 0x09C062)
    static let warningPalette = VyrraAdaptiveColor(light: 0xA66912, dark: 0xBD7814, lightHighContrast: 0x7C4F0D, darkHighContrast: 0xE7941B)
    static let dangerPalette = VyrraAdaptiveColor(light: 0xBF2424, dark: 0xDF5555, lightHighContrast: 0xAC2020, darkHighContrast: 0xEA8D8D)

    static let success = successPalette.color
    static let warning = warningPalette.color
    static let danger = dangerPalette.color
    static let cornerRadius: CGFloat = 8

    static var pageBackground: Color {
        Color(.systemBackground)
    }

    static var quietFill: Color {
        Color(.secondarySystemBackground)
    }

    static var thinLine: Color {
        Color.primary.opacity(0.08)
    }
}

enum ProductIdentity {
    static let publicName = "Vyrra"
    static let bundleIdentifier = "com.runnerconcepts.vyrra"
}

enum VyrraExternalLinks {
    static let privacyPolicy = URL(string: "https://vyrra.ai/privacy")!
    static let supportPage = URL(string: "https://vyrra.ai/support")!
    static let supportEmail = URL(string: "mailto:support@vyrra.ai")!
}

struct VyrraTrustCard: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    var showsDivider = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.body.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24)

            Text("Private. Free. Forever.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, showsDivider ? 14 : 13)
        .padding(.horizontal, showsDivider ? 0 : 14)
        .background {
            if !showsDivider {
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct VyrraAccentPicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 10)], spacing: 10) {
            ForEach(VyrraAccent.allCases) { accent in
                let isSelected = selection == accent.rawValue

                Button {
                    selection = accent.rawValue
                    HapticManager.selected()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle()
                                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                                }

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    // Every swatch is dark in light mode and light in dark mode.
                                    .foregroundStyle(Color(.systemBackground))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(accent.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Text(accent.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                    .background(accent.color.opacity(isSelected ? 0.13 : 0.05), in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                            .stroke(isSelected ? accent.color.opacity(0.38) : VyrraTheme.thinLine, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accent.title) accent")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

struct VyrraAppearancePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Appearance", selection: $selection) {
            ForEach(VyrraAppearance.allCases) { appearance in
                Text(appearance.title)
                    .tag(appearance.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct VyrraPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var scale: CGFloat = 0.985
    var opacity: Double = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? opacity : 1)
            .animation(
                reduceMotion ? .linear(duration: 0) : .spring(response: 0.22, dampingFraction: 0.84),
                value: configuration.isPressed
            )
    }
}

struct VyrraPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VyrraTheme.quietFill, in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .stroke(VyrraTheme.thinLine, lineWidth: 1)
            )
    }
}

enum VyrraProfileImageStore {
    static let storageKey = "profileImageJPEGData"

    static func loadData() -> Data? {
        UserDefaults.standard.data(forKey: storageKey)
    }

    static func save(_ data: Data?) {
        if let data {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    static func normalizedJPEGData(from data: Data) -> Data? {
        guard let sourceImage = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 640
        let largestSide = max(sourceImage.size.width, sourceImage.size.height)
        let scale = largestSide > maxDimension ? maxDimension / largestSide : 1
        let targetSize = CGSize(
            width: max(1, sourceImage.size.width * scale),
            height: max(1, sourceImage.size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return renderedImage.jpegData(compressionQuality: 0.82)
    }
}

struct VyrraProfileAvatar: View {
    let imageData: Data?
    let initials: String
    var size: CGFloat = 72

    @Environment(\.vyrraAccentColor) private var accentColor

    var body: some View {
        ZStack {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(accentColor.opacity(0.12))

                Text(initials)
                    .font(.system(size: max(13, size * 0.32), weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct VyrraStatusPill: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct VyrraIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 34
    var iconSize: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color.primary.opacity(0.07), in: Circle())
        .accessibilityLabel(label)
    }
}

struct VyrraIndeterminateProgressRail: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let cycle = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.45) / 1.45
                let thumbWidth = max(width * 0.28, 54)
                let offset = (width + thumbWidth) * cycle - thumbWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(Color.primary.opacity(0.58))
                        .frame(width: thumbWidth)
                        .offset(x: offset)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
        .accessibilityLabel("Working")
    }
}

struct VyrraElapsedText: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(elapsedText(now: timeline.date))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func elapsedText(now: Date) -> String {
        guard let startedAt else { return "Starting" }

        let totalSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        guard totalSeconds >= 60 else { return "Elapsed \(totalSeconds)s" }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "Elapsed \(minutes)m \(seconds)s"
    }
}
