import Foundation
import SwiftData

@Model
final class TranscriptionRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var rawText: String
    var polishedText: String
    var title: String?
    var sectionName: String?
    var tagsText: String?
    var duration: TimeInterval
    var modelName: String
    var polishingMode: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        polishedText: String,
        title: String? = nil,
        sectionName: String? = nil,
        tagsText: String? = nil,
        duration: TimeInterval,
        modelName: String,
        polishingMode: PolishingMode
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.polishedText = polishedText
        self.title = title
        self.sectionName = sectionName
        self.tagsText = tagsText
        self.duration = duration
        self.modelName = modelName
        self.polishingMode = polishingMode.rawValue
    }
}

enum HistoryRecordFormatter {
    static let defaultSectionName = "Inbox"

    static func displayTitle(title: String?, polishedText: String) -> String {
        let trimmedTitle = normalizedOptional(title)
        if let trimmedTitle {
            return trimmedTitle
        }

        let firstMeaningfulLine = polishedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        let normalizedText = firstMeaningfulLine
            .replacingOccurrences(
                of: "^(?:[-•*–—]|[0-9]+[.)])\\s+",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return "Untitled Transcript" }
        guard normalizedText.count > 62 else { return normalizedText }
        return "\(normalizedText.prefix(59))..."
    }

    static func displaySectionName(_ sectionName: String?) -> String {
        normalizedOptional(sectionName) ?? defaultSectionName
    }

    static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum HistoryTagFormatter {
    static func normalizedTags(from text: String?) -> [String] {
        let rawText = text ?? ""
        var seen = Set<String>()

        return rawText
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .flatMap { component in
                component
                    .split(separator: " ")
                    .map(String.init)
            }
            .compactMap { rawTag in
                let tag = rawTag
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                guard !tag.isEmpty else { return nil }

                let normalizedKey = tag.lowercased()
                guard !seen.contains(normalizedKey) else { return nil }
                seen.insert(normalizedKey)
                return tag
            }
    }

    static func storageText(from text: String?) -> String? {
        let tags = normalizedTags(from: text)
        guard !tags.isEmpty else { return nil }
        return tags.joined(separator: ", ")
    }

    static func displayText(from text: String?) -> String? {
        let tags = normalizedTags(from: text)
        guard !tags.isEmpty else { return nil }
        return tags.map { "#\($0)" }.joined(separator: " ")
    }
}

enum HistoryStorageEstimate {
    static func bytes(
        rawText: String,
        polishedText: String,
        title: String?,
        sectionName: String?,
        tagsText: String?
    ) -> Int {
        let transcriptBytes = rawText.utf8.count + polishedText.utf8.count
        let metadataBytes = (title?.utf8.count ?? 0)
            + (sectionName?.utf8.count ?? 0)
            + (tagsText?.utf8.count ?? 0)
        return transcriptBytes + metadataBytes
    }

    static func formatted(bytes: Int) -> String {
        guard bytes > 0 else { return "0 KB" }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

enum HistoryExportFormatter {
    static func plainText(record: HistoryDisplayRecord) -> String {
        let lines = [
            record.displayTitle,
            record.createdAt.formatted(date: .complete, time: .shortened),
            record.displaySectionName,
            HistoryTagFormatter.displayText(from: record.tagsText),
            "",
            record.polishedText
        ]

        return lines.compactMap(\.self).joined(separator: "\n")
    }

    static func markdown(record: HistoryDisplayRecord) -> String {
        var lines = [
            "# \(record.displayTitle)",
            "",
            "- Created: \(record.createdAt.formatted(date: .complete, time: .shortened))",
            "- Folder: \(record.displaySectionName)"
        ]

        if let tags = HistoryTagFormatter.displayText(from: record.tagsText) {
            lines.append("- Tags: \(tags)")
        }

        lines += [
            "",
            record.polishedText
        ]

        return lines.joined(separator: "\n")
    }

    static func fileBaseName(for record: HistoryDisplayRecord) -> String {
        let title = record.displayTitle
            .replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = "Vyrra Transcript"
        let base = title.isEmpty ? fallback : title
        return String(base.prefix(48))
    }
}

enum HistoryExportWriter {
    static func exportURLs(for record: HistoryDisplayRecord) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyrraExports", isDirectory: true)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = HistoryExportFormatter.fileBaseName(for: record)
        let textURL = directory.appendingPathComponent(baseName).appendingPathExtension("txt")
        let markdownURL = directory.appendingPathComponent(baseName).appendingPathExtension("md")

        try HistoryExportFormatter
            .plainText(record: record)
            .write(to: textURL, atomically: true, encoding: .utf8)

        try HistoryExportFormatter
            .markdown(record: record)
            .write(to: markdownURL, atomically: true, encoding: .utf8)

        return [textURL, markdownURL]
    }
}

struct VyrraExportPayload: Codable, Equatable {
    let schemaVersion: Int
    let app: VyrraExportAppInfo
    let exportedAt: Date
    let records: [VyrraExportRecord]
    let folders: [VyrraExportFolder]
    let vocabulary: [VyrraExportVocabularyEntry]
    let snippets: [VyrraExportSnippetEntry]
    let selectedPreferences: VyrraExportPreferences

