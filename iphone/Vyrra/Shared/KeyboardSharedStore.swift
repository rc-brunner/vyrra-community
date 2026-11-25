import Darwin
import Foundation
import notify

// Signals carry no data. Each process reads the coordinated App Group file,
// and its existing timer covers suspension or a missed notification.
enum KeyboardStoreChange: String {
    case command = "group.com.runnerconcepts.vyrra.keyboard.command"
    case payload = "group.com.runnerconcepts.vyrra.keyboard.payload"

    func post() { notify_post(rawValue) }
}

final class KeyboardStoreObservation {
    private var token: Int32 = -1

    init?(_ change: KeyboardStoreChange, onChange: @escaping () -> Void) {
        guard notify_register_dispatch(change.rawValue, &token, .main, { _ in onChange() }) == NOTIFY_STATUS_OK
        else { return nil }
    }

    deinit {
        if token >= 0 { notify_cancel(token) }
    }
}

struct KeyboardShortcutPayload: Codable, Equatable {
    let trigger: String
    let body: String
}

struct KeyboardPolishingModePayload: Codable, Equatable {
    let rawValue: String
    let title: String
}

enum KeyboardSessionState: String, Codable, Equatable {
    case ready
    case opening
    case warming
    case listening
    case paused
    case processing
    case insertReady
    case inserted
    case error
}

enum KeyboardVoiceReadinessState: String, Codable, Equatable {
    case notDownloaded
    case downloading
    case cachedCold
    case preparing
    case ready
    case needsAttention
}

struct KeyboardVoiceReadinessPayload: Codable, Equatable {
    let state: KeyboardVoiceReadinessState
    let detail: String?
    let updatedAt: Date
}

struct KeyboardSessionPayload: Codable, Equatable {
    let state: KeyboardSessionState
    let startedAt: Date?
    let resultText: String?
    let errorText: String?
    let updatedAt: Date
    let voiceReadiness: KeyboardVoiceReadinessPayload?
    let sessionID: String?
    let automaticInsertionRequestedAt: Date?

    init(
        state: KeyboardSessionState,
        startedAt: Date?,
        resultText: String?,
        errorText: String?,
        updatedAt: Date,
        voiceReadiness: KeyboardVoiceReadinessPayload? = nil,
        sessionID: String? = nil,
        automaticInsertionRequestedAt: Date? = nil
    ) {
        self.state = state
        self.startedAt = startedAt
        self.resultText = resultText
        self.errorText = errorText
        self.updatedAt = updatedAt
        self.voiceReadiness = voiceReadiness
        self.sessionID = sessionID
        self.automaticInsertionRequestedAt = automaticInsertionRequestedAt
    }

    static func ready(
        updatedAt: Date = Date(),
        voiceReadiness: KeyboardVoiceReadinessPayload? = nil
    ) -> KeyboardSessionPayload {
        KeyboardSessionPayload(
            state: .ready,
            startedAt: nil,
            resultText: nil,
            errorText: nil,
            updatedAt: updatedAt,
            voiceReadiness: voiceReadiness,
            sessionID: nil,
            automaticInsertionRequestedAt: nil
        )
    }
}

enum KeyboardSessionCommandType: String, Codable, Equatable {
    case start
    case finish
    case cancel
    case endKeyboardSession
}

struct KeyboardActivationPayload: Codable, Equatable {
    let id: String
    let expiresAt: Date?
    let updatedAt: Date

    func isCurrent(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return !id.isEmpty && (expiresAt.map { $0 > now } ?? true) && age >= -2
            && age <= VyrraSessionPolicy.keyboardHeartbeatWindow
    }
}

struct KeyboardPresencePayload: Codable, Equatable {
    let id: String
    let isVisible: Bool
    let updatedAt: Date

    func isCurrent(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return !id.isEmpty && isVisible && age >= -2
            && age <= VyrraSessionPolicy.keyboardHeartbeatWindow
    }
}

struct KeyboardSessionCommand: Codable, Equatable {
    let id: String
    let type: KeyboardSessionCommandType
    let requestedAt: Date
    let sessionID: String?
    let expiresAt: Date?

    init(
        id: String = UUID().uuidString,
        type: KeyboardSessionCommandType,
        requestedAt: Date = Date(),
        sessionID: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.requestedAt = requestedAt
        self.sessionID = sessionID
        self.expiresAt = expiresAt
    }
}

