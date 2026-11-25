import Foundation
import UIKit

enum RecordingPhase: Equatable {
    case idle
    case needsMicrophone
    case microphoneDenied
    case modelUnavailable
    case modelDownloading(Double)
    case modelPreparing
    case lowStorage
    case offlineBeforeDownload
    case recording
    case transcribing
    case processing
    case copied
    case emptyTranscript
    case error(String)

    var isBusy: Bool {
        switch self {
        case .processing, .transcribing, .modelPreparing, .modelDownloading:
            true
        default:
            false
        }
    }

    var canRecord: Bool {
        switch self {
        case .idle, .copied, .emptyTranscript, .error:
            true
        default:
            false
        }
    }

    var buttonTitle: String {
        switch self {
        case .idle:
            "Hold"
        case .recording:
            "Release"
        case .processing, .transcribing, .modelPreparing, .modelDownloading:
            "Wait"
        case .copied:
            "Again"
        case .emptyTranscript, .error:
            "Retry"
        case .needsMicrophone:
            "Allow"
        case .microphoneDenied:
            "Settings"
        case .modelUnavailable, .lowStorage, .offlineBeforeDownload:
            "Paused"
        }
    }

    var buttonIcon: String {
        switch self {
        case .recording:
            "stop.fill"
        case .processing, .modelPreparing, .modelDownloading:
            "hourglass"
        case .transcribing:
            "waveform"
        case .copied:
            "checkmark"
        case .microphoneDenied, .needsMicrophone:
            "mic.slash"
        case .lowStorage:
            "internaldrive"
        case .offlineBeforeDownload:
            "wifi.slash"
        default:
            "mic.fill"
        }
    }

    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .needsMicrophone: "needsMicrophone"
        case .microphoneDenied: "microphoneDenied"
        case .modelUnavailable: "modelUnavailable"
        case .modelDownloading: "modelDownloading"
        case .modelPreparing: "modelPreparing"
        case .lowStorage: "lowStorage"
        case .offlineBeforeDownload: "offlineBeforeDownload"
        case .recording: "recording"
        case .transcribing: "transcribing"
        case .processing: "processing"
        case .copied: "copied"
        case .emptyTranscript: "emptyTranscript"
        case .error: "error"
        }
    }
}

struct DictationSessionConfiguration {
    let modelName: String
    let languageCode: String
    let polishingMode: PolishingMode
    let savesHistory: Bool
    let vocabulary: [VocabularyReplacement]
    let snippets: [SnippetExpansion]
}

enum DictationSessionResultBuilder {
    static func polishedText(
        rawText: String,
        mode: PolishingMode,
        vocabulary: [VocabularyReplacement],
        snippets: [SnippetExpansion]
    ) throws -> String {
        let polishedText = TextPolisher(
            mode: mode,
            vocabulary: vocabulary,
            snippets: snippets
        ).polish(rawText)

        guard !polishedText.isEmpty else {
            throw TranscriptionEngineError.emptyTranscript
        }

        return polishedText
    }
}

@MainActor
final class DictationSessionController: ObservableObject {
    @Published var phase: RecordingPhase
    @Published var lastPolishedText: String
    @Published var prepareError: String?
    @Published private(set) var recoverableRecording: PendingRecordingSnapshot?

    private var processingBackgroundTask = UIBackgroundTaskIdentifier.invalid

    init(
        initialPhase: RecordingPhase = .idle,
        initialPolishedText: String = "",
        initialRecoverableRecording: PendingRecordingSnapshot? = nil
    ) {
        self.phase = initialPhase == .idle && initialRecoverableRecording != nil
            ? .error("Your recording is saved on this device.")
            : initialPhase
        self.lastPolishedText = initialPolishedText
        self.recoverableRecording = initialRecoverableRecording
    }

    var hasRecoverableRecording: Bool {
        recoverableRecording != nil
    }

    static func initialPreparationPhase(cacheSummary: ModelCacheSummary) -> RecordingPhase {
        cacheSummary.isUsable ? .modelPreparing : .modelDownloading(0)
    }

    func handleInterruptionMessage(_ message: String?) {
        guard let message, phase == .recording else { return }
        phase = .error(message)
        HapticManager.warning()
    }

