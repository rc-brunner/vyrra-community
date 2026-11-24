import XCTest
@testable import Vyrra

final class ModelManagerTests: XCTestCase {
    func testPersistsOutputPreferencesAcrossManagers() throws {
        let suiteName = "ModelManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = ModelManager(defaults: defaults)
        manager.selectedModel = .debugTiny
        manager.selectedLanguageCode = SpeechLanguage.spanish.rawValue
        manager.polishingMode = .bullets
        manager.waveformSensitivity = 1.35
        manager.waveformMotion = .detail
        manager.hapticsEnabled = false
        manager.savesHistory = false

        let restored = ModelManager(defaults: defaults)

        XCTAssertEqual(restored.selectedModel, .debugTiny)
        XCTAssertEqual(restored.selectedLanguageCode, SpeechLanguage.spanish.rawValue)
        XCTAssertEqual(restored.polishingMode, .bullets)
        XCTAssertEqual(restored.waveformSensitivity, 1.35, accuracy: 0.001)
        XCTAssertEqual(restored.waveformMotion, .detail)
        XCTAssertFalse(restored.hapticsEnabled)
        XCTAssertFalse(restored.savesHistory)
    }

    func testFallsBackWhenStoredOutputPreferencesAreInvalid() throws {
        let suiteName = "ModelManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("missing-model", forKey: "selectedModel")
        defaults.set("xx", forKey: "selectedLanguageCode")
        defaults.set("loud", forKey: "polishingMode")
        defaults.set("jitter", forKey: "waveformMotion")

        let manager = ModelManager(defaults: defaults, preferredLanguages: ["en-US"])

        XCTAssertEqual(manager.selectedModel, .recommendedLarge)
        XCTAssertEqual(manager.selectedLanguageCode, SpeechLanguage.english.rawValue)
        XCTAssertEqual(manager.polishingMode, .cleanUp)
        XCTAssertEqual(manager.waveformMotion, .flow)
    }