struct KeyboardSessionCommandAcknowledgment: Codable, Equatable {
    let commandID: String
    let accepted: Bool
}

struct KeyboardSharedPayload: Codable, Equatable {
    let latestDraft: String?
    let shortcuts: [KeyboardShortcutPayload]
    let session: KeyboardSessionPayload?
    let polishingMode: KeyboardPolishingModePayload?
    let activation: KeyboardActivationPayload?
    let commandAcknowledgment: KeyboardSessionCommandAcknowledgment?
    let updatedAt: Date

    init(
        latestDraft: String?,
        shortcuts: [KeyboardShortcutPayload],
        session: KeyboardSessionPayload?,
        polishingMode: KeyboardPolishingModePayload? = nil,
        activation: KeyboardActivationPayload? = nil,
        commandAcknowledgment: KeyboardSessionCommandAcknowledgment? = nil,
        updatedAt: Date
    ) {
        self.latestDraft = latestDraft
        self.shortcuts = shortcuts
        self.session = session
        self.polishingMode = polishingMode
        self.activation = activation
        self.commandAcknowledgment = commandAcknowledgment
        self.updatedAt = updatedAt
    }

    var hasInsertableContent: Bool {
        guard let latestDraft else { return !shortcuts.isEmpty }
        return !latestDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !shortcuts.isEmpty
    }
}

extension KeyboardSessionPayload {
    func collapsedIfStale(now: Date = Date(), staleInterval: TimeInterval? = nil) -> KeyboardSessionPayload {
        let staleInterval = staleInterval ?? state.defaultStaleInterval
        guard state.canBecomeStale,
              now.timeIntervalSince(updatedAt) > staleInterval
        else { return self }

        return .ready(updatedAt: now, voiceReadiness: voiceReadiness)
    }
}

enum KeyboardPrimaryAction: Equatable {
    case start
    case quickStart
    case attention
    case finish
    case insertResult
    case wait
}