    func prepareModel(
        transcriptionEngine: TranscriptionEngine,
        modelManager: ModelManager,
        cacheSummary: ModelCacheSummary
    ) {
        guard !phase.isBusy else { return }
        prepareError = nil

        if !cacheSummary.isUsable,
           !ModelCacheStore.hasEnoughStorage(forModelBytes: modelManager.selectedModel.estimatedStorageBytes) {
            phase = .lowStorage
            HapticManager.warning()
            return
        }

        phase = Self.initialPreparationPhase(cacheSummary: cacheSummary)

        Task { @MainActor in
            do {
                try await transcriptionEngine.prepare(modelName: modelManager.selectedModelName)
                phase = .idle
                HapticManager.completed()
            } catch {
                prepareError = error.localizedDescription
                phase = .idle
                HapticManager.error()
            }
        }
    }

    func startRecording(
        audioRecorder: AudioRecorder,
        transcriptionEngine: TranscriptionEngine,
        modelManager: ModelManager,
        cacheSummary: ModelCacheSummary,
        modelIsReady: Bool,
        publishToKeyboard: Bool = false,
        clearDiagnostics: @escaping () -> Void,
        onStartCompleted: @escaping () -> Void = {}
    ) {
        guard phase.canRecord else {
            onStartCompleted()
            return
        }
        if let recoverableRecording,
           !PendingRecordingStore.isRetainable(createdAt: recoverableRecording.createdAt) {
            clearRecoverableRecording(removingAudio: true)
        }
        guard recoverableRecording == nil else {
            phase = .error("Retry or discard the saved recording first.")
            HapticManager.warning()
            onStartCompleted()
            return
        }
        guard modelIsReady else {
            prepareModel(
                transcriptionEngine: transcriptionEngine,
                modelManager: modelManager,
                cacheSummary: cacheSummary
            )
            onStartCompleted()
            return
        }

        Task { @MainActor in
            defer { onStartCompleted() }
            do {
                try await audioRecorder.startRecording(publishToKeyboard: publishToKeyboard, beforeCapture: {
                    // Complete the start cues before retaining the first audio buffer.
                    await DictationAnnouncement.recordingStarted.postAndWaitUntilSpoken()
                    HapticManager.recordingStarted()
                    await DictationSound.engageBeforeCapture()
                })
                phase = .recording
                lastPolishedText = ""
                prepareError = nil
                clearDiagnostics()
            } catch AudioRecorderError.microphoneDenied {
                phase = .microphoneDenied
                HapticManager.error()
            } catch {
                phase = .error(error.localizedDescription)
                HapticManager.error()
            }
        }
    }

    func stopRecording(
        audioRecorder: AudioRecorder,
        transcriptionEngine: TranscriptionEngine,
        configuration: DictationSessionConfiguration,
        saveRecord: @escaping (TranscriptionRecord) -> Void,
        recordTiming: @escaping (RecordingTimingSummary) -> Void,
        notifyCopied: @escaping () -> Void,
        shareDraft: @escaping (String) -> Void
    ) {
        guard phase == .recording else { return }

        let releasedAt = Date()
        beginProcessingBackgroundTask()
        do {
            let result = try audioRecorder.stopRecording()
            let capturedAt = Date()
            DictationSound.releaseAfterCapture()
            let recoverableResult: PendingRecordingSnapshot
            do {
                recoverableResult = try PendingRecordingStore.stage(
                    result,
                    createdAt: capturedAt
                )
            } catch {
                // The in-memory URL remains recoverable for this app session if
                // persistent staging is temporarily unavailable.
                recoverableResult = PendingRecordingSnapshot(
                    result: result,
                    createdAt: capturedAt
                )
            }
            recoverableRecording = recoverableResult
            phase = .processing

            Task { @MainActor in
                await processRecording(
                    recoverableResult.result,
                    releasedAt: releasedAt,
                    transcriptionEngine: transcriptionEngine,
                    configuration: configuration,
                    saveRecord: saveRecord,
                    recordTiming: recordTiming,
                    notifyCopied: notifyCopied,
                    shareDraft: shareDraft
                )
            }
        } catch {
            endProcessingBackgroundTask()
            phase = .error(error.localizedDescription)
            HapticManager.error()
        }
    }