    func testDefaultLanguageUsesDevicePreferenceWithoutReplacingExplicitChoice() throws {
        let suiteName = "ModelManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["en-US"]).selectedLanguageCode, "en")
        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["fr-CA"]).selectedLanguageCode, "fr")
        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["pt_BR"]).selectedLanguageCode, "pt")
        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["xx"]).selectedLanguageCode, "auto")

        defaults.set("auto", forKey: "selectedLanguageCode")
        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["en-US"]).selectedLanguageCode, "auto")
        defaults.set("es", forKey: "selectedLanguageCode")
        XCTAssertEqual(ModelManager(defaults: defaults, preferredLanguages: ["en-US"]).selectedLanguageCode, "es")
    }

    @MainActor
    func testCachedPreferredModelAutoWarmsOnForeground() async throws {
        let manager = try makeManager(selectedModel: .liteSmall)
        let preparer = MockVoiceReadinessPreparer()
        let coordinator = VoiceReadinessCoordinator(
            modelManager: manager,
            preparer: preparer,
            cacheSummaryProvider: { modelName in
                Self.cacheSummary(modelName: modelName, isUsable: modelName == SpeechModel.liteSmall.rawValue)
            }
        )

        coordinator.refreshForForeground()
        await Task.yield()

        XCTAssertEqual(preparer.prepareCalls, [SpeechModel.liteSmall.rawValue])
        XCTAssertEqual(coordinator.state, .ready(modelName: SpeechModel.liteSmall.rawValue))
    }

    @MainActor
    func testUncachedPreferredModelDoesNotAutoDownload() async throws {
        let manager = try makeManager(selectedModel: .recommendedLarge)
        let preparer = MockVoiceReadinessPreparer()
        let coordinator = VoiceReadinessCoordinator(
            modelManager: manager,
            preparer: preparer,
            cacheSummaryProvider: { modelName in
                Self.cacheSummary(modelName: modelName, isUsable: false)
            }
        )

        coordinator.refreshForForeground()
        await Task.yield()

        XCTAssertTrue(preparer.prepareCalls.isEmpty)
        XCTAssertEqual(coordinator.state, .notDownloaded)
    }

    @MainActor
    func testOnlyPreferredModelWarmsWhenMultipleModelsAreCached() async throws {
        let manager = try makeManager(selectedModel: .debugTiny)
        let preparer = MockVoiceReadinessPreparer()
        let coordinator = VoiceReadinessCoordinator(
            modelManager: manager,
            preparer: preparer,
            cacheSummaryProvider: { modelName in
                Self.cacheSummary(modelName: modelName, isUsable: true)
            }
        )

        coordinator.refreshForForeground()
        await Task.yield()

        XCTAssertEqual(preparer.prepareCalls, [SpeechModel.debugTiny.rawValue])
        XCTAssertEqual(coordinator.state, .ready(modelName: SpeechModel.debugTiny.rawValue))
    }

    @MainActor
    func testFailedAutoWarmSurfacesRetryableStateWithoutLooping() async throws {
        let manager = try makeManager(selectedModel: .debugTiny)
        let preparer = MockVoiceReadinessPreparer()
        preparer.prepareHandler = { _ in
            throw MockVoiceReadinessError.prepareFailed
        }
        let coordinator = VoiceReadinessCoordinator(
            modelManager: manager,
            preparer: preparer,
            cacheSummaryProvider: { modelName in
                Self.cacheSummary(modelName: modelName, isUsable: true)
            }
        )

        coordinator.refreshForForeground()
        await Task.yield()
        coordinator.refreshForForeground()
        await Task.yield()

        XCTAssertEqual(preparer.prepareCalls, [SpeechModel.debugTiny.rawValue])
        if case .failed(let message) = coordinator.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected failed readiness state")
        }
    }

    @MainActor
    func testDownloadCompletionWarmsOnlyThePreferredModel() async throws {
        let manager = try makeManager(selectedModel: .liteSmall)
        let preparer = MockVoiceReadinessPreparer()
        var cachedModels = Set<String>()
        let coordinator = VoiceReadinessCoordinator(
            modelManager: manager,
            preparer: preparer,
            cacheSummaryProvider: { modelName in
                Self.cacheSummary(modelName: modelName, isUsable: cachedModels.contains(modelName))
            }
        )

        cachedModels.insert(SpeechModel.debugTiny.rawValue)
        coordinator.handleDownloadCompleted(model: .debugTiny)
        await Task.yield()
        XCTAssertTrue(preparer.prepareCalls.isEmpty)

        cachedModels.insert(SpeechModel.liteSmall.rawValue)
        coordinator.handleDownloadCompleted(model: .liteSmall)
        await Task.yield()

        XCTAssertEqual(preparer.prepareCalls, [SpeechModel.liteSmall.rawValue])
        XCTAssertEqual(coordinator.state, .ready(modelName: SpeechModel.liteSmall.rawValue))
    }

    private func makeManager(selectedModel: SpeechModel) throws -> ModelManager {
        let suiteName = "VoiceReadinessTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let manager = ModelManager(defaults: defaults)
        manager.selectedModel = selectedModel
        return manager
    }

    private static func cacheSummary(modelName: String, isUsable: Bool) -> ModelCacheSummary {
        ModelCacheSummary(
            modelName: modelName,
            folderPath: isUsable ? "/tmp/\(modelName)" : nil,
            isUsable: isUsable,
            sizeBytes: isUsable ? 123 : 0
        )
    }
}

@MainActor
private final class MockVoiceReadinessPreparer: VoiceReadinessPreparing {
    var state: TranscriptionEngineState = .idle
    var prepareCalls: [String] = []
    var prepareHandler: ((String) async throws -> Void)?

    func prepare(modelName: String) async throws {
        prepareCalls.append(modelName)
        if let prepareHandler {
            try await prepareHandler(modelName)
        } else {
            state = .ready(modelName)
        }
    }
}

private enum MockVoiceReadinessError: LocalizedError {
    case prepareFailed

    var errorDescription: String? {
        "Prepare failed."
    }
}

