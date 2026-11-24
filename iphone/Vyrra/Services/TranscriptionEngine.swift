import Foundation
import WhisperKit

enum TranscriptionEngineState: Equatable {
    case idle
    case downloadingModel(String, Double)
    case loadingModel(String)
    case transcribing(String)
    case ready(String)
    case failed(String)
}

enum TranscriptionEngineError: LocalizedError {
    case emptyTranscript
    case modelSetupIncomplete
    case unreliableTranscript

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "No speech was detected in that recording."
        case .modelSetupIncomplete:
            "Model setup couldn't finish. Check your connection, keep Vyrra open, and tap Prepare again."
        case .unreliableTranscript:
            "Speech wasn't clear enough to transcribe. Check the spoken language in Settings > Model, then retry."
        }
    }
}

struct TranscriptionEngineResult {
    let text: String
    let modelPrepareDuration: TimeInterval
    let transcriptionDuration: TimeInterval
}

/// Main-actor isolation alone does not serialize work across suspension points.
/// Share matching setup requests and queue other models so Hub downloads and
/// tokenizer repair never mutate the same cache concurrently.
@MainActor
final class ModelSetupCoordinator {
    enum Kind { case download, prepare }

    private struct Operation {
        let id: UUID
        let modelName: String
        let kind: Kind
        let task: Task<Void, Error>
    }

    private var active: Operation?

    func run(modelName: String, kind: Kind, action: @escaping @MainActor () async throws -> Void) async throws {
        while let operation = active {
            let result = await operation.task.result
            finish(operation.id)
            try Task.checkCancellation()
            if operation.modelName == modelName, kind == .download || operation.kind == .prepare {
                return try result.get()
            }
        }

        try Task.checkCancellation()
        let id = UUID()
        // A canceled UI waiter must not cancel work shared by other callers.
        let task = Task { @MainActor in try await action() }
        active = Operation(id: id, modelName: modelName, kind: kind, task: task)
        defer { finish(id) }
        let result = await task.result
        try Task.checkCancellation()
        try result.get()
    }

    private func finish(_ id: UUID) {
        if active?.id == id { active = nil }
    }
}

@MainActor
final class TranscriptionEngine: ObservableObject {
    @Published private(set) var state: TranscriptionEngineState = .idle

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?
    private let setup = ModelSetupCoordinator()

    func unload(modelName: String? = nil) {
        guard modelName == nil || loadedModelName == modelName else { return }
        whisperKit = nil
        loadedModelName = nil
        state = .idle
    }

    func download(modelName: String) async throws {
        try await setup.run(modelName: modelName, kind: .download) { [self] in
            try await downloadModel(modelName: modelName)
        }
    }

