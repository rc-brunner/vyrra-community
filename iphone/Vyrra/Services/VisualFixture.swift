import Foundation

enum AppTab: Hashable {
    case speak
    case library
    case personalize
    case settings
}

enum VisualFixture: String {
    case firstRun = "first_run"
    case recordIdle = "record_idle"
    case recordRecording = "record_recording"
    case recordProcessing = "record_processing"
    case recordCopied = "record_copied"
    case recordEmptyTranscript = "record_empty_transcript"
    case recordPermissionDenied = "record_permission_denied"
    case recordModelDownload = "record_model_download"
    case recordOffline = "record_offline"
    case recordLowStorage = "record_low_storage"
    case historyEmpty = "history_empty"
    case historySingle = "history_single"
    case historyPopulated = "history_populated"
    case historyDetail = "history_detail"
    case dictionaryEmpty = "dictionary_empty"
    case dictionaryPopulated = "dictionary_populated"
    case snippetsEmpty = "snippets_empty"
    case snippetsPopulated = "snippets_populated"
    case personalize = "personalize"
    case style = "style"
    case profile = "profile"
    case settings = "settings"
    case settingsAcknowledgements = "settings_acknowledgements"

    static var current: VisualFixture? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-VyrraFixture"),
           arguments.indices.contains(index + 1) {
            return VisualFixture(rawValue: arguments[index + 1])
        }

        if let rawValue = ProcessInfo.processInfo.environment["VYRRA_FIXTURE"] {
            return VisualFixture(rawValue: rawValue)
        }

        return nil
        #else
        return nil
        #endif
    }

    var defaultTab: AppTab {
        switch self {
        case .historyEmpty, .historySingle, .historyPopulated, .historyDetail:
            .library
        case .dictionaryEmpty, .dictionaryPopulated, .snippetsEmpty, .snippetsPopulated, .personalize, .style:
            .personalize
        case .settings, .settingsAcknowledgements, .profile:
            .settings
        default:
            .speak
        }
    }

    var shouldShowReadiness: Bool {
        self == .firstRun
    }

    var recordPhase: RecordingPhase? {
        switch self {
        case .firstRun, .recordIdle:
            .idle
        case .recordRecording:
            .recording
        case .recordProcessing:
            .processing
        case .recordCopied:
            .copied
        case .recordEmptyTranscript:
            .emptyTranscript
        case .recordPermissionDenied:
            .microphoneDenied
        case .recordModelDownload:
            .modelDownloading(0.42)
        case .recordOffline:
            .offlineBeforeDownload
        case .recordLowStorage:
            .lowStorage
        default:
            nil
        }
    }

    var samplePolishedText: String {
        #if DEBUG
        "Move the launch checklist to Friday and send a concise status update before noon."
        #else
        ""
        #endif
    }

    static var sampleHistory: [HistoryDisplayRecord] {
        #if DEBUG
        [
            HistoryDisplayRecord(
                title: "Launch checklist update",
                polishedText: "Move the launch checklist to Friday and send a concise status update before noon.",
                rawText: "Um I think we should basically move the launch checklist into Friday and send a short update.",
                sectionName: "Launch",
                tagsText: "launch, follow-up",
                createdAt: Date(timeIntervalSince1970: 1_777_773_600),
                duration: 8.4,
                modelName: "large-v3-v20240930_626MB",
                polishingMode: PolishingMode.cleanUp.rawValue
            ),
            HistoryDisplayRecord(
                polishedText: "I like the idea, but I do not like the current onboarding copy.",
                rawText: "I like the idea, but I do not like the current onboarding copy.",
                sectionName: "Product",
                tagsText: "ux",
                createdAt: Date(timeIntervalSince1970: 1_777_770_000),
                duration: 4.9,
                modelName: "large-v3-v20240930_626MB",
                polishingMode: PolishingMode.cleanUp.rawValue
            )
        ]
        #else
        []
        #endif
    }

    static var sampleSingleHistory: [HistoryDisplayRecord] {
        #if DEBUG
        [
            HistoryDisplayRecord(
                polishedText: "Hello.",
                rawText: "Hello.",
                createdAt: Date(timeIntervalSince1970: 1_777_830_600),
                duration: 2.6,
                modelName: "large-v3-v20240930_626MB",
                polishingMode: PolishingMode.cleanUp.rawValue
            )
        ]
        #else
        []
        #endif
    }

    static var sampleVocabulary: [VocabularyDisplayEntry] {
        #if DEBUG
        [
            VocabularyDisplayEntry(
                spokenForm: "vyrra",
                preferredText: ProductIdentity.publicName,
                category: .company,
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 1_777_773_600)
            ),
            VocabularyDisplayEntry(
                spokenForm: "btw",
                preferredText: "by the way",
                category: .custom,
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 1_777_770_000)
            ),
            VocabularyDisplayEntry(
                spokenForm: "asr",
                preferredText: "ASR",
                category: .acronym,
                isEnabled: false,
                createdAt: Date(timeIntervalSince1970: 1_777_766_400)
            )
        ]
        #else
        []
        #endif
    }

    static var sampleSnippets: [SnippetDisplayEntry] {
        #if DEBUG
        [
            SnippetDisplayEntry(
                trigger: "my email address",
                body: "hello@example.com",
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 1_777_773_600)
            ),
            SnippetDisplayEntry(
                trigger: "launch status",
                body: "Quick update: the launch checklist is moving, and I will send the next status note before noon.",
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 1_777_770_000)
            )
        ]
        #else
        []
        #endif
    }
}

struct HistoryDisplayRecord: Identifiable, Hashable {
    let id: UUID
    let title: String?
    let polishedText: String
    let rawText: String
    let sectionName: String?
    let tagsText: String?
    let createdAt: Date
    let duration: TimeInterval
    let modelName: String
    let polishingMode: String

    init(
        id: UUID = UUID(),
        title: String? = nil,
        polishedText: String,
        rawText: String,
        sectionName: String? = nil,
        tagsText: String? = nil,
        createdAt: Date,
        duration: TimeInterval,
        modelName: String,
        polishingMode: String
    ) {
        self.id = id
        self.title = title
        self.polishedText = polishedText
        self.rawText = rawText
        self.sectionName = sectionName
        self.tagsText = tagsText
        self.createdAt = createdAt
        self.duration = duration
        self.modelName = modelName
        self.polishingMode = polishingMode
    }

    init(record: TranscriptionRecord) {
        self.id = record.id
        self.title = record.title
        self.polishedText = record.polishedText
        self.rawText = record.rawText
        self.sectionName = record.sectionName
        self.tagsText = record.tagsText
        self.createdAt = record.createdAt
        self.duration = record.duration
        self.modelName = record.modelName
        self.polishingMode = record.polishingMode
    }

    var displayTitle: String {
        HistoryRecordFormatter.displayTitle(title: title, polishedText: polishedText)
    }

    var displaySectionName: String {
        HistoryRecordFormatter.displaySectionName(sectionName)
    }

    var estimatedStorageBytes: Int {
        HistoryStorageEstimate.bytes(
            rawText: rawText,
            polishedText: polishedText,
            title: title,
            sectionName: sectionName,
            tagsText: tagsText
        )
    }
}
