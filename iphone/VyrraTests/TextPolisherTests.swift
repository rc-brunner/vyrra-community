import XCTest
@testable import Vyrra

final class TextPolisherTests: XCTestCase {
    func testPolishedOutputLegitimatelyDiffersFromOriginalWhenCleanupIsNeeded() {
        let original = "um I I think this this works ,okay"
        let polished = TextPolisher().polish(original)

        XCTAssertNotEqual(polished, original)
        XCTAssertEqual(polished, "I think this works, okay.")
    }

    func testRawModePreservesSpeakerArtifactsWhileNormalizingSpacing() {
        let original = " um   i i think this ,works "
        let polished = TextPolisher(mode: .raw).polish(original)

        XCTAssertNotEqual(polished, original)
        XCTAssertEqual(polished, "um i i think this, works")
    }

    func testPolishPreservesFactsNumbersAndNamesWithoutInventingContent() {
        let polished = TextPolisher().polish("uh schedule the model review for friday at 3 pm with alex")

        XCTAssertEqual(polished, "Schedule the model review for friday at 3 pm with alex.")
        XCTAssertTrue(polished.contains("friday"))
        XCTAssertTrue(polished.contains("3 pm"))
        XCTAssertTrue(polished.contains("alex"))
        XCTAssertFalse(polished.localizedCaseInsensitiveContains("monday"))
    }

    func testEmailModeDoesNotInventGreetingOrSignature() {
        let polished = TextPolisher(mode: .email).polish("send the agenda to maya by noon")

        XCTAssertEqual(polished, "Send the agenda to maya by noon.")
        XCTAssertFalse(polished.localizedCaseInsensitiveContains("hi "))
        XCTAssertFalse(polished.localizedCaseInsensitiveContains("thanks"))
    }

    func testStyleModesMayChangeShapeWithoutChangingCoreSentenceContent() {
        let original = "first item. second item."

        XCTAssertEqual(TextPolisher(mode: .cleanUp).polish(original), "First item. Second item.")
        XCTAssertEqual(TextPolisher(mode: .notes).polish(original), "First item.\n\nSecond item.")
        XCTAssertEqual(TextPolisher(mode: .bullets).polish(original), "• First item\n• Second item")
    }

    func testVocabularyIsUserApprovedDivergenceFromOriginal() {
        let original = "runner concepts ships asr for ios"
        let polished = TextPolisher(
            vocabulary: [
                VocabularyReplacement(spokenForm: "runner concepts", preferredText: "Runner Concepts"),
                VocabularyReplacement(spokenForm: "asr", preferredText: "ASR"),
                VocabularyReplacement(spokenForm: "ios", preferredText: "iOS")
            ]
        )
        .polish(original)

        XCTAssertNotEqual(polished, original)
        XCTAssertEqual(polished, "Runner Concepts ships ASR for iOS.")
    }

    func testSnippetExpansionIsUserApprovedReplacementOfExactOriginal() {
        let original = "my email address"
        let polished = TextPolisher(
            snippets: [
                SnippetExpansion(trigger: "my email address", body: "brunner@runnertechnologies.com")
            ]
        )
        .polish(original)

        XCTAssertNotEqual(polished, original)
        XCTAssertEqual(polished, "brunner@runnertechnologies.com")
    }

    func testRemovesSimpleFillers() {
        let result = TextPolisher().polish("um I think you know this is basically useful")
        XCTAssertEqual(result, "I think this is useful.")
    }

    func testPreservesMeaningfulLike() {
        let result = TextPolisher().polish("I like pizza and I like pasta")
        XCTAssertEqual(result, "I like pizza and I like pasta.")
    }

    func testRemovesFillerLikeAtSentenceStart() {
        let result = TextPolisher().polish("like I think this works")
        XCTAssertEqual(result, "I think this works.")
    }

    func testRemovesRepeatedWords() {
        let result = TextPolisher().polish("I I I think this this works")
        XCTAssertEqual(result, "I think this works.")
    }

    func testNormalizesWhitespaceAndPunctuation() {
        let result = TextPolisher().polish("hello   world ,this works")
        XCTAssertEqual(result, "Hello world, this works.")
    }

    func testEmptyInputReturnsEmptyOutput() {
        let result = TextPolisher().polish("   ")
        XCTAssertEqual(result, "")
    }

    func testBulletModeFormatsSentences() {
        let result = TextPolisher(mode: .bullets).polish("first thing. second thing.")
        XCTAssertEqual(result, "• First thing\n• Second thing")
    }