    func retryRecoverableRecording(
        transcriptionEngine: TranscriptionEngine,
        configuration: DictationSessionConfiguration,
        saveRecord: @escaping (TranscriptionRecord) -> Void,
        recordTiming: @escaping (RecordingTimingSummary) -> Void,
        notifyCopied: @escaping () -> Void,
        shareDraft: @escaping (String) -> Void
    ) {
        guard !phase.isBusy, let recoverableRecording else { return }
        guard PendingRecordingStore.isRetainable(createdAt: recoverableRecording.createdAt) else {
            clearRecoverableRecording(removingAudio: true)
            phase = .error("The saved recording expired.")
            HapticManager.warning()
            return
        }
        guard FileManager.default.fileExists(atPath: recoverableRecording.result.url.path) else {
            clearRecoverableRecording(removingAudio: false)
            phase = .error("The saved recording is no longer available.")
            HapticManager.error()
            return
        }

        let retryStartedAt = Date()
        beginProcessingBackgroundTask()
        phase = .processing

        Task { @MainActor in
            await processRecording(
                recoverableRecording.result,
                releasedAt: retryStartedAt,
                transcriptionEngine: transcriptionEngine,
                configuration: configuration,
                saveRecord: saveRecord,
                recordTiming: recordTiming,
                notifyCopied: notifyCopied,
                shareDraft: shareDraft
            )
        }
    }

    func discardRecoverableRecording() {
        guard recoverableRecording != nil else { return }
        clearRecoverableRecording(removingAudio: true)
        phase = .idle
        lastPolishedText = ""
        HapticManager.warning()
    }

    func cancelRecording(audioRecorder: AudioRecorder) {
        guard phase == .recording else { return }
        audioRecorder.cancelRecording()
        DictationSound.releaseAfterCapture()
        phase = .idle
        lastPolishedText = ""
        HapticManager.warning()
    }

    private func processRecording(
        _ result: RecordingResult,
        releasedAt: Date,
        transcriptionEngine: TranscriptionEngine,
        configuration: DictationSessionConfiguration,
        saveRecord: @escaping (TranscriptionRecord) -> Void,
        recordTiming: @escaping (RecordingTimingSummary) -> Void,
        notifyCopied: @escaping () -> Void,
        shareDraft: @escaping (String) -> Void
    ) async {
        defer { endProcessingBackgroundTask() }

        do {
            let transcriptionResult = try await transcriptionEngine.transcribe(
                audioURL: result.url,
                modelName: configuration.modelName,
                languageCode: configuration.languageCode
            )
            let rawText = transcriptionResult.text

            let polishAndCopyStartedAt = Date()
            let polishedText = try DictationSessionResultBuilder.polishedText(
                rawText: rawText,
                mode: configuration.polishingMode,
                vocabulary: configuration.vocabulary,
                snippets: configuration.snippets
            )

            ClipboardService.copy(polishedText)
            let polishAndCopyDuration = Date().timeIntervalSince(polishAndCopyStartedAt)
            lastPolishedText = polishedText
            phase = .copied
            shareDraft(polishedText)
            notifyCopied()
            HapticManager.completed()
            recordTiming(
                RecordingTimingSummary(
                    capturedAt: Date(),
                    recordingDuration: result.duration,
                    modelPrepareDuration: transcriptionResult.modelPrepareDuration,
                    transcriptionDuration: transcriptionResult.transcriptionDuration,
                    polishAndCopyDuration: polishAndCopyDuration,
                    releaseToCopiedDuration: Date().timeIntervalSince(releasedAt)
                )
            )

            if configuration.savesHistory {
                saveRecord(
                    TranscriptionRecord(
                        rawText: rawText,
                        polishedText: polishedText,
                        duration: result.duration,
                        modelName: configuration.modelName,
                        polishingMode: configuration.polishingMode
                    )
                )
            }
            clearRecoverableRecording(removingAudio: true)
        } catch TranscriptionEngineError.emptyTranscript {
            phase = .emptyTranscript
            HapticManager.warning()
            clearRecoverableRecording(removingAudio: true)
        } catch {
            phase = .error(error.localizedDescription)
            HapticManager.error()
        }
    }

    private func clearRecoverableRecording(removingAudio: Bool) {
        let audioURL = recoverableRecording?.result.url
        recoverableRecording = nil

        guard removingAudio else { return }
        try? PendingRecordingStore.discard()
        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    private func beginProcessingBackgroundTask() {
        endProcessingBackgroundTask()
        processingBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Finish Vyrra Dictation"
        ) { [weak self] in
            Task { @MainActor in
                self?.endProcessingBackgroundTask()
            }
        }
    }

    private func endProcessingBackgroundTask() {
        guard processingBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(processingBackgroundTask)
        processingBackgroundTask = .invalid
    }
}
