import Foundation
import SwiftData

@Model
final class NoteFolder {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var name: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
    }
}

@Model
final class VocabularyEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var spokenForm: String
    var preferredText: String
    var categoryRawValue: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        spokenForm: String,
        preferredText: String,
        category: VocabularyCategory = .custom,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.spokenForm = spokenForm
        self.preferredText = preferredText
        self.categoryRawValue = category.rawValue
        self.isEnabled = isEnabled
    }

    var category: VocabularyCategory {
        get { VocabularyCategory(rawValue: categoryRawValue) ?? .custom }
        set { categoryRawValue = newValue.rawValue }
    }
}

enum VocabularyCategory: String, CaseIterable, Identifiable, Codable {
    case name
    case acronym
    case company
    case technical
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            "Name"
        case .acronym:
            "Acronym"
        case .company:
            "Company"
        case .technical:
            "Technical"
        case .custom:
            "Custom"
        }
    }
}

@Model
final class SnippetEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var trigger: String
    var body: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        trigger: String,
        body: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trigger = trigger
        self.body = body
        self.isEnabled = isEnabled
    }
}

struct VocabularyReplacement: Hashable {
    let spokenForm: String
    let preferredText: String
    let isEnabled: Bool

    init(spokenForm: String, preferredText: String, isEnabled: Bool = true) {
        self.spokenForm = spokenForm
        self.preferredText = preferredText
        self.isEnabled = isEnabled
    }

    init(entry: VocabularyEntry) {
        self.init(
            spokenForm: entry.spokenForm,
            preferredText: entry.preferredText,
            isEnabled: entry.isEnabled
        )
    }
}

struct SnippetExpansion: Hashable {
    let trigger: String
    let body: String
    let isEnabled: Bool

    init(trigger: String, body: String, isEnabled: Bool = true) {
        self.trigger = trigger
        self.body = body
        self.isEnabled = isEnabled
    }

    init(entry: SnippetEntry) {
        self.init(trigger: entry.trigger, body: entry.body, isEnabled: entry.isEnabled)
    }
}

struct VocabularyDisplayEntry: Identifiable, Hashable {
    let id: UUID
    let spokenForm: String
    let preferredText: String
    let category: VocabularyCategory
    let isEnabled: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        spokenForm: String,
        preferredText: String,
        category: VocabularyCategory,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.spokenForm = spokenForm
        self.preferredText = preferredText
        self.category = category
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    init(entry: VocabularyEntry) {
        self.id = entry.id
        self.spokenForm = entry.spokenForm
        self.preferredText = entry.preferredText
        self.category = entry.category
        self.isEnabled = entry.isEnabled
        self.createdAt = entry.createdAt
    }
}

struct SnippetDisplayEntry: Identifiable, Hashable {
    let id: UUID
    let trigger: String
    let body: String
    let isEnabled: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        trigger: String,
        body: String,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.trigger = trigger
        self.body = body
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    init(entry: SnippetEntry) {
        self.id = entry.id
        self.trigger = entry.trigger
        self.body = entry.body
        self.isEnabled = entry.isEnabled
        self.createdAt = entry.createdAt
    }
}

enum PersonalizationFormatter {
    static func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedSnippetTrigger(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))

        return trimmed.lowercased()
    }
}

enum PersonalizationEngine {
    static func applyVocabulary(_ entries: [VocabularyReplacement], to text: String) -> String {
        var output = text
        let enabledEntries = entries
            .filter { $0.isEnabled }
            .compactMap { entry -> VocabularyReplacement? in
                guard PersonalizationFormatter.normalizedOptional(entry.spokenForm) != nil,
                      PersonalizationFormatter.normalizedOptional(entry.preferredText) != nil
                else { return nil }
                return entry
            }
            .sorted { $0.spokenForm.count > $1.spokenForm.count }

        for entry in enabledEntries {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spokenForm)
            let pattern = "(?i)(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])"
            output = output.replacingOccurrences(
                of: pattern,
                with: entry.preferredText,
                options: [.regularExpression]
            )
        }

        return output
    }

    static func exactSnippetExpansion(_ entries: [SnippetExpansion], for text: String) -> String? {
        let normalizedText = PersonalizationFormatter.normalizedSnippetTrigger(text)
        guard !normalizedText.isEmpty else { return nil }

        return entries
            .filter { $0.isEnabled }
            .first { entry in
                PersonalizationFormatter.normalizedSnippetTrigger(entry.trigger) == normalizedText
                    && PersonalizationFormatter.normalizedOptional(entry.body) != nil
            }
            .flatMap { PersonalizationFormatter.normalizedOptional($0.body) }
    }
}
