import XCTest
import AVFoundation
@testable import Vyrra

final class DictationSessionControllerTests: XCTestCase {
    @MainActor
    func testBundledDictationClicksAreShortAndTheStartCueReturns() async throws {
        for name in DictationSound.Palette.allCases.flatMap({ [$0.file(closing: false), $0.file(closing: true)].compactMap { $0 } }) {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "DictationSounds"))
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertGreaterThan(duration, 0.03)
            XCTAssertLessThan(duration, 0.09)
        }
        let clock = ContinuousClock()
        let elapsed = await clock.measure { await DictationSound.engageBeforeCapture() }
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    @MainActor
    func testExistingMuteAndSoundSelectionSurviveUpgrade() throws {
        let suite = UUID().uuidString
        let values = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { values.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DictationSound.palette(in: values), .classic)
        values.set(false, forKey: DictationSound.preferenceKey)
        XCTAssertEqual(DictationSound.palette(in: values), .off)
        values.set(true, forKey: DictationSound.preferenceKey)
        values.set("felt", forKey: DictationSound.paletteKey)
        XCTAssertEqual(DictationSound.palette(in: values).file(closing: true), "felt-release")
    }

    func testKeyboardCaptureDiscardsAudioBetweenSeparatePhrases() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for index in 0..<160 { samples[index] = 0.25 }
        let capture = KeyboardPhraseCapture()

        capture.append(buffer)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let firstURL = directory.appendingPathComponent("first.caf")
        try capture.begin(at: firstURL, format: format)
        capture.append(buffer)
        let first = try capture.finish()
        capture.append(buffer)
        capture.append(buffer)

        let secondURL = directory.appendingPathComponent("second.caf")
        try capture.begin(at: secondURL, format: format)
        for index in 0..<160 { samples[index] = 0.5 }
        capture.append(buffer)
        let second = try capture.finish()

        XCTAssertEqual(first.duration, 0.01, accuracy: 0.0001)
        XCTAssertEqual(second.duration, 0.01, accuracy: 0.0001)
        for (url, expectedValue) in [(firstURL, Float(0.25)), (secondURL, Float(0.5))] {
            let audio = try AVAudioFile(forReading: url)
            XCTAssertEqual(audio.length, 160)
            let result = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 160))
            try audio.read(into: result)
            XCTAssertEqual(try XCTUnwrap(result.floatChannelData?.pointee)[0], expectedValue, accuracy: 0.001)
        }
        XCTAssertThrowsError(try capture.finish())
    }

    func testKeyboardCaptureRejectsOverlappingPhrasesAndRemovesCancelledAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let capture = KeyboardPhraseCapture()
        let firstURL = directory.appendingPathComponent("first.caf")
        let secondURL = directory.appendingPathComponent("second.caf")
        try capture.begin(at: firstURL, format: format)
        XCTAssertThrowsError(try capture.begin(at: secondURL, format: format))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        capture.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        try capture.begin(at: secondURL, format: format)
        capture.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @MainActor
    func testKeyboardMicrophoneIndicatorExpiresWithItsSession() {
        let now = Date(timeIntervalSince1970: 10_000)
        let expiry = now.addingTimeInterval(300)
        let content = VyrraActivityAttributes.ContentState(
            state: .keyboardReady, startedAt: now, updatedAt: now,
            keyboardSessionExpiresAt: expiry
        )
        XCTAssertEqual(VyrraLiveActivityController.staleDate(for: content, now: now), expiry)
    }

    func testResultBuilderAppliesVocabularyAndSnippetRules() throws {
        let polished = try DictationSessionResultBuilder.polishedText(
            rawText: "vyrra",
            mode: .cleanUp,
            vocabulary: [
                VocabularyReplacement(spokenForm: "vyrra", preferredText: "Vyrra")
            ],
            snippets: [
                SnippetExpansion(trigger: "my email", body: "hello@example.com")
            ]
        )

        XCTAssertEqual(polished, "Vyrra.")
    }

    func testResultBuilderAllowsExactSnippetExpansion() throws {
        let polished = try DictationSessionResultBuilder.polishedText(
            rawText: "my email",
            mode: .cleanUp,
            vocabulary: [],
            snippets: [
                SnippetExpansion(trigger: "my email", body: "hello@example.com")
            ]
        )

        XCTAssertEqual(polished, "hello@example.com")
    }

    func testResultBuilderThrowsForEmptyPolishedText() {
        XCTAssertThrowsError(
            try DictationSessionResultBuilder.polishedText(
                rawText: "   ",
                mode: .cleanUp,
                vocabulary: [],
                snippets: []
            )
        ) { error in
            XCTAssertEqual(error as? TranscriptionEngineError, .emptyTranscript)
        }
    }

    @MainActor
    func testInterruptionOnlyChangesActiveRecording() {
        let idleController = DictationSessionController(initialPhase: .idle)
        idleController.handleInterruptionMessage("Interrupted")
        XCTAssertEqual(idleController.phase, .idle)

        let recordingController = DictationSessionController(initialPhase: .recording)
        recordingController.handleInterruptionMessage("Interrupted")
        XCTAssertEqual(recordingController.phase, .error("Interrupted"))
    }

    @MainActor
    func testInitialPreparationPhaseMatchesCacheState() {
        let uncachedSummary = ModelCacheSummary(
            modelName: "tiny",
            folderPath: nil,
            isUsable: false,
            sizeBytes: 0
        )
        let cachedSummary = ModelCacheSummary(
            modelName: "tiny",
            folderPath: "/tmp/VyrraModel",
            isUsable: true,
            sizeBytes: 75
        )

        XCTAssertEqual(
            DictationSessionController.initialPreparationPhase(cacheSummary: uncachedSummary),
            .modelDownloading(0)
        )
        XCTAssertEqual(
            DictationSessionController.initialPreparationPhase(cacheSummary: cachedSummary),
            .modelPreparing
        )
    }

    func testRecordingLimitMatchesSharedFiveMinutePolicy() {
        XCTAssertEqual(VyrraSessionPolicy.maximumRecordingDuration, 300)
        XCTAssertEqual(
            AudioRecorder.maximumRecordingDuration,
            VyrraSessionPolicy.maximumRecordingDuration
        )
        XCTAssertGreaterThan(
            VyrraSessionPolicy.listeningStaleInterval,
            VyrraSessionPolicy.maximumRecordingDuration
        )
    }

    @MainActor
    func testRecoverableRecordingBlocksSilentLossUntilDiscarded() throws {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vyrra-Recovery-Test-\(UUID().uuidString).caf")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let controller = DictationSessionController(
            initialRecoverableRecording: PendingRecordingSnapshot(
                result: RecordingResult(url: audioURL, duration: 8),
                createdAt: Date()
            )
        )

        XCTAssertTrue(controller.hasRecoverableRecording)
        XCTAssertEqual(controller.phase, .error("Your recording is saved on this device."))

        controller.discardRecoverableRecording()

        XCTAssertFalse(controller.hasRecoverableRecording)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    @MainActor
    func testLiveActivityStatesMatchTheVisibleRecordingLifecycle() {
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .recording), .listening)
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .transcribing), .polishing)
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .processing), .polishing)
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .copied), .copied)
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .emptyTranscript), .attention)
        XCTAssertEqual(VyrraLiveActivityController.liveState(for: .error("Failed")), .attention)
        XCTAssertNil(VyrraLiveActivityController.liveState(for: .idle))
        XCTAssertEqual(VyrraLiveActivityState.polishing.title, "Processing")
    }

    @MainActor
    func testLiveActivityStaysFreshForTheFullRecordingAndEndsBriefly() {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        let now = startedAt.addingTimeInterval(15)
        let listening = VyrraActivityAttributes.ContentState(
            state: .listening,
            startedAt: startedAt,
            updatedAt: now
        )
        let copied = VyrraActivityAttributes.ContentState(
            state: .copied,
            startedAt: startedAt,
            updatedAt: now
        )

        XCTAssertGreaterThanOrEqual(
            VyrraLiveActivityController.staleDate(for: listening, now: now),
            startedAt.addingTimeInterval(VyrraSessionPolicy.listeningStaleInterval)
        )
        XCTAssertEqual(
            VyrraLiveActivityController.staleDate(for: copied, now: now),
            now.addingTimeInterval(VyrraSessionPolicy.liveActivityCompletionVisibility + 2)
        )
    }

    func testVoiceOverHearsEachMomentOfTheRecordLoop() {
        let text = "Move the launch checklist to Friday."
        func announcement(_ old: RecordingPhase, _ new: RecordingPhase, saved: Bool = false) -> DictationAnnouncement? {
            DictationAnnouncement.forTransition(from: old, to: new, polishedText: text, hasRecoverableRecording: saved)
        }

        XCTAssertEqual(DictationAnnouncement.recordingStarted.message, "Recording")
        XCTAssertEqual(announcement(.recording, .processing)?.message, "Stopped. Transcribing.")
        XCTAssertEqual(announcement(.recording, .transcribing)?.message, "Stopped. Transcribing.")
        XCTAssertNil(announcement(.processing, .transcribing), "Busy phases alternate; announce once")
        XCTAssertNil(announcement(.transcribing, .processing))
        XCTAssertEqual(announcement(.error("Saved"), .processing, saved: true)?.message, "Transcribing.")
        XCTAssertEqual(announcement(.processing, .copied), DictationAnnouncement(message: "Copied. \(text)", priority: .high))
        XCTAssertEqual(announcement(.recording, .idle)?.message, "Recording canceled.")
        XCTAssertEqual(announcement(.processing, .emptyTranscript)?.priority, .high)
        XCTAssertEqual(announcement(.idle, .microphoneDenied)?.message, "Microphone is off. Turn it on in Settings.")
        XCTAssertEqual(announcement(.processing, .error("Engine failed."), saved: true)?.message, "Recording saved. Retry when ready.")
        XCTAssertEqual(announcement(.processing, .error("Engine failed."))?.message, "Try again. Engine failed.")
        XCTAssertNil(announcement(.idle, .recording), "Recording is announced before capture, not after")
        XCTAssertNil(announcement(.copied, .copied))
        XCTAssertNil(announcement(.idle, .modelPreparing))
    }

    func testCopiedAnnouncementReadsBackAShortExcerpt() {
        let long = String(repeating: "word ", count: 40)
        let excerpt = DictationAnnouncement.excerpt(of: long)

        XCTAssertLessThanOrEqual(excerpt.count, DictationAnnouncement.transcriptExcerptLength)
        XCTAssertFalse(excerpt.hasSuffix(" "))
        XCTAssertTrue(excerpt.hasSuffix("word"), "Excerpts end on a whole word")
        XCTAssertEqual(DictationAnnouncement.excerpt(of: "  Hello.  "), "Hello.")
    }
}