    private func downloadModel(modelName: String) async throws {
        guard ModelCacheStore.cachedFolder(for: modelName) == nil else {
            restoreLoadedState()
            return
        }

        do {
            state = .downloadingModel(modelName, 0)
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                downloadBase: ModelCacheStore.hubDownloadBase
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(modelName: modelName, progress: progress.fractionCompleted)
                }
            }
            ModelCacheStore.save(folder: modelFolder, for: modelName)
            restoreLoadedState()
        } catch {
            let userFacingError = Self.userFacingError(for: error)
            state = .failed(userFacingError.localizedDescription)
            throw userFacingError
        }
    }

    func prepare(modelName: String) async throws {
        try await setup.run(modelName: modelName, kind: .prepare) { [self] in
            try await prepareModel(modelName: modelName)
        }
    }

    private func prepareModel(modelName: String) async throws {
        if whisperKit != nil, loadedModelName == modelName {
            state = .ready(modelName)
            return
        }

        do {
            if let cachedFolder = ModelCacheStore.cachedFolder(for: modelName) {
                do {
                    try await load(modelName: modelName, modelFolder: cachedFolder)
                    return
                } catch {
                    whisperKit = nil
                    loadedModelName = nil
                    if Self.isTokenizerCacheError(error) {
                        throw error
                    }
                    if !ModelCacheStore.deleteCachedModel(for: modelName) {
                        ModelCacheStore.clearMetadata(for: modelName)
                    }
                }
            }

            state = .downloadingModel(modelName, 0)
            let modelFolder = try await WhisperKit.download(
                variant: modelName,
                downloadBase: ModelCacheStore.hubDownloadBase
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(modelName: modelName, progress: progress.fractionCompleted)
                }
            }
            ModelCacheStore.save(folder: modelFolder, for: modelName)
            try await load(modelName: modelName, modelFolder: modelFolder)
        } catch {
            let userFacingError = Self.userFacingError(for: error)
            state = .failed(userFacingError.localizedDescription)
            throw userFacingError
        }
    }

    private func load(modelName: String, modelFolder: URL) async throws {
        state = .loadingModel(modelName)
        do {
            try await loadModel(modelName: modelName, modelFolder: modelFolder)
        } catch {
            guard Self.isTokenizerCacheError(error) else { throw error }
            ModelCacheStore.deleteTokenizerCache(for: modelName)
            try await loadModel(modelName: modelName, modelFolder: modelFolder)
        }
    }

    private func loadModel(modelName: String, modelFolder: URL) async throws {
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: ModelCacheStore.hubDownloadBase,
            modelFolder: modelFolder.path,
            tokenizerFolder: ModelCacheStore.hubDownloadBase,
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        loadedModelName = modelName
        state = .ready(modelName)
    }

    nonisolated static func userFacingError(for error: Error) -> Error {
        isTokenizerCacheError(error) ? TranscriptionEngineError.modelSetupIncomplete : error
    }

    nonisolated static func isTokenizerCacheError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        let message = [error.localizedDescription, cocoaError.userInfo[NSFilePathErrorKey] as? String ?? ""]
            .joined(separator: " ").lowercased()
        return message.contains("tokenizer configuration is missing") ||
            message.contains("tokenizer.json") ||
            message.contains("tokenizer_config") ||
            message.contains("tokenizer config") ||
            (cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError).map { isTokenizerCacheError($0) } == true
    }

    private func updateDownloadProgress(modelName: String, progress: Double) {
        guard case .downloadingModel(let activeModel, _) = state, activeModel == modelName else { return }
        state = .downloadingModel(modelName, progress)
    }

    private func restoreLoadedState() {
        if whisperKit != nil, let loadedModelName {
            state = .ready(loadedModelName)
        } else {
            state = .idle
        }
    }

    func transcribe(audioURL: URL, modelName: String, languageCode: String = "auto") async throws -> TranscriptionEngineResult {
        // Validate the same 16 kHz samples passed to the decoder. WhisperKit
        // 0.18.0 does not compute noSpeechProb, so its silence threshold alone
        // cannot prevent an empty microphone buffer from producing invented text.
        let samples = try await Task.detached(priority: .userInitiated) {
            try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        }.value
        guard Self.containsUsableAudio(samples) else {
            throw TranscriptionEngineError.emptyTranscript
        }

        let prepareStartedAt = Date()
        try await prepare(modelName: modelName)
        let modelPrepareDuration = Date().timeIntervalSince(prepareStartedAt)
        guard let whisperKit else { throw TranscriptionEngineError.emptyTranscript }

        let decodeOptions = Self.decodingOptions(for: languageCode)

        let transcriptionStartedAt = Date()
        state = .transcribing(modelName)
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: decodeOptions
            )
            state = .ready(modelName)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
        let transcriptionDuration = Date().timeIntervalSince(transcriptionStartedAt)
        let transcript = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            throw TranscriptionEngineError.emptyTranscript
        }
        let segments = results.flatMap(\.segments).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !segments.isEmpty, segments.allSatisfy({
            Self.acceptsSegment(averageLogProbability: $0.avgLogprob, compressionRatio: $0.compressionRatio)
        }) else {
            throw TranscriptionEngineError.unreliableTranscript
        }

        return TranscriptionEngineResult(
            text: transcript,
            modelPrepareDuration: modelPrepareDuration,
            transcriptionDuration: transcriptionDuration
        )
    }

    nonisolated static func decodingLanguage(for languageCode: String) -> String? {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto" else { return nil }
        return normalized
    }

    nonisolated static func decodingOptions(for languageCode: String) -> DecodingOptions {
        let language = decodingLanguage(for: languageCode)
        return DecodingOptions(
            task: .transcribe,
            language: language,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )
    }

    nonisolated static func acceptsSegment(averageLogProbability: Float, compressionRatio: Float) -> Bool {
        averageLogProbability.isFinite && compressionRatio.isFinite
            && averageLogProbability >= -1 && compressionRatio <= 2.4
    }

    // A conservative signal check, not a speech classifier. Require 100 ms of
    // non-DC audio above -60 dBFS, so digital silence, clicks, and dead input do
    // not reach the speech decoder. Quiet speech still passes this check.
    nonisolated static func containsUsableAudio(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        guard sampleRate > 0, !samples.isEmpty else { return false }
        let windowSize = max(sampleRate / 50, 1)
        let minimumActiveSamples = max(sampleRate / 10, 1)
        var activeSamples = 0
        for start in stride(from: 0, to: samples.count, by: windowSize) {
            let end = min(start + windowSize, samples.count)
            var sum = 0.0
            var sumSquares = 0.0
            for index in start..<end {
                let sample = Double(samples[index])
                guard sample.isFinite else { return false }
                sum += sample
                sumSquares += sample * sample
            }
            let count = Double(end - start)
            let mean = sum / count
            let variance = max(sumSquares / count - mean * mean, 0)
            if variance >= 0.000_001 {
                activeSamples += end - start
            }
        }
        return activeSamples >= minimumActiveSamples
    }
}

