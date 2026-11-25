import AVFoundation
import Foundation
import UIKit

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case missingInputFormat
    case recordingNotActive
    case recordingAlreadyStarting
    case recordingStartTimedOut
    case recordingInterrupted(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required to record dictation."
        case .missingInputFormat:
            "No microphone input format was available."
        case .recordingNotActive:
            "No active recording was found."
        case .recordingAlreadyStarting:
            "The microphone is already starting."
        case .recordingStartTimedOut:
            "The microphone didn't respond. Check the audio route, then retry."
        case .recordingInterrupted(let message):
            message
        }
    }
}

struct RecordingResult {
    let url: URL
    let duration: TimeInterval
}

final class AudioRecorder: ObservableObject {
    static let temporaryRecordingPrefix = "Vyrra-"
    static let temporaryRecordingExtension = "caf"
    static let maximumRecordingDuration = VyrraSessionPolicy.maximumRecordingDuration
    private static let minimumLevelPublishInterval: TimeInterval = 1.0 / 50.0
    private static let recordingStartTimeout: TimeInterval = 12

    @Published private(set) var isRecording = false {
        didSet { if oldValue && !isRecording { keyboardMeter?.clear() } }
    }
    @Published private(set) var isStarting = false
    @Published private(set) var level: Double = 0
    @Published private(set) var interruptionMessage: String?
    @Published private(set) var maximumDurationReached = false
    @Published private(set) var keyboardSession: KeyboardActivationPayload?
    @Published private(set) var keyboardResumeID: UUID?

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var recordingStartDate: Date?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var maximumDurationWorkItem: DispatchWorkItem?
    private var keyboardEngine: AVAudioEngine?
    private let keyboardCapture = KeyboardPhraseCapture()
    private lazy var keyboardMeter = KeyboardLevelMeter(writable: true)
    private var keyboardSessionMonitor: Timer?
    private var keyboardInactivity = KeyboardInactivityTracker()
    private var keyboardPhraseIsProcessing = false
    private var keyboardEnabledAt: Date?
    private var keyboardSessionStopRequested = false
    private var keyboardInterruptedAt: Date?
    private var isPreparingKeyboardPhrase = false

