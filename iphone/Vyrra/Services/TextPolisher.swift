import Foundation

enum PolishingMode: String, CaseIterable, Identifiable, Codable {
    case raw
    case cleanUp
    case casual
    case notes
    case email
    case bullets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .raw:
            "Raw"
        case .cleanUp:
            "Clean Up"
        case .casual:
            "Message"
        case .notes:
            "Notes"
        case .email:
            "Email"
        case .bullets:
            "Bullets"
        }
    }
}

struct TextPolisher {
    var mode: PolishingMode = .cleanUp
    var vocabulary: [VocabularyReplacement] = []
    var snippets: [SnippetExpansion] = []

    func polish(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if mode == .raw {
            text = normalizeWhitespace(in: text)
            text = PersonalizationEngine.applyVocabulary(vocabulary, to: text)
            return PersonalizationEngine.exactSnippetExpansion(snippets, for: text) ?? text
        }

        text = removeFillers(from: text)
        text = removeRepeatedWords(from: text)
        text = normalizeSpokenSymbols(in: text)
        text = normalizeWhitespace(in: text)
        text = fixCapitalization(in: text)
        text = restoreSymbolPlaceholders(in: text)
        text = PersonalizationEngine.applyVocabulary(vocabulary, to: text)

        if let snippetBody = PersonalizationEngine.exactSnippetExpansion(snippets, for: text) {
            return snippetBody
        }

        switch mode {
        case .cleanUp, .casual:
            return text
        case .raw:
            return text
        case .notes:
            return notesFormatted(text)
        case .email:
            return emailFormatted(text)
        case .bullets:
            return bulletFormatted(text)
        }
    }

    private func removeFillers(from text: String) -> String {
        var output = text

        let simplePatterns = [
            "\\b(um+|uh+|er+)\\b[, ]*",
            "\\byou know\\b[, ]*",
            "\\b(sort of|kind of)\\b[, ]*",
            "\\b(basically|actually)\\b[, ]*"
        ]

        for pattern in simplePatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        output = output.replacingOccurrences(
            of: "(^|[.!?]\\s+|,\\s+)like\\b[, ]*",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )

        return output
    }

    private func removeRepeatedWords(from text: String) -> String {
        text.replacingOccurrences(
            of: "\\b([A-Za-z']+)(\\s+\\1\\b)+",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func normalizeWhitespace(in text: String) -> String {
        let output = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,;:!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([,;:!?])([^\\s])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([”\\)])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([“\\(])\\s+", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+\\)", with: ")", options: .regularExpression)
            .replacingOccurrences(of: "\\(\\s+", with: "(", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return output
    }

    private func normalizeSpokenSymbols(in text: String) -> String {
        var output = text

        let phraseReplacements = [
            ("\\bopen quote\\b\\s*", "“"),
            ("\\bclose quote\\b", "”"),
            ("\\bopen parenthesis\\b", "("),
            ("\\bclose parenthesis\\b", ")"),
            ("\\bleft parenthesis\\b", "("),
            ("\\bright parenthesis\\b", ")"),
            ("\\bat sign\\b", "__VYRRA_AT__"),
            ("\\bhash tag\\b", "__VYRRA_HASH__"),
            ("\\bhashtag\\b", "__VYRRA_HASH__"),
            ("\\bdollar sign\\b", "$"),
            ("\\bpercent sign\\b", "%"),
            ("\\bampersand\\b", "__VYRRA_AMP__"),
            ("\\bforward slash\\b", "__VYRRA_SLASH__"),
            ("\\bslash\\b", "__VYRRA_SLASH__"),
            ("\\bdot\\b", "__VYRRA_DOT__"),
            ("\\bcolon\\b", ":"),
            ("\\bsemicolon\\b", ";"),
            ("\\bcomma\\b", ","),
            ("\\bquestion mark\\b", "?"),
            ("\\bexclamation point\\b", "!"),
            ("\\bexclamation mark\\b", "!")
        ]

        for (pattern, replacement) in phraseReplacements {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return output
    }

    private func restoreSymbolPlaceholders(in text: String) -> String {
        text
            .replacingOccurrences(of: "\\s*__VYRRA_DOT__\\s*", with: ".", options: .regularExpression)
            .replacingOccurrences(of: "\\s*__VYRRA_SLASH__\\s*", with: "/", options: .regularExpression)
            .replacingOccurrences(of: "\\s*__VYRRA_AT__\\s*", with: "@", options: .regularExpression)
            .replacingOccurrences(of: "\\s*__VYRRA_HASH__\\s*", with: "#", options: .regularExpression)
            .replacingOccurrences(of: "\\s*__VYRRA_AMP__\\s*", with: "&", options: .regularExpression)
    }

    private func fixCapitalization(in text: String) -> String {
        var output = text.replacingOccurrences(
            of: "\\bi\\b",
            with: "I",
            options: [.regularExpression, .caseInsensitive]
        )

        var result = ""
        var shouldCapitalize = true

        for character in output {
            if shouldCapitalize, character.isLetter {
                result.append(contentsOf: character.uppercased())
                shouldCapitalize = false
            } else {
                result.append(character)
            }

            if ".!?".contains(character) {
                shouldCapitalize = true
            }
        }

        output = result
        if !output.hasSuffix(".") && !output.hasSuffix("!") && !output.hasSuffix("?") {
            output += "."
        }

        return output
    }

    private func emailFormatted(_ text: String) -> String {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("hi ") || lowercased.hasPrefix("hello ") {
            return text
        }
        return text
    }

    private func bulletFormatted(_ text: String) -> String {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else { return text }
        return sentences.map { "• \($0)" }.joined(separator: "\n")
    }

    private func notesFormatted(_ text: String) -> String {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count > 1 else { return text }
        return sentences.map { "\($0)." }.joined(separator: "\n\n")
    }
}