enum VoiceReadinessState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case cachedCold
    case warming(startedAt: Date)
    case ready(modelName: String)
    case failed(message: String)
}

@MainActor
protocol VoiceReadinessPreparing: AnyObject {
    var state: TranscriptionEngineState { get }

    func prepare(modelName: String) async throws
}

extension TranscriptionEngine: VoiceReadinessPreparing {}

@MainActor
final class VoiceReadinessCoordinator: ObservableObject {
    @Published private(set) var state: VoiceReadinessState = .notDownloaded

    private let modelManager: ModelManager
    private let preparer: VoiceReadinessPreparing
    private let cacheSummaryProvider: (String) -> ModelCacheSummary
    private var warmingTask: Task<Void, Never>?
    private var warmingModelName: String?
    private var warmingStartedAt: Date?
    private var failedAutoWarmModelName: String?

    init(
        modelManager: ModelManager,
        preparer: VoiceReadinessPreparing,
        cacheSummaryProvider: @escaping (String) -> ModelCacheSummary = ModelCacheStore.summary(for:)
    ) {
        self.modelManager = modelManager
        self.preparer = preparer
        self.cacheSummaryProvider = cacheSummaryProvider
        refreshFromCurrentState()
    }

    deinit {
        warmingTask?.cancel()
    }

    func refreshForForeground() {
        refreshFromCurrentState()
        warmPreferredModelIfPossible(reason: "foreground")
    }

    func refreshFromCurrentState() {
        let selectedModelName = modelManager.selectedModelName

        switch preparer.state {
        case .downloadingModel(let modelName, let progress) where modelName == selectedModelName:
            state = .downloading(progress: progress)
        case .loadingModel(let modelName) where modelName == selectedModelName:
            let startedAt = warmingStartedAt ?? Date()
            warmingStartedAt = startedAt
            state = .warming(startedAt: startedAt)
        case .ready(let modelName) where modelName == selectedModelName:
            warmingTask = nil
            warmingModelName = nil
            warmingStartedAt = nil
            failedAutoWarmModelName = nil
            state = .ready(modelName: modelName)
        case .failed(let message) where failedAutoWarmModelName == selectedModelName:
            state = .failed(message: message)
        default:
            state = cacheSummaryProvider(selectedModelName).isUsable ? .cachedCold : .notDownloaded
        }
    }

    func warmPreferredModelIfPossible(reason: String) {
        let selectedModelName = modelManager.selectedModelName
        refreshFromCurrentState()

        if case .ready = state { return }
        if case .downloading = state { return }
        if case .warming = state, warmingModelName == selectedModelName { return }
        guard cacheSummaryProvider(selectedModelName).isUsable else {
            state = .notDownloaded
            return
        }

        guard failedAutoWarmModelName != selectedModelName else {
            if case .failed = state {
                return
            }
            state = .failed(message: "Open Vyrra to try preparing again.")
            return
        }

        warmingTask?.cancel()
        warmingModelName = selectedModelName
        let startedAt = Date()
        warmingStartedAt = startedAt
        state = .warming(startedAt: startedAt)

        warmingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await preparer.prepare(modelName: selectedModelName)
                guard !Task.isCancelled else { return }
                warmingTask = nil
                warmingModelName = nil
                warmingStartedAt = nil
                failedAutoWarmModelName = nil
                state = .ready(modelName: selectedModelName)
            } catch {
                guard !Task.isCancelled else { return }
                warmingTask = nil
                warmingModelName = nil
                warmingStartedAt = nil
                failedAutoWarmModelName = selectedModelName
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func handlePreferredModelChanged() {
        warmingTask?.cancel()
        warmingTask = nil
        warmingModelName = nil
        warmingStartedAt = nil
        failedAutoWarmModelName = nil
        refreshForForeground()
    }

    func handleDownloadCompleted(model: SpeechModel) {
        handleDownloadCompleted(modelName: model.rawValue)
    }

    func handleDownloadCompleted(modelName: String) {
        guard modelName == modelManager.selectedModelName else {
            refreshFromCurrentState()
            return
        }

        failedAutoWarmModelName = nil
        warmPreferredModelIfPossible(reason: "downloadCompleted")
    }
}
