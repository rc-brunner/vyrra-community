import Foundation

enum SpeechLanguage: String, CaseIterable, Identifiable {
    case auto
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    case hindi = "hi"
    case arabic = "ar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "Auto Detect"
        case .english:
            "English"
        case .spanish:
            "Spanish"
        case .french:
            "French"
        case .german:
            "German"
        case .italian:
            "Italian"
        case .portuguese:
            "Portuguese"
        case .dutch:
            "Dutch"
        case .japanese:
            "Japanese"
        case .korean:
            "Korean"
        case .chinese:
            "Chinese"
        case .hindi:
            "Hindi"
        case .arabic:
            "Arabic"
        }
    }

    var shortTitle: String {
        self == .auto ? "Auto" : title
    }

    var validationLabel: String {
        switch self {
        case .auto, .english, .spanish, .french, .german:
            "Core test set"
        default:
            "Candidate"
        }
    }

    static func title(for code: String, short: Bool = false) -> String {
        let language = SpeechLanguage(rawValue: code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .auto
        return short ? language.shortTitle : language.title
    }

    static func preferredDefault(from preferredLanguages: [String]) -> SpeechLanguage {
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if let language = SpeechLanguage(rawValue: code), language != .auto {
                return language
            }
        }
        return .auto
    }
}

enum SpeechModel: String, CaseIterable, Identifiable {
    case recommendedLarge = "large-v3-v20240930_626MB"
    case debugTiny = "tiny"
    case liteSmall = "small"

    static var allCases: [SpeechModel] {
        [.debugTiny, .liteSmall, .recommendedLarge]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommendedLarge:
            "Whisper Large v3"
        case .debugTiny:
            "Whisper Tiny"
        case .liteSmall:
            "Whisper Small"
        }
    }

    var detail: String {
        switch self {
        case .recommendedLarge:
            "20240930 · 4-bit compressed"
        case .debugTiny:
            "Fastest · lower accuracy"
        case .liteSmall:
            "Speed and accuracy"
        }
    }

    var sourceVariant: String { "openai_whisper-\(rawValue)" }

    var sourceURL: URL {
        URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/\(sourceVariant)")!
    }

    var storageLabel: String {
        switch self {
        case .recommendedLarge:
            "626 MB"
        case .debugTiny:
            "~75 MB"
        case .liteSmall:
            "~466 MB"
        }
    }

    var downloadActionTitle: String {
        "Download \(storageLabel)"
    }

    var downloadExpectation: String {
        switch self {
        case .recommendedLarge:
            "One-time download. Preparing can take about a minute."
        case .debugTiny:
            "Small download. Quick to prepare."
        case .liteSmall:
            "One-time download. Preparing can take under a minute."
        }
    }

    var warmupExpectation: String {
        switch self {
        case .recommendedLarge:
            "Preparing can take about a minute."
        case .debugTiny:
            "Preparing is usually quick."
        case .liteSmall:
            "Preparing can take under a minute."
        }
    }

    var activePreparationGuidance: String {
        "Keep Vyrra open. Usually 1–2 min."
    }

    var estimatedStorageBytes: Int64 {
        switch self {
        case .recommendedLarge:
            626 * 1_024 * 1_024
        case .debugTiny:
            75 * 1_024 * 1_024
        case .liteSmall:
            466 * 1_024 * 1_024
        }
    }
}

enum WaveformMotion: String, CaseIterable, Identifiable {
    case calm
    case flow
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm:
            "Calm"
        case .flow:
            "Flow"
        case .detail:
            "Detail"
        }
    }

    var barCount: Int {
        switch self {
        case .calm:
            32
        case .flow:
            44
        case .detail:
            56
        }
    }

    var speedMultiplier: Double {
        switch self {
        case .calm:
            0.72
        case .flow:
            1
        case .detail:
            1.22
        }
    }

    var energyMultiplier: Double {
        switch self {
        case .calm:
            0.78
        case .flow:
            1
        case .detail:
            1.12
        }
    }
}

final class ModelManager: ObservableObject {
    @Published var selectedModel: SpeechModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
        }
    }

    @Published var selectedLanguageCode: String {
        didSet {
            defaults.set(selectedLanguageCode, forKey: Self.selectedLanguageCodeKey)
        }
    }

    @Published var polishingMode: PolishingMode {
        didSet {
            defaults.set(polishingMode.rawValue, forKey: Self.polishingModeKey)
        }
    }

    @Published var waveformSensitivity: Double {
        didSet {
            defaults.set(waveformSensitivity, forKey: Self.waveformSensitivityKey)
        }
    }

    @Published var waveformMotion: WaveformMotion {
        didSet {
            defaults.set(waveformMotion.rawValue, forKey: Self.waveformMotionKey)
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Self.hapticsEnabledKey)
            syncKeyboardHaptics()
        }
    }

    @Published var savesHistory: Bool {
        didSet {
            defaults.set(savesHistory, forKey: Self.savesHistoryKey)
        }
    }

    private let defaults: UserDefaults

    private static let selectedModelKey = "selectedModel"
    private static let selectedLanguageCodeKey = "selectedLanguageCode"
    private static let polishingModeKey = "polishingMode"
    private static let waveformSensitivityKey = "waveformSensitivity"
    private static let waveformMotionKey = "waveformMotion"
    private static let hapticsEnabledKey = "hapticsEnabled"
    private static let savesHistoryKey = "savesHistory"

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults

        selectedModel = defaults
            .string(forKey: Self.selectedModelKey)
            .flatMap(SpeechModel.init(rawValue:)) ?? .recommendedLarge

        selectedLanguageCode = defaults
            .string(forKey: Self.selectedLanguageCodeKey)
            .flatMap { SpeechLanguage(rawValue: $0) == nil ? nil : $0 }
            ?? SpeechLanguage.preferredDefault(from: preferredLanguages).rawValue

        polishingMode = defaults
            .string(forKey: Self.polishingModeKey)
            .flatMap(PolishingMode.init(rawValue:)) ?? .cleanUp

        let storedWaveformSensitivity = defaults.object(forKey: Self.waveformSensitivityKey) as? Double
        waveformSensitivity = storedWaveformSensitivity ?? 1.0

        waveformMotion = defaults
            .string(forKey: Self.waveformMotionKey)
            .flatMap(WaveformMotion.init(rawValue:)) ?? .flow

        let storedValue = defaults.object(forKey: Self.hapticsEnabledKey) as? Bool
        hapticsEnabled = storedValue ?? true

        let storedHistoryValue = defaults.object(forKey: Self.savesHistoryKey) as? Bool
        savesHistory = storedHistoryValue ?? true
        syncKeyboardHaptics()
    }

    private func syncKeyboardHaptics() {
        guard defaults === UserDefaults.standard else { return }
        var preferences = (try? KeyboardSharedStore.readAppearance()) ?? KeyboardAppearancePreferences()
        preferences.hapticsEnabled = hapticsEnabled
        try? KeyboardSharedStore.writeAppearance(preferences)
    }

    var selectedModelName: String {
        selectedModel.rawValue
    }

    var waveformSensitivityLabel: String {
        switch waveformSensitivity {
        case ..<0.85:
            "Calm"
        case 1.2...:
            "Responsive"
        default:
            "Standard"
        }
    }
}