    init() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification)
        }

        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioRouteChange(notification)
        }
    }

    deinit {
        let center = NotificationCenter.default
        if let interruptionObserver {
            center.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            center.removeObserver(routeChangeObserver)
        }
        levelTimer?.invalidate()
        maximumDurationWorkItem?.cancel()
        keyboardSessionMonitor?.invalidate()
        keyboardEngine?.stop()
        keyboardCapture.cancel()
    }

    var keyboardActivation: KeyboardActivationPayload? {
        guard let keyboardSession,
              keyboardSession.expiresAt.map({ $0 > Date() }) ?? true,
              keyboardEngine?.isRunning == true else { return nil }
        return KeyboardActivationPayload(
            id: keyboardSession.id,
            expiresAt: keyboardSession.expiresAt,
            updatedAt: Date()
        )
    }

    @MainActor
    func enableKeyboardSession() async throws {
        guard !isRecording, !isStarting else { throw AudioRecorderError.recordingAlreadyStarting }
        guard keyboardActivation == nil else { return }
        isStarting = true
        keyboardSessionStopRequested = false
        keyboardInterruptedAt = nil
        defer { isStarting = false }
        guard await requestMicrophonePermission() else { throw AudioRecorderError.microphoneDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
            guard !session.currentRoute.inputs.isEmpty, session.inputNumberOfChannels > 0 else {
                throw AudioRecorderError.missingInputFormat
            }
            let engine = try await Self.startKeyboardEngine(capture: keyboardCapture)
            guard !keyboardSessionStopRequested else {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
                throw AudioRecorderError.recordingInterrupted("Keyboard session was stopped.")
            }
            keyboardEngine = engine
            let now = Date()
            keyboardEnabledAt = now
            keyboardInactivity = KeyboardInactivityTracker()
            keyboardPhraseIsProcessing = false
            keyboardSession = KeyboardActivationPayload(
                id: UUID().uuidString,
                expiresAt: nil,
                updatedAt: now
            )
            interruptionMessage = nil
            maximumDurationReached = false
            startKeyboardMetering()
            startKeyboardSessionMonitoring()
        } catch {
            shutdownKeyboardEngine()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func endKeyboardSession() {
        keyboardSessionStopRequested = true
        keyboardInterruptedAt = nil
        if keyboardEngine != nil {
            keyboardCapture.cancel()
            recordingURL = nil
            recordingStartDate = nil
            isRecording = false
            level = 0
            maximumDurationWorkItem?.cancel()
            shutdownKeyboardEngine()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func checkKeyboardSessionHealth() {
        guard let keyboardSession else { return }
        guard keyboardEngine?.isRunning == true else {
            stopAndDiscardRecording(reason: "Keyboard session stopped because microphone input ended.")
            return
        }

        let now = Date()
        let timeout = KeyboardInactivityTimeout.current
        let keyboardIsVisible = (try? KeyboardSharedStore.readPresence())?.isCurrent(now: now) == true
        var deadline = keyboardInactivity.deadline(
            timeout: timeout,
            appIsActive: UIApplication.shared.applicationState != .background,
            keyboardIsVisible: keyboardIsVisible,
            phraseIsBusy: isRecording || isStarting || keyboardPhraseIsProcessing,
            now: now
        )
        if timeout == .immediately, let proposedDeadline = deadline, let keyboardEnabledAt {
            // Allow the initial app-to-keyboard handoff to finish.
            deadline = max(proposedDeadline, keyboardEnabledAt.addingTimeInterval(8))
        }
        if let deadline, deadline <= now {
            endKeyboardSession()
        } else if keyboardSession.expiresAt != deadline {
            self.keyboardSession = KeyboardActivationPayload(
                id: keyboardSession.id, expiresAt: deadline, updatedAt: now
            )
        }
    }

    func setKeyboardPhraseProcessing(_ isProcessing: Bool) {
        keyboardPhraseIsProcessing = isProcessing
    }

    private func startKeyboardSessionMonitoring() {
        keyboardSessionMonitor?.invalidate()
        let monitor = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkKeyboardSessionHealth()
        }
        keyboardSessionMonitor = monitor
        RunLoop.main.add(monitor, forMode: .common)
    }

    private func shutdownKeyboardEngine() {
        keyboardSessionMonitor?.invalidate()
        keyboardSessionMonitor = nil
        if let keyboardEngine {
            keyboardEngine.stop()
            keyboardEngine.inputNode.removeTap(onBus: 0)
        }
        keyboardEngine = nil
        keyboardSession = nil
        keyboardEnabledAt = nil
        keyboardInactivity = KeyboardInactivityTracker()
        keyboardPhraseIsProcessing = false
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func startKeyboardPhrase() throws {
        guard keyboardActivation != nil, let keyboardEngine else {
            endKeyboardSession()
            throw AudioRecorderError.recordingInterrupted("Enable a new keyboard session in Vyrra.")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.temporaryRecordingPrefix)\(UUID().uuidString).caf")
        try keyboardCapture.begin(at: url, format: keyboardEngine.inputNode.outputFormat(forBus: 0))
        recordingURL = url
        recordingStartDate = Date()
        isRecording = true
        level = 0
        maximumDurationReached = false
        interruptionMessage = nil
        scheduleMaximumDurationWatchdog()
    }

    private func startKeyboardMetering() {
        levelTimer?.invalidate()
        let timer = Timer(timeInterval: Self.minimumLevelPublishInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.level = self.isRecording ? self.keyboardCapture.level : 0
            if self.isRecording { self.keyboardMeter?.publish(self.level) }
        }
        levelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func startKeyboardEngine(capture: KeyboardPhraseCapture) async throws -> AVAudioEngine {
        try await withCheckedThrowingContinuation { continuation in
            let attempt = KeyboardEngineStartupAttempt(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
                    _ = attempt.resolve(.failure(AudioRecorderError.missingInputFormat))
                    return
                }
                input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                    capture.append(buffer)
                }
                do {
                    engine.prepare()
                    try engine.start()
                    if !attempt.resolve(.success(engine)) {
                        engine.stop()
                        input.removeTap(onBus: 0)
                    }
                } catch {
                    engine.stop()
                    input.removeTap(onBus: 0)
                    _ = attempt.resolve(.failure(error))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + recordingStartTimeout) {
                _ = attempt.resolve(.failure(AudioRecorderError.recordingStartTimedOut))
            }
        }
    }

    /// Starts a recording.
    ///
    /// `beforeCapture` runs on the main actor after permission and the audio
    /// session are ready and immediately before audio starts being kept, so
    /// "you're live" cues (VoiceOver speech, haptics) don't land in the
    /// recording. It is skipped when the start fails earlier.
    @MainActor
    func startRecording(publishToKeyboard: Bool = false, beforeCapture: @MainActor () async -> Void = {}) async throws {
        guard !isRecording else { return }
        guard !isStarting, !isPreparingKeyboardPhrase else { throw AudioRecorderError.recordingAlreadyStarting }
        if keyboardSession != nil {
            if keyboardActivation != nil {
                isPreparingKeyboardPhrase = true
                await beforeCapture()
                isPreparingKeyboardPhrase = false
            }
            try startKeyboardPhrase()
            return
        }
        interruptionMessage = nil
        maximumDurationReached = false

        let granted = await requestMicrophonePermission()
        guard granted else { throw AudioRecorderError.microphoneDenied }
        guard !isRecording else { return }
        guard !isStarting else { throw AudioRecorderError.recordingAlreadyStarting }
        isStarting = true
        defer { isStarting = false }

        let session = AVAudioSession.sharedInstance()
        // Vyrra captures only. Avoid opening an unnecessary playback route while
        // still allowing Bluetooth HFP microphones for hands-free dictation.
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        await beforeCapture()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.temporaryRecordingPrefix)\(UUID().uuidString)")
            .appendingPathExtension(Self.temporaryRecordingExtension)

        do {
            let recorder = try await Self.startRecorder(
                at: url,
                timeout: Self.recordingStartTimeout
            )
            recorder.isMeteringEnabled = true

            self.recorder = recorder
            recordingURL = url
            recordingStartDate = Date()
            isRecording = true
            level = 0.08
            startLevelMetering(publishToKeyboard: publishToKeyboard)
            scheduleMaximumDurationWatchdog()
        } catch {
            recorder?.stop()
            recorder = nil
            levelTimer?.invalidate()
            levelTimer = nil
            recordingURL = nil
            recordingStartDate = nil
            isRecording = false
            level = 0
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func startRecorder(
        at url: URL,
        timeout: TimeInterval
    ) async throws -> AVAudioRecorder {
        try await withCheckedThrowingContinuation { continuation in
            let attempt = RecorderStartupAttempt(continuation: continuation)

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let recorder = try AVAudioRecorder(
                        url: url,
                        settings: recordingSettings
                    )
                    guard recorder.prepareToRecord(), recorder.record() else {
                        throw AudioRecorderError.recordingInterrupted(
                            "The microphone could not start recording."
                        )
                    }

                    if !attempt.resolve(.success(recorder)) {
                        recorder.stop()
                        try? FileManager.default.removeItem(at: url)
                    }
                } catch {
                    _ = attempt.resolve(.failure(error))
                    try? FileManager.default.removeItem(at: url)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                _ = attempt.resolve(.failure(AudioRecorderError.recordingStartTimedOut))
            }
        }
    }

    func stopRecording() throws -> RecordingResult {
        if keyboardEngine != nil, isRecording {
            defer {
                maximumDurationWorkItem?.cancel()
                recordingURL = nil
                recordingStartDate = nil
                isRecording = false
                level = 0
                maximumDurationReached = false
                if keyboardActivation == nil { endKeyboardSession() }
            }
            let result = try keyboardCapture.finish()
            keyboardPhraseIsProcessing = true
            return result
        }
        guard isRecording,
              let recordingURL,
              let recordingStartDate,
              let recorder
        else {
            throw AudioRecorderError.recordingNotActive
        }

        maximumDurationWorkItem?.cancel()
        levelTimer?.invalidate()
        levelTimer = nil
        let duration = max(
            recorder.currentTime,
            Date().timeIntervalSince(recordingStartDate)
        )
        recorder.stop()
        self.recorder = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        self.recordingURL = nil
        self.recordingStartDate = nil
        isRecording = false
        level = 0
        maximumDurationReached = false

        return RecordingResult(url: recordingURL, duration: duration)
    }

    func cancelRecording() {
        if keyboardEngine != nil {
            keyboardCapture.cancel()
            maximumDurationWorkItem?.cancel()
            recordingURL = nil
            recordingStartDate = nil
            isRecording = false
            level = 0
            maximumDurationReached = false
            return
        }
        guard isRecording || recordingURL != nil || recorder?.isRecording == true else { return }

        maximumDurationWorkItem?.cancel()
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil

        let abandonedURL = recordingURL
        recordingURL = nil
        recordingStartDate = nil
        isRecording = false
        level = 0
        interruptionMessage = nil
        maximumDurationReached = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let abandonedURL {
            try? FileManager.default.removeItem(at: abandonedURL)
        }
    }

    private func scheduleMaximumDurationWatchdog() {
        maximumDurationWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.maximumDurationReached = true
        }
        maximumDurationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumRecordingDuration, execute: workItem)
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }
        if type == .began {
            if keyboardSession != nil,
               UserDefaults.standard.bool(forKey: KeyboardInactivityTimeout.enabledKey) {
                keyboardInterruptedAt = Date()
            }
            stopAndDiscardRecording(reason: "Recording stopped because audio was interrupted.")
        } else if let interruptedAt = keyboardInterruptedAt {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            guard options.contains(.shouldResume),
                  KeyboardInactivityTimeout.current.permitsResume(after: interruptedAt),
                  UserDefaults.standard.bool(forKey: KeyboardInactivityTimeout.enabledKey) else {
                keyboardInterruptedAt = nil
                return
            }
            Task { @MainActor [weak self] in
                guard let self, self.keyboardInterruptedAt == interruptedAt,
                      !self.isStarting, !self.isRecording else { return }
                do {
                    try await self.enableKeyboardSession()
                    // Restore availability, never an interrupted phrase.
                    self.keyboardResumeID = UUID()
                } catch {
                    self.interruptionMessage = "Open Vyrra to resume keyboard dictation."
                }
            }
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard isRecording || keyboardSession != nil,
              let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable, .categoryChange, .routeConfigurationChange:
            stopAndDiscardRecording(reason: "Recording stopped because the microphone route changed.")
        default:
            break
        }
    }

    private func stopAndDiscardRecording(reason: String) {
        guard isRecording || recordingURL != nil || recorder?.isRecording == true || keyboardSession != nil else { return }

        keyboardCapture.cancel()
        shutdownKeyboardEngine()

        maximumDurationWorkItem?.cancel()
        levelTimer?.invalidate()
        levelTimer = nil
        recorder?.stop()
        recorder = nil

        let abandonedURL = recordingURL
        recordingURL = nil
        recordingStartDate = nil
        isRecording = false
        level = 0
        maximumDurationReached = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let abandonedURL {
            try? FileManager.default.removeItem(at: abandonedURL)
        }

        interruptionMessage = reason
    }

    @discardableResult
    static func cleanupTemporaryRecordings(
        in directory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) -> Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removedCount = 0
        for url in urls where isVyrraTemporaryRecording(url) {
            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                continue
            }
        }
        return removedCount
    }

    private static func isVyrraTemporaryRecording(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(temporaryRecordingPrefix)
            && url.pathExtension == temporaryRecordingExtension
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false
    ]

    private func startLevelMetering(publishToKeyboard: Bool) {
        levelTimer?.invalidate()
        let timer = Timer(timeInterval: Self.minimumLevelPublishInterval, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()

            let decibels = Double(recorder.averagePower(forChannel: 0))
            let target = Self.normalizedMeterLevel(decibels: decibels)
            let smoothing = target > self.level ? 0.88 : 0.30
            self.level += (target - self.level) * smoothing
            if publishToKeyboard { self.keyboardMeter?.publish(self.level) }
        }
        levelTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func normalizedMeterLevel(decibels: Double) -> Double {
        guard decibels.isFinite, decibels > -80 else { return 0 }
        return min(max(pow(10, decibels / 20) * 5.0, 0), 1)
    }
}