    func testSpokenQuotesAndSymbolsAreFormatted() {
        let result = TextPolisher().polish("open quote ship it close quote slash support at sign example dot com")
        XCTAssertEqual(result, "“Ship it”/support@example.com.")
    }

    func testSpokenPunctuationAndParenthesesAreFormatted() {
        let result = TextPolisher().polish("launch checklist colon open parenthesis friday close parenthesis question mark")
        XCTAssertEqual(result, "Launch checklist: (friday)?")
    }

    func testRawModeKeepsFillerText() {
        let result = TextPolisher(mode: .raw).polish("um this is raw")
        XCTAssertEqual(result, "um this is raw")
    }

    func testNotesModeSplitsSentencesIntoParagraphs() {
        let result = TextPolisher(mode: .notes).polish("first thought. second thought.")
        XCTAssertEqual(result, "First thought.\n\nSecond thought.")
    }

    func testVocabularyReplacementUsesWordBoundaries() {
        let result = TextPolisher(
            vocabulary: [
                VocabularyReplacement(spokenForm: "runner concepts", preferredText: "Runner Concepts")
            ]
        )
        .polish("runner concepts is ready but prerunner concepts should not change")

        XCTAssertEqual(result, "Runner Concepts is ready but prerunner concepts should not change.")
    }

    func testDisabledVocabularyReplacementIsIgnored() {
        let result = TextPolisher(
            vocabulary: [
                VocabularyReplacement(spokenForm: "asr", preferredText: "ASR", isEnabled: false)
            ]
        )
        .polish("asr should stay lowercase")

        XCTAssertEqual(result, "Asr should stay lowercase.")
    }

    func testSnippetExpandsOnlyExactTrigger() {
        let polisher = TextPolisher(
            snippets: [
                SnippetExpansion(trigger: "my email address", body: "brunner@runnertechnologies.com")
            ]
        )

        XCTAssertEqual(polisher.polish("my email address"), "brunner@runnertechnologies.com")
        XCTAssertEqual(polisher.polish("please send my email address"), "Please send my email address.")
    }

    func testSnippetIgnoresDisabledTrigger() {
        let result = TextPolisher(
            snippets: [
                SnippetExpansion(trigger: "my email address", body: "brunner@runnertechnologies.com", isEnabled: false)
            ]
        )
        .polish("my email address")

        XCTAssertEqual(result, "My email address.")
    }

    func testTranscriptionLanguageMappingTreatsAutoAsDetection() {
        XCTAssertNil(TranscriptionEngine.decodingLanguage(for: "auto"))
        XCTAssertNil(TranscriptionEngine.decodingLanguage(for: "  "))
        XCTAssertEqual(TranscriptionEngine.decodingLanguage(for: "ES"), "es")
        XCTAssertEqual(TranscriptionEngine.decodingLanguage(for: " ja "), "ja")
        XCTAssertEqual(TranscriptionEngine.decodingLanguage(for: "ZH"), "zh")
    }

    func testAutoDetectionStillForcesTheTranscriptionPrompt() {
        let options = TranscriptionEngine.decodingOptions(for: "auto")
        XCTAssertTrue(options.usePrefillPrompt)
        XCTAssertTrue(options.detectLanguage)
        XCTAssertNil(options.language)
        XCTAssertEqual(options.task, .transcribe)
        XCTAssertTrue(options.skipSpecialTokens)
        XCTAssertEqual(options.temperatureFallbackCount, 0)
    }

    func testExplicitLanguageDoesNotGetRedetected() {
        let options = TranscriptionEngine.decodingOptions(for: "en")
        XCTAssertEqual(options.language, "en")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertTrue(options.usePrefillPrompt)
        XCTAssertEqual(options.task, .transcribe)
    }