    static func make(
        records: [TranscriptionRecord],
        folders: [NoteFolder],
        vocabulary: [VocabularyEntry],
        snippets: [SnippetEntry],
        modelManager: ModelManager,
        exportedAt: Date = Date(),
        appVersion: String? = nil,
        buildNumber: String? = nil
    ) -> VyrraExportPayload {
        let bundle = Bundle.main
        let resolvedVersion = appVersion
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
        let resolvedBuild = buildNumber
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"

        return VyrraExportPayload(
            schemaVersion: 1,
            app: VyrraExportAppInfo(
                name: ProductIdentity.publicName,
                bundleIdentifier: ProductIdentity.bundleIdentifier,
                version: resolvedVersion,
                build: resolvedBuild
            ),
            exportedAt: exportedAt,
            records: records.map(VyrraExportRecord.init(record:)),
            folders: folders.map(VyrraExportFolder.init(folder:)),
            vocabulary: vocabulary.map(VyrraExportVocabularyEntry.init(entry:)),
            snippets: snippets.map(VyrraExportSnippetEntry.init(entry:)),
            selectedPreferences: VyrraExportPreferences(modelManager: modelManager)
        )
    }
}

struct VyrraExportAppInfo: Codable, Equatable {
    let name: String
    let bundleIdentifier: String
    let version: String
    let build: String
}

struct VyrraExportRecord: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let rawText: String
    let polishedText: String
    let title: String?
    let sectionName: String?
    let tagsText: String?
    let duration: TimeInterval
    let modelName: String
    let polishingMode: String

    init(record: TranscriptionRecord) {
        id = record.id
        createdAt = record.createdAt
        rawText = record.rawText
        polishedText = record.polishedText
        title = record.title
        sectionName = record.sectionName
        tagsText = record.tagsText
        duration = record.duration
        modelName = record.modelName
        polishingMode = record.polishingMode
    }
}

struct VyrraExportFolder: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let name: String

    init(folder: NoteFolder) {
        id = folder.id
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
        name = folder.name
    }
}

struct VyrraExportVocabularyEntry: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let spokenForm: String
    let preferredText: String
    let category: String
    let isEnabled: Bool

    init(entry: VocabularyEntry) {
        id = entry.id
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        spokenForm = entry.spokenForm
        preferredText = entry.preferredText
        category = entry.categoryRawValue
        isEnabled = entry.isEnabled
    }
}

struct VyrraExportSnippetEntry: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let trigger: String
    let body: String
    let isEnabled: Bool

    init(entry: SnippetEntry) {
        id = entry.id
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        trigger = entry.trigger
        body = entry.body
        isEnabled = entry.isEnabled
    }
}

struct VyrraExportPreferences: Codable, Equatable {
    let selectedModel: String
    let selectedModelTitle: String
    let selectedLanguageCode: String
    let selectedLanguageTitle: String
    let polishingMode: String
    let savesHistory: Bool
    let waveformSensitivity: Double
    let waveformMotion: String?
    let hapticsEnabled: Bool

    init(modelManager: ModelManager) {
        selectedModel = modelManager.selectedModelName
        selectedModelTitle = modelManager.selectedModel.title
        selectedLanguageCode = modelManager.selectedLanguageCode
        selectedLanguageTitle = SpeechLanguage.title(for: modelManager.selectedLanguageCode)
        polishingMode = modelManager.polishingMode.rawValue
        savesHistory = modelManager.savesHistory
        waveformSensitivity = modelManager.waveformSensitivity
        waveformMotion = modelManager.waveformMotion.rawValue
        hapticsEnabled = modelManager.hapticsEnabled
    }
}

enum VyrraExportWriter {
    static func exportURL(for payload: VyrraExportPayload) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyrraDataExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory
            .appendingPathComponent("Vyrra Data Export \(fileStamp(for: payload.exportedAt))")
            .appendingPathExtension("json")
        let data = try encodedData(for: payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return fileURL
    }

    static func encodedData(for payload: VyrraExportPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private static func fileStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

enum HistoryFolderRecommender {
    static func recommendedFolderNames(
        title: String,
        text: String,
        folders: [String],
        currentFolder: String?,
        limit: Int = 3
    ) -> [String] {
        let current = HistoryRecordFormatter.displaySectionName(currentFolder)
        let titleText = title.lowercased()
        let bodyText = text.lowercased()
        let uniqueFolders = folders.reduce(into: [String: String]()) { result, folder in
            guard let name = HistoryRecordFormatter.normalizedOptional(folder),
                  name != HistoryRecordFormatter.defaultSectionName
            else { return }
            result[name.lowercased()] = name
        }

        let scoredFolders = uniqueFolders.values.compactMap { folder -> (name: String, score: Int)? in
            guard folder.caseInsensitiveCompare(current) != .orderedSame else { return nil }

            let needle = folder.lowercased()
            var score = 0
            if titleText.contains(needle) { score += 5 }
            if bodyText.contains(needle) { score += 3 }

            let folderWords = needle.split(separator: " ").map(String.init)
            if !folderWords.isEmpty && folderWords.allSatisfy({ bodyText.contains($0) }) {
                score += 1
            }

            return score > 0 ? (folder, score) : nil
        }

        return scoredFolders
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.name)
    }
}