// The engine stays available only during an explicitly enabled session. This
// gate discards input outside a requested phrase without creating an audio file.
final class KeyboardPhraseCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var url: URL?
    private var capturedFrames: AVAudioFramePosition = 0
    private var writeError: Error?
    private var meterLevel: Double = 0

    var level: Double {
        lock.lock()
        defer { lock.unlock() }
        return meterLevel
    }

    func begin(at url: URL, format: AVAudioFormat) throws {
        lock.lock()
        defer { lock.unlock() }
        guard file == nil else { throw AudioRecorderError.recordingAlreadyStarting }
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRecorderError.missingInputFormat
        }
        do {
            let file = try AVAudioFile(
                forWriting: url, settings: format.settings,
                commonFormat: format.commonFormat, interleaved: format.isInterleaved
            )
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
            )
            self.file = file
            self.url = url
            capturedFrames = 0
            writeError = nil
            meterLevel = 0
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, writeError == nil else { return }
        do {
            try file.write(from: buffer)
            capturedFrames += AVAudioFramePosition(buffer.frameLength)
            if let samples = buffer.floatChannelData?.pointee, buffer.frameLength > 0 {
                let step = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
                var sum: Double = 0
                for index in 0..<Int(buffer.frameLength) {
                    let value = Double(samples[index * step])
                    sum += value * value
                }
                let rms = sqrt(sum / Double(buffer.frameLength))
                meterLevel = min(max(rms * 5, 0), 1)
            }
        } catch {
            writeError = error
        }
    }

    func finish() throws -> RecordingResult {
        lock.lock()
        defer { lock.unlock() }
        guard let url, let file else { throw AudioRecorderError.recordingNotActive }
        let duration = Double(capturedFrames) / file.processingFormat.sampleRate
        self.file = nil
        self.url = nil
        capturedFrames = 0
        meterLevel = 0
        if let writeError {
            self.writeError = nil
            try? FileManager.default.removeItem(at: url)
            throw writeError
        }
        return RecordingResult(url: url, duration: duration)
    }

    func cancel() {
        lock.lock()
        let abandonedURL = url
        file = nil
        url = nil
        capturedFrames = 0
        writeError = nil
        meterLevel = 0
        lock.unlock()
        if let abandonedURL { try? FileManager.default.removeItem(at: abandonedURL) }
    }
}

private final class KeyboardEngineStartupAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AVAudioEngine, Error>?

    init(continuation: CheckedContinuation<AVAudioEngine, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resolve(_ result: Result<AVAudioEngine, Error>) -> Bool {
        lock.lock()
        guard let continuation else { lock.unlock(); return false }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}

private final class RecorderStartupAttempt: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AVAudioRecorder, Error>?

    init(continuation: CheckedContinuation<AVAudioRecorder, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resolve(_ result: Result<AVAudioRecorder, Error>) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()

        continuation.resume(with: result)
        return true
    }
}