    func testSilentDeadAndBriefInputCannotReachTranscription() {
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio([]))
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio(Array(repeating: 0, count: 32_000)))
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio(Array(repeating: 0.2, count: 32_000)))
        var click = Array(repeating: Float(0), count: 16_000)
        click[400] = 1
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio(click))
    }

    func testQuietSustainedAudioPassesButCorruptSamplesDoNot() {
        var samples = (0..<3_200).map { Float(sin(Double($0) * 0.2) * 0.003) }
        XCTAssertTrue(TranscriptionEngine.containsUsableAudio(samples))
        samples.append(.nan)
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio(samples))
        XCTAssertFalse(TranscriptionEngine.containsUsableAudio([.infinity]))
    }

    func testUnreliableDecoderOutputIsRejectedInsteadOfInserted() {
        XCTAssertTrue(TranscriptionEngine.acceptsSegment(averageLogProbability: -0.3, compressionRatio: 1.2))
        XCTAssertFalse(TranscriptionEngine.acceptsSegment(averageLogProbability: -1.1, compressionRatio: 1.2))
        XCTAssertFalse(TranscriptionEngine.acceptsSegment(averageLogProbability: -0.3, compressionRatio: 2.5))
        XCTAssertFalse(TranscriptionEngine.acceptsSegment(averageLogProbability: .nan, compressionRatio: 1.2))
    }

    func testLanguageCatalogIncludesCoreAndCandidateLanguages() {
        XCTAssertEqual(SpeechLanguage.title(for: "auto"), "Auto Detect")
        XCTAssertEqual(SpeechLanguage.title(for: "pt"), "Portuguese")
        XCTAssertEqual(SpeechLanguage.title(for: "ja"), "Japanese")
        XCTAssertEqual(SpeechLanguage.title(for: "zh", short: true), "Chinese")
        XCTAssertEqual(SpeechLanguage(rawValue: "en")?.validationLabel, "Core test set")
        XCTAssertEqual(SpeechLanguage(rawValue: "ar")?.validationLabel, "Candidate")
    }

    func testRecordingTimingFormatting() {
        XCTAssertEqual(RecordingTimingSummary.formatted(0), "0.0s")
        XCTAssertEqual(RecordingTimingSummary.formatted(1.24), "1.2s")
        XCTAssertEqual(RecordingTimingSummary.formatted(12.6), "13s")
        XCTAssertEqual(RecordingTimingSummary.formatted(-2), "0.0s")
    }

    func testRecordingTimingRowsStayInValidationOrder() {
        let summary = RecordingTimingSummary(
            capturedAt: Date(timeIntervalSince1970: 0),
            recordingDuration: 10,
            modelPrepareDuration: 2,
            transcriptionDuration: 3,
            polishAndCopyDuration: 0.2,
            releaseToCopiedDuration: 5.2
        )

        XCTAssertEqual(summary.rows.map(\.title), [
            "Recording",
            "Model Prepare",
            "Transcription",
            "Polish + Copy",
            "Release to Copied"
        ])
    }

    func testCleanupTemporaryRecordingsOnlyRemovesVyrraAudioFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let staleRecording = directory
            .appendingPathComponent("Vyrra-stale-recording")
            .appendingPathExtension("caf")
        let unrelatedAudio = directory
            .appendingPathComponent("OtherApp-recording")
            .appendingPathExtension("caf")
        let vyrraNonAudio = directory
            .appendingPathComponent("Vyrra-note")
            .appendingPathExtension("txt")

        try Data("stale".utf8).write(to: staleRecording)
        try Data("other".utf8).write(to: unrelatedAudio)
        try Data("note".utf8).write(to: vyrraNonAudio)

        let removedCount = AudioRecorder.cleanupTemporaryRecordings(in: directory)

        XCTAssertEqual(removedCount, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: staleRecording.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedAudio.path))
        XCTAssertTrue(fileManager.fileExists(atPath: vyrraNonAudio.path))
    }

    func testAudioMeterNormalizationClampsSilenceAndLoudInput() {
        XCTAssertEqual(AudioRecorder.normalizedMeterLevel(decibels: -.infinity), 0)
        XCTAssertEqual(AudioRecorder.normalizedMeterLevel(decibels: -80), 0)
        XCTAssertEqual(AudioRecorder.normalizedMeterLevel(decibels: -20), 0.5, accuracy: 0.000_1)
        XCTAssertEqual(AudioRecorder.normalizedMeterLevel(decibels: 0), 1)
    }

    func testHistoryRecordFormatterUsesTitleOrGeneratedFallback() {
        XCTAssertEqual(
            HistoryRecordFormatter.displayTitle(title: " Launch Note ", polishedText: "Ignored text."),
            "Launch Note"
        )

        XCTAssertEqual(
            HistoryRecordFormatter.displayTitle(title: nil, polishedText: "Short generated title."),
            "Short generated title."
        )

        XCTAssertEqual(
            HistoryRecordFormatter.displayTitle(title: "   ", polishedText: "   "),
            "Untitled Transcript"
        )

        XCTAssertEqual(
            HistoryRecordFormatter.displayTitle(
                title: nil,
                polishedText: "- First saved point\n- Second saved point"
            ),
            "First saved point"
        )

        XCTAssertEqual(
            HistoryRecordFormatter.displayTitle(
                title: nil,
                polishedText: "• First polished point\n• Second polished point"
            ),
            "First polished point"
        )
    }

    func testHistorySectionDefaultsToInbox() {
        XCTAssertEqual(HistoryRecordFormatter.displaySectionName(nil), "Inbox")
        XCTAssertEqual(HistoryRecordFormatter.displaySectionName("  "), "Inbox")
        XCTAssertEqual(HistoryRecordFormatter.displaySectionName(" Work "), "Work")
    }

    func testHistoryStorageEstimateCountsStoredTextOnly() {
        let bytes = HistoryStorageEstimate.bytes(
            rawText: "raw",
            polishedText: "polished",
            title: "title",
            sectionName: "section",
            tagsText: "work"
        )

        XCTAssertEqual(bytes, 3 + 8 + 5 + 7 + 4)
        XCTAssertFalse(HistoryStorageEstimate.formatted(bytes: bytes).isEmpty)
    }

    func testHistoryTagFormatterNormalizesTags() {
        XCTAssertEqual(
            HistoryTagFormatter.normalizedTags(from: "#Work, follow-up work\nclient"),
            ["Work", "follow-up", "client"]
        )
        XCTAssertEqual(HistoryTagFormatter.storageText(from: "#Work, follow-up"), "Work, follow-up")
        XCTAssertEqual(HistoryTagFormatter.displayText(from: "#Work, follow-up"), "#Work #follow-up")
    }

    func testHistoryExportIncludesMetadataAndMarkdown() {
        let record = HistoryDisplayRecord(
            title: "Launch",
            polishedText: "Ship it.",
            rawText: "ship it",
            sectionName: "Work",
            tagsText: "launch, follow-up",
            createdAt: Date(timeIntervalSince1970: 0),
            duration: 1.2,
            modelName: "tiny",
            polishingMode: PolishingMode.cleanUp.rawValue
        )

        let plainText = HistoryExportFormatter.plainText(record: record)
        let markdown = HistoryExportFormatter.markdown(record: record)

        XCTAssertTrue(plainText.contains("Launch"))
        XCTAssertTrue(plainText.contains("#launch #follow-up"))
        XCTAssertTrue(markdown.contains("# Launch"))
        XCTAssertTrue(markdown.contains("- Tags: #launch #follow-up"))
    }

    func testVyrraExportPayloadIncludesLocalDataAndSelectedPreferences() throws {
        let suiteName = "VyrraExportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let manager = ModelManager(defaults: defaults)
        manager.selectedModel = .debugTiny
        manager.selectedLanguageCode = SpeechLanguage.english.rawValue
        manager.polishingMode = .notes
        manager.savesHistory = false
        manager.waveformSensitivity = 1.25
        manager.waveformMotion = .calm
        manager.hapticsEnabled = false

        let createdAt = Date(timeIntervalSince1970: 1_777_700)
        let record = TranscriptionRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: createdAt,
            rawText: "ship it",
            polishedText: "Ship it.",
            title: "Launch",
            sectionName: "Work",
            tagsText: "launch",
            duration: 1.2,
            modelName: SpeechModel.debugTiny.rawValue,
            polishingMode: .notes
        )
        let folder = NoteFolder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: createdAt,
            updatedAt: createdAt,
            name: "Work"
        )
        let vocabulary = VocabularyEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            createdAt: createdAt,
            updatedAt: createdAt,
            spokenForm: "runner concepts",
            preferredText: "Runner Concepts",
            category: .company,
            isEnabled: true
        )
        let snippet = SnippetEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            createdAt: createdAt,
            updatedAt: createdAt,
            trigger: "sig",
            body: "Sent from Vyrra",
            isEnabled: true
        )

        let payload = VyrraExportPayload.make(
            records: [record],
            folders: [folder],
            vocabulary: [vocabulary],
            snippets: [snippet],
            modelManager: manager,
            exportedAt: createdAt,
            appVersion: "1.2.3",
            buildNumber: "45"
        )
        let data = try VyrraExportWriter.encodedData(for: payload)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.records.first?.polishedText, "Ship it.")
        XCTAssertEqual(payload.folders.first?.name, "Work")
        XCTAssertEqual(payload.vocabulary.first?.preferredText, "Runner Concepts")
        XCTAssertEqual(payload.snippets.first?.body, "Sent from Vyrra")
        XCTAssertEqual(payload.selectedPreferences.selectedModel, SpeechModel.debugTiny.rawValue)
        XCTAssertEqual(payload.selectedPreferences.selectedLanguageCode, SpeechLanguage.english.rawValue)
        XCTAssertEqual(payload.selectedPreferences.polishingMode, PolishingMode.notes.rawValue)
        XCTAssertEqual(payload.selectedPreferences.waveformMotion, WaveformMotion.calm.rawValue)
        XCTAssertFalse(payload.selectedPreferences.savesHistory)
        XCTAssertFalse(json.contains("http"))
        XCTAssertFalse(json.contains("support@"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("account"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("analytics"))
    }

    func testVyrraExportPreferencesDecodeBeforeWaveformMotionWasAdded() throws {
        let data = try XCTUnwrap(
            """
            {
              "selectedModel": "tiny",
              "selectedModelTitle": "Fast",
              "selectedLanguageCode": "en",
              "selectedLanguageTitle": "English",
              "polishingMode": "notes",
              "savesHistory": true,
              "waveformSensitivity": 1.0,
              "hapticsEnabled": true
            }
            """.data(using: .utf8)
        )

        let preferences = try JSONDecoder().decode(VyrraExportPreferences.self, from: data)

        XCTAssertNil(preferences.waveformMotion)
    }

    func testHistoryFolderRecommenderPrioritizesMatchingFolders() {
        let recommendations = HistoryFolderRecommender.recommendedFolderNames(
            title: "Launch follow-up",
            text: "Send the project update to the work channel.",
            folders: ["Inbox", "Work", "Personal", "Launch"],
            currentFolder: "Inbox"
        )

        XCTAssertEqual(recommendations, ["Launch", "Work"])
    }

    func testHistoryFolderRecommenderExcludesCurrentFolderAndInbox() {
        let recommendations = HistoryFolderRecommender.recommendedFolderNames(
            title: "Work note",
            text: "Work and inbox should not be suggested when already in work.",
            folders: ["Inbox", "Work", "work", "Archive"],
            currentFolder: "Work"
        )

        XCTAssertEqual(recommendations, [])
    }

    func testModelCacheValidationRequiresCoreWhisperKitArtifacts() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraModelCache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(
            at: directory.appendingPathComponent("MelSpectrogram.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("AudioEncoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertFalse(ModelCacheStore.folderIsUsable(directory))

        try fileManager.createDirectory(
            at: directory.appendingPathComponent("TextDecoder.mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(ModelCacheStore.folderIsUsable(directory))
    }

    func testModelCacheSaveSummaryAndClearRoundTrip() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-\(UUID().uuidString)"
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraModelCache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: directory)
        }

        for artifact in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(artifact, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try Data("model bytes".utf8).write(to: directory.appendingPathComponent("weights.bin"))

        ModelCacheStore.save(folder: directory, for: modelName)

        let summary = ModelCacheStore.summary(for: modelName)
        XCTAssertTrue(summary.isUsable)
        XCTAssertEqual(summary.statusLabel, "Cached")
        XCTAssertNotNil(ModelCacheStore.cachedFolder(for: modelName))
        XCTAssertGreaterThan(summary.sizeBytes, 0)
        XCTAssertFalse(summary.sizeLabel.isEmpty)

        ModelCacheStore.clearMetadata(for: modelName)

        XCTAssertFalse(ModelCacheStore.summary(for: modelName).isUsable)
        XCTAssertNil(ModelCacheStore.cachedFolder(for: modelName))
    }

    func testModelCacheDeleteRemovesFolderAndMetadata() throws {
        let fileManager = FileManager.default
        let modelName = "test-model-\(UUID().uuidString)"
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("VyrraModelCache-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            ModelCacheStore.clearMetadata(for: modelName)
            try? fileManager.removeItem(at: directory)
        }

        for artifact in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent(artifact, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        ModelCacheStore.save(folder: directory, for: modelName)
        XCTAssertTrue(fileManager.fileExists(atPath: directory.path))

        XCTAssertTrue(ModelCacheStore.deleteCachedModel(for: modelName))
        XCTAssertFalse(fileManager.fileExists(atPath: directory.path))
        XCTAssertFalse(ModelCacheStore.summary(for: modelName).isUsable)
        XCTAssertNil(ModelCacheStore.cachedFolder(for: modelName))
    }
}