@MainActor
final class ModelSetupCoordinatorTests: XCTestCase {
    func testConcurrentPreparationAndDownloadShareOneCacheWriter() async throws {
        let setup = ModelSetupCoordinator()
        let started = expectation(description: "Setup started")
        let joined = expectation(description: "All callers joined")
        joined.expectedFulfillmentCount = 12
        var resume: CheckedContinuation<Void, Never>?
        var writes = 0
        let first = Task {
            try await setup.run(modelName: "large-v3", kind: .prepare) {
                writes += 1
                await withCheckedContinuation { resume = $0; started.fulfill() }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let callers = (0..<12).map { index in
            Task {
                joined.fulfill()
                try await setup.run(modelName: "large-v3", kind: index.isMultiple(of: 2) ? .prepare : .download) {
                    writes += 1
                }
            }
        }
        await fulfillment(of: [joined], timeout: 2)
        resume?.resume()
        try await first.value
        for caller in callers { try await caller.value }
        XCTAssertEqual(writes, 1)
    }

    func testPrepareWaitsForDownloadThenLoadsInsteadOfSkippingPreparation() async throws {
        let setup = ModelSetupCoordinator()
        let started = expectation(description: "Download started")
        var resume: CheckedContinuation<Void, Never>?
        var events: [String] = []
        let download = Task {
            try await setup.run(modelName: "tiny", kind: .download) {
                events.append("download")
                await withCheckedContinuation { resume = $0; started.fulfill() }
                events.append("cached")
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let prepare = Task {
            try await setup.run(modelName: "tiny", kind: .prepare) { events.append("loaded") }
        }
        resume?.resume()
        try await download.value
        try await prepare.value
        XCTAssertEqual(events, ["download", "cached", "loaded"])
    }

    func testDifferentModelsSerializeAndFailureDoesNotBlockTheNextModel() async throws {
        let setup = ModelSetupCoordinator()
        let started = expectation(description: "First setup started")
        var resume: CheckedContinuation<Void, Never>?
        var events: [String] = []
        let first = Task {
            try await setup.run(modelName: "large-v3", kind: .prepare) {
                events.append("large-start")
                await withCheckedContinuation { resume = $0; started.fulfill() }
                events.append("large-failed")
                throw MockVoiceReadinessError.prepareFailed
            }
        }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            try await setup.run(modelName: "small", kind: .prepare) { events.append("small-loaded") }
        }
        resume?.resume()
        if case .success = await first.result { XCTFail("Expected the first setup to fail") }
        try await second.value
        XCTAssertEqual(events, ["large-start", "large-failed", "small-loaded"])
    }

    func testCancelingAWaiterDoesNotCancelSharedSetupAndRetryIsPossible() async throws {
        let setup = ModelSetupCoordinator()
        let started = expectation(description: "Setup started")
        var resume: CheckedContinuation<Void, Never>?
        var completed = false
        let first = Task {
            try await setup.run(modelName: "tiny", kind: .prepare) {
                await withCheckedContinuation { resume = $0; started.fulfill() }
                try Task.checkCancellation()
                completed = true
            }
        }
        await fulfillment(of: [started], timeout: 2)
        first.cancel()
        resume?.resume()
        do {
            try await first.value
            XCTFail("Expected canceled caller")
        } catch is CancellationError {}
        XCTAssertTrue(completed)
        var retried = false
        try await setup.run(modelName: "tiny", kind: .prepare) { retried = true }
        XCTAssertTrue(retried)
    }

    func testMissingTokenizerMoveIsRecoverableAndDoesNotExposeTheCachePath() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [
            NSFilePathErrorKey: "/private/test/models/openai/whisper-large-v3/.cache/tokenizer.json.abc.incomplete"
        ])
        XCTAssertTrue(TranscriptionEngine.isTokenizerCacheError(error))
        let message = TranscriptionEngine.userFacingError(for: error).localizedDescription
        XCTAssertTrue(message.contains("Prepare again"))
        XCTAssertFalse(message.contains("/private/"))
        let wrapped = NSError(domain: "ModelSetup", code: 1, userInfo: [NSUnderlyingErrorKey: error])
        XCTAssertTrue(TranscriptionEngine.isTokenizerCacheError(wrapped))
        XCTAssertFalse(TranscriptionEngine.isTokenizerCacheError(URLError(.notConnectedToInternet)))
    }
}