enum KeyboardPrimaryActionResolver {
    static func action(
        for session: KeyboardSessionPayload,
        activation: KeyboardActivationPayload? = nil,
        now: Date = Date()
    ) -> KeyboardPrimaryAction {
        switch session.state {
        case .ready, .inserted:
            activation?.isCurrent(now: now) == true ? .start : .quickStart
        case .error:
            .attention
        case .listening, .paused:
            .finish
        case .insertReady:
            normalized(session.resultText) == nil
                ? (activation?.isCurrent(now: now) == true ? .start : .quickStart)
                : .insertResult
        case .opening, .warming, .processing:
            .wait
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum KeyboardSessionContinuity {
    static func automaticInsertionText(
        _ text: String,
        contextBeforeInput: String?,
        selectedText: String?
    ) -> String {
        guard selectedText?.isEmpty != false,
              let preceding = contextBeforeInput?.last,
              let first = text.first,
              first.isASCII, first.isLetter || first.isNumber,
              preceding.isASCII,
              preceding.isLetter || preceding.isNumber || ".,!?;:".contains(preceding)
        else { return text }
        return " " + text
    }

    static func commandTargetsKeyboardActivation(
        _ command: KeyboardSessionCommand,
        activation: KeyboardActivationPayload,
        now: Date = Date()
    ) -> Bool {
        guard command.type == .start || command.type == .endKeyboardSession,
              activation.isCurrent(now: now), command.sessionID == activation.id
        else { return false }
        return commandTargetsActiveSession(command, activeSessionID: activation.id, now: now)
    }

    static func completedSessionResult(
        latestDraft: String?,
        inMemoryResult: String?
    ) -> String? {
        normalized(latestDraft) ?? normalized(inMemoryResult)
    }

    static func preservingInsertedResult(
        candidate: KeyboardSessionPayload,
        existing: KeyboardSessionPayload?
    ) -> KeyboardSessionPayload {
        guard candidate.state == .insertReady,
              existing?.state == .inserted,
              let sessionID = normalized(candidate.sessionID),
              sessionID == normalized(existing?.sessionID)
        else {
            return candidate
        }

        return KeyboardSessionPayload(
            state: .inserted,
            startedAt: candidate.startedAt,
            resultText: candidate.resultText,
            errorText: nil,
            updatedAt: candidate.updatedAt,
            voiceReadiness: candidate.voiceReadiness,
            sessionID: sessionID,
            automaticInsertionRequestedAt: nil
        )
    }

    static func shouldAutomaticallyInsert(
        _ session: KeyboardSessionPayload,
        now: Date = Date()
    ) -> Bool {
        guard session.state == .insertReady,
              normalized(session.sessionID) != nil,
              normalized(session.resultText) != nil,
              let requestedAt = session.automaticInsertionRequestedAt
        else {
            return false
        }

        let age = now.timeIntervalSince(requestedAt)
        return age >= -2 && age <= VyrraSessionPolicy.automaticInsertionWindow
    }

    static func commandTargetsActiveSession(
        _ command: KeyboardSessionCommand,
        activeSessionID: String?,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince(command.requestedAt)
        guard age >= -2, age <= VyrraSessionPolicy.commandFreshnessWindow,
              command.expiresAt.map({ now < $0 }) ?? true else {
            return false
        }

        guard let commandSessionID = normalized(command.sessionID) else {
            return normalized(activeSessionID) != nil
        }

        return commandSessionID == normalized(activeSessionID)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct KeyboardSpaceTap: Equatable {
    let occurredAt: Date
    let expectedContextBeforeInput: String
    let expectedContextAfterInput: String
}

enum KeyboardDoubleSpacePeriodPolicy {
    static let maximumInterval: TimeInterval = 0.45

    static func shouldInsertPeriod(
        after tap: KeyboardSpaceTap?,
        contextBeforeInput: String?,
        contextAfterInput: String?,
        selectedText: String?,
        now: Date = Date()
    ) -> Bool {
        guard let tap,
              selectedText?.isEmpty != false,
              let contextBeforeInput,
              let contextAfterInput,
              contextBeforeInput == tap.expectedContextBeforeInput,
              contextAfterInput == tap.expectedContextAfterInput
        else {
            return false
        }

        let age = now.timeIntervalSince(tap.occurredAt)
        guard age >= 0, age <= maximumInterval, contextBeforeInput.hasSuffix(" ") else {
            return false
        }

        guard let precedingCharacter = contextBeforeInput.dropLast().last else {
            return false
        }
        return precedingCharacter.isLetter || precedingCharacter.isNumber
    }
}

extension KeyboardSessionState {
    var canBecomeStale: Bool {
        switch self {
        case .opening, .warming, .listening, .paused, .processing, .insertReady:
            return true
        case .ready, .inserted, .error:
            return false
        }
    }

    var defaultStaleInterval: TimeInterval {
        switch self {
        case .opening:
            return VyrraSessionPolicy.openingStaleInterval
        case .warming:
            return VyrraSessionPolicy.warmingStaleInterval
        case .listening, .paused:
            return VyrraSessionPolicy.listeningStaleInterval
        case .processing:
            return VyrraSessionPolicy.processingStaleInterval
        case .insertReady:
            return VyrraSessionPolicy.insertReadyStaleInterval
        case .ready, .inserted, .error:
            return .infinity
        }
    }
}

enum KeyboardDiagnosticEventType: String, Codable, Equatable {
    case keyboardAppeared
    case fullAccessState
    case payloadRead
    case primaryTapped
    case insertTapped
    case shortcutTapped
    case commandWriteSucceeded
    case commandWriteFailed
    case openAppRequested
    case openAppSucceeded
    case openAppFailed
    case appDeepLinkReceived
    case commandConsumed
    case commandIgnored
    case recordingStartRequested
    case recordingStartBlocked
}

struct KeyboardDiagnosticEntry: Codable, Equatable, Identifiable {
    let id: String
    let type: KeyboardDiagnosticEventType
    let detail: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        type: KeyboardDiagnosticEventType,
        detail: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.detail = detail
        self.createdAt = createdAt
    }
}

/// A single quantized loudness reading shared only with the keyboard extension.
/// Both processes reuse their file descriptor. The file contains no samples or text.
final class KeyboardLevelMeter {
    private let url: URL
    private let writable: Bool
    private var descriptor: Int32 = -1
    private var lastPublished: TimeInterval = -.infinity
    static let interval: TimeInterval = 1.0 / 12.0

    init?(writable: Bool, container: URL? = KeyboardSharedStore.defaultContainerURL()) {
        guard let container else { return nil }
        url = container.appendingPathComponent("Library/Caches/VyrraMeter/level", isDirectory: false)
        self.writable = writable
    }

    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    private func openIfNeeded() -> Bool {
        if descriptor >= 0 { return true }
        if writable {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            } catch { return false }
        }
        let flags = (writable ? O_CREAT | O_RDWR : O_RDONLY) | O_CLOEXEC | O_NOFOLLOW
        descriptor = url.withUnsafeFileSystemRepresentation { Darwin.open($0!, flags, mode_t(0o600)) }
        return descriptor >= 0
    }

    func publish(_ level: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard writable, level.isFinite, now - lastPublished >= Self.interval, openIfNeeded() else { return }
        let amplitude = UInt64((min(1, max(0, level)) * 255).rounded())
        var reading = (UInt64(now * 1000) << 8) | amplitude
        if pwrite(descriptor, &reading, 8, 0) == 8 { lastPublished = now }
    }

    func clear() {
        guard writable, descriptor >= 0 else { return }
        var zero: UInt64 = 0
        _ = pwrite(descriptor, &zero, 8, 0)
        lastPublished = -.infinity
    }

    func latest(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        var reading: UInt64 = 0
        guard openIfNeeded(), pread(descriptor, &reading, 8, 0) == 8, reading != 0 else { return 0 }
        let age = now - Double(reading >> 8) / 1000
        guard age >= 0, age < 0.35 else { return 0 }
        return Double(reading & 255) / 255
    }
}

enum KeyboardSharedStore {
    static let appGroupIdentifier = "group.com.runnerconcepts.vyrra"
    static let storageDirectoryName = "VyrraKeyboard"
    static let payloadFileName = "keyboard-payload.json"
    static let commandFileName = "keyboard-session-command.json"
    static let diagnosticsFileName = "keyboard-diagnostics.json"
    static let presenceFileName = "keyboard-presence.json"
    static let appearanceFileName = "keyboard-appearance.json"
    private static let diagnosticsLimit = 40
    private static let protectedWritingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUnlessOpen
    ]

    enum StoreError: LocalizedError {
        case sharedContainerUnavailable

        var errorDescription: String? {
            "The Vyrra keyboard shared container is unavailable."
        }
    }

    static func defaultContainerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func storageDirectoryURL(in containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(storageDirectoryName, isDirectory: true)
    }

    static func payloadURL(in containerURL: URL) -> URL {
        storageDirectoryURL(in: containerURL)
            .appendingPathComponent(payloadFileName, isDirectory: false)
    }

    static func commandURL(in containerURL: URL) -> URL {
        storageDirectoryURL(in: containerURL)
            .appendingPathComponent(commandFileName, isDirectory: false)
    }

    static func diagnosticsURL(in containerURL: URL) -> URL {
        storageDirectoryURL(in: containerURL)
            .appendingPathComponent(diagnosticsFileName, isDirectory: false)
    }

    static func readPresence(from containerURL: URL) throws -> KeyboardPresencePayload? {
        let url = storageDirectoryURL(in: containerURL).appendingPathComponent(presenceFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.keyboardShared.decode(KeyboardPresencePayload.self, from: Data(contentsOf: url))
    }

    static func readPresence() throws -> KeyboardPresencePayload? {
        guard let containerURL = defaultContainerURL() else { throw StoreError.sharedContainerUnavailable }
        return try readPresence(from: containerURL)
    }

    static func writePresence(_ presence: KeyboardPresencePayload, to containerURL: URL) throws {
        try prepareStorageDirectory(in: containerURL)
        let url = storageDirectoryURL(in: containerURL).appendingPathComponent(presenceFileName)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                // A disappearing keyboard in one app must not hide a newer
                // keyboard instance already visible in another app.
                if !presence.isVisible, let existing = try readPresence(from: containerURL),
                   existing.id != presence.id { return }
                let data = try JSONEncoder.keyboardShared.encode(presence)
                try data.write(to: coordinatedURL, options: protectedWritingOptions)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func writePresence(_ presence: KeyboardPresencePayload) throws {
        guard let containerURL = defaultContainerURL() else { throw StoreError.sharedContainerUnavailable }
        try writePresence(presence, to: containerURL)
    }

    static func readAppearance(from containerURL: URL) throws -> KeyboardAppearancePreferences {
        let url = storageDirectoryURL(in: containerURL).appendingPathComponent(appearanceFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return KeyboardAppearancePreferences() }
        return try JSONDecoder().decode(KeyboardAppearancePreferences.self, from: Data(contentsOf: url))
    }

    static func readAppearance() throws -> KeyboardAppearancePreferences {
        guard let containerURL = defaultContainerURL() else { throw StoreError.sharedContainerUnavailable }
        return try readAppearance(from: containerURL)
    }

    static func writeAppearance(_ appearance: KeyboardAppearancePreferences, to containerURL: URL) throws {
        try prepareStorageDirectory(in: containerURL)
        let url = storageDirectoryURL(in: containerURL).appendingPathComponent(appearanceFileName)
        try JSONEncoder().encode(appearance).write(to: url, options: protectedWritingOptions)
    }

    static func writeAppearance(_ appearance: KeyboardAppearancePreferences) throws {
        guard let containerURL = defaultContainerURL() else { throw StoreError.sharedContainerUnavailable }
        try writeAppearance(appearance, to: containerURL)
    }

    static func read(from containerURL: URL) throws -> KeyboardSharedPayload? {
        guard let url = existingURL(
            preferred: payloadURL(in: containerURL),
            legacy: legacyURL(for: payloadFileName, in: containerURL)
        ) else { return nil }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.keyboardShared.decode(KeyboardSharedPayload.self, from: data)
    }

    static func read(fileManager: FileManager = .default) throws -> KeyboardSharedPayload? {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try read(from: containerURL)
    }

    static func write(_ payload: KeyboardSharedPayload, to containerURL: URL) throws {
        try prepareStorageDirectory(in: containerURL)
        let url = payloadURL(in: containerURL)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let existing = try? Data(contentsOf: coordinatedURL)
                let existingSession = existing.flatMap {
                    try? JSONDecoder.keyboardShared.decode(KeyboardSharedPayload.self, from: $0).session
                }
                let sharedSession = payload.session.map {
                    KeyboardSessionContinuity.preservingInsertedResult(candidate: $0, existing: existingSession)
                }
                // App heartbeats and keyboard insertion acknowledgements may
                // race. Merge under the same cross-process write coordination.
                let merged = KeyboardSharedPayload(
                    latestDraft: payload.latestDraft, shortcuts: payload.shortcuts,
                    session: sharedSession, polishingMode: payload.polishingMode,
                    activation: payload.activation, commandAcknowledgment: payload.commandAcknowledgment,
                    updatedAt: payload.updatedAt
                )
                let data = try JSONEncoder.keyboardShared.encode(merged)
                try data.write(to: coordinatedURL, options: protectedWritingOptions)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func write(_ payload: KeyboardSharedPayload, fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try write(payload, to: containerURL)
        KeyboardStoreChange.payload.post()
    }

    /// Claims a completed phrase before inserting it. Every keyboard instance
    /// must use the same coordinated read/acknowledgement to avoid double insertion.
    static func claimInsertion(
        for expectedSession: KeyboardSessionPayload,
        in containerURL: URL,
        now: Date = Date()
    ) throws -> KeyboardSharedPayload? {
        try prepareStorageDirectory(in: containerURL)
        let url = payloadURL(in: containerURL)
        var coordinationError: NSError?
        var claimError: Error?
        var claimedPayload: KeyboardSharedPayload?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                guard expectedSession.state == .insertReady,
                      let expectedID = expectedSession.sessionID,
                      !expectedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let current = try read(from: containerURL),
                      let session = current.session,
                      session.collapsedIfStale(now: now).state == .insertReady,
                      session.sessionID == expectedID,
                      let result = session.resultText,
                      !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      result == expectedSession.resultText
                else { return }

                let acknowledged = KeyboardSharedPayload(
                    latestDraft: current.latestDraft,
                    shortcuts: current.shortcuts,
                    session: KeyboardSessionPayload(
                        state: .inserted, startedAt: session.startedAt,
                        resultText: result, errorText: nil, updatedAt: now,
                        voiceReadiness: session.voiceReadiness, sessionID: expectedID
                    ),
                    polishingMode: current.polishingMode,
                    activation: current.activation,
                    commandAcknowledgment: current.commandAcknowledgment,
                    updatedAt: now
                )
                try JSONEncoder.keyboardShared.encode(acknowledged)
                    .write(to: coordinatedURL, options: protectedWritingOptions)
                claimedPayload = acknowledged
            } catch { claimError = error }
        }
        if let coordinationError { throw coordinationError }
        if let claimError { throw claimError }
        return claimedPayload
    }

    static func claimInsertion(
        for expectedSession: KeyboardSessionPayload,
        fileManager: FileManager = .default
    ) throws -> KeyboardSharedPayload? {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try claimInsertion(for: expectedSession, in: containerURL)
    }

    @discardableResult
    static func bootstrapIfNeeded(
        in containerURL: URL,
        updatedAt: Date = Date()
    ) throws -> KeyboardSharedPayload {
        if let existingPayload = try read(from: containerURL) {
            return existingPayload
        }

        let payload = KeyboardSharedPayload(
            latestDraft: nil,
            shortcuts: [],
            session: .ready(updatedAt: updatedAt),
            updatedAt: updatedAt
        )
        try write(payload, to: containerURL)
        return payload
    }

    @discardableResult
    static func bootstrapIfNeeded(
        fileManager: FileManager = .default,
        updatedAt: Date = Date()
    ) throws -> KeyboardSharedPayload {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try bootstrapIfNeeded(in: containerURL, updatedAt: updatedAt)
    }

    static func clear(from containerURL: URL) throws {
        try removeIfPresent(payloadURL(in: containerURL))
        try removeIfPresent(legacyURL(for: payloadFileName, in: containerURL))
        try removeIfPresent(storageDirectoryURL(in: containerURL).appendingPathComponent(presenceFileName))
    }

    static func clear(fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try clear(from: containerURL)
    }

    static func readCommand(from containerURL: URL) throws -> KeyboardSessionCommand? {
        try readCommands(from: containerURL).first
    }

    private static func readCommands(from containerURL: URL) throws -> [KeyboardSessionCommand] {
        guard let url = existingURL(
            preferred: commandURL(in: containerURL),
            legacy: legacyURL(for: commandFileName, in: containerURL)
        ) else { return [] }

        let data = try Data(contentsOf: url)
        // Older versions stored a single command at either location.
        if let command = try? JSONDecoder.keyboardShared.decode(KeyboardSessionCommand.self, from: data) {
            return [command]
        }
        return try JSONDecoder.keyboardShared.decode([KeyboardSessionCommand].self, from: data)
    }

    static func readCommand(fileManager: FileManager = .default) throws -> KeyboardSessionCommand? {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try readCommand(from: containerURL)
    }

    static func writeCommand(_ command: KeyboardSessionCommand, to containerURL: URL) throws {
        _ = try updateCommands(in: containerURL) { commands in
            commands.append(command)
            return nil
        }
    }

    static func writeCommand(_ command: KeyboardSessionCommand, fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try writeCommand(command, to: containerURL)
        KeyboardStoreChange.command.post()
    }

    static func clearCommand(from containerURL: URL) throws {
        _ = try updateCommands(in: containerURL, replacingExisting: true) { commands in
            commands.removeAll()
            return nil
        }
    }

    static func clearCommand(fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try clearCommand(from: containerURL)
    }

    static func consumeCommand(from containerURL: URL) throws -> KeyboardSessionCommand? {
        // An empty poll need not acquire a write lock. A command arriving after
        // this check remains queued for the next poll.
        guard existingURL(
            preferred: commandURL(in: containerURL),
            legacy: legacyURL(for: commandFileName, in: containerURL)
        ) != nil else { return nil }
        return try updateCommands(in: containerURL) { commands in
            commands.isEmpty ? nil : commands.removeFirst()
        }
    }

    static func consumeCommand(fileManager: FileManager = .default) throws -> KeyboardSessionCommand? {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try consumeCommand(from: containerURL)
    }

    private static func updateCommands(
        in containerURL: URL,
        replacingExisting: Bool = false,
        _ update: (inout [KeyboardSessionCommand]) -> KeyboardSessionCommand?
    ) throws -> KeyboardSessionCommand? {
        try prepareStorageDirectory(in: containerURL)
        let url = commandURL(in: containerURL)
        var coordinationError: NSError?
        var updateError: Error?
        var consumedCommand: KeyboardSessionCommand?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                // Queue and consume under one cross-process lock. A rapid Cancel
                // followed by Start must retain both intents in that order.
                var commands = replacingExisting ? [] : try readCommands(from: containerURL)
                consumedCommand = update(&commands)
                if commands.isEmpty {
                    try removeIfPresent(coordinatedURL)
                } else {
                    try JSONEncoder.keyboardShared.encode(commands)
                        .write(to: coordinatedURL, options: protectedWritingOptions)
                }
                try removeIfPresent(legacyURL(for: commandFileName, in: containerURL))
            } catch { updateError = error }
        }
        if let coordinationError { throw coordinationError }
        if let updateError { throw updateError }
        return consumedCommand
    }

    static func readDiagnostics(from containerURL: URL) throws -> [KeyboardDiagnosticEntry] {
        guard let url = existingURL(
            preferred: diagnosticsURL(in: containerURL),
            legacy: legacyURL(for: diagnosticsFileName, in: containerURL)
        ) else { return [] }

        let data = try Data(contentsOf: url)
        return try decodeDiagnostics(from: data)
    }

    static func readDiagnostics(fileManager: FileManager = .default) throws -> [KeyboardDiagnosticEntry] {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try readDiagnostics(from: containerURL)
    }

    static func appendDiagnostic(_ entry: KeyboardDiagnosticEntry, to containerURL: URL) throws {
        let existingEntries = (try? readDiagnostics(from: containerURL)) ?? []
        let entries = Array((existingEntries + [entry]).suffix(diagnosticsLimit))
        try writeDiagnostics(entries, to: containerURL)
    }

    static func appendDiagnostic(_ entry: KeyboardDiagnosticEntry, fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try appendDiagnostic(entry, to: containerURL)
    }

    static func clearDiagnostics(from containerURL: URL) throws {
        try removeIfPresent(diagnosticsURL(in: containerURL))
        try removeIfPresent(legacyURL(for: diagnosticsFileName, in: containerURL))
    }

    static func clearDiagnostics(fileManager: FileManager = .default) throws {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        try clearDiagnostics(from: containerURL)
    }

    @discardableResult
    static func sanitizeDiagnostics(in containerURL: URL) throws -> Int {
        guard let url = existingURL(
            preferred: diagnosticsURL(in: containerURL),
            legacy: legacyURL(for: diagnosticsFileName, in: containerURL)
        ) else { return 0 }

        let data = try Data(contentsOf: url)
        let storedEntries = try JSONDecoder.keyboardShared.decode(
            [StoredKeyboardDiagnosticEntry].self,
            from: data
        )
        let currentEntries = storedEntries.compactMap(\.currentEntry)
        let removedCount = storedEntries.count - currentEntries.count

        if removedCount > 0 {
            try writeDiagnostics(currentEntries, to: containerURL)
        }
        return removedCount
    }

    @discardableResult
    static func sanitizeDiagnostics(fileManager: FileManager = .default) throws -> Int {
        guard let containerURL = defaultContainerURL(fileManager: fileManager) else {
            throw StoreError.sharedContainerUnavailable
        }
        return try sanitizeDiagnostics(in: containerURL)
    }

    private static func decodeDiagnostics(from data: Data) throws -> [KeyboardDiagnosticEntry] {
        try JSONDecoder.keyboardShared
            .decode([StoredKeyboardDiagnosticEntry].self, from: data)
            .compactMap(\.currentEntry)
    }

    private static func writeDiagnostics(
        _ entries: [KeyboardDiagnosticEntry],
        to containerURL: URL
    ) throws {
        let data = try JSONEncoder.keyboardShared.encode(entries)
        try prepareStorageDirectory(in: containerURL)
        try data.write(to: diagnosticsURL(in: containerURL), options: protectedWritingOptions)
    }

    private static func prepareStorageDirectory(in containerURL: URL) throws {
        try FileManager.default.createDirectory(
            at: storageDirectoryURL(in: containerURL),
            withIntermediateDirectories: true
        )
    }

    private static func legacyURL(for fileName: String, in containerURL: URL) -> URL {
        containerURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func existingURL(preferred: URL, legacy: URL) -> URL? {
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        return nil
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private struct StoredKeyboardDiagnosticEntry: Codable {
    let id: String
    let type: String
    let detail: String
    let createdAt: Date

    var currentEntry: KeyboardDiagnosticEntry? {
        guard let currentType = KeyboardDiagnosticEventType(rawValue: type) else { return nil }
        return KeyboardDiagnosticEntry(
            id: id,
            type: currentType,
            detail: detail,
            createdAt: createdAt
        )
    }
}

private extension JSONEncoder {
    static var keyboardShared: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var keyboardShared: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
