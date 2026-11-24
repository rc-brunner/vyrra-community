import Combine
import SwiftData
import SwiftUI
import UIKit

struct RecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var audioRecorder: AudioRecorder
    @EnvironmentObject private var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var recordingDiagnostics: RecordingDiagnostics
    @EnvironmentObject private var voiceReadiness: VoiceReadinessCoordinator
    @EnvironmentObject private var liveActivityController: VyrraLiveActivityController
    @Query(sort: \TranscriptionRecord.createdAt, order: .reverse) private var records: [TranscriptionRecord]
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var vocabularyEntries: [VocabularyEntry]
    @Query(sort: \SnippetEntry.createdAt, order: .reverse) private var snippetEntries: [SnippetEntry]
    private let fixture: VisualFixture?
    // Meter updates rebuild the parent view frequently. Keep one publisher so
    // its polling interval can elapse while the microphone is active.
    @State private var keyboardCommandTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    @State private var keyboardCommandObservation: KeyboardStoreObservation?

    @StateObject private var session: DictationSessionController
    @State private var toastMessage: String?
    @State private var toastID = UUID()
    @State private var busyStartedAt: Date?
    @State private var keyboardSessionStartedAt: Date?
    @State private var keyboardSessionID: String?
    @State private var quickAccessSessionRequestsInsertion = false
    @State private var automaticInsertionRequestedAt: Date?
    @State private var lastHandledKeyboardCommandID: String?
    @State private var keyboardCommandAcknowledgment: KeyboardSessionCommandAcknowledgment?
    @State private var openingKeyboardCommand: KeyboardSessionCommand?
    @State private var showsProfile = false
    @State private var showsKeyboardReturnGuide = false
    @State private var shouldShowReturnGuideWhenRecording = false
    @State private var shouldStartAfterModelPreparation = false
    @State private var preparedStartUsesQuickAccess = false
    @State private var showsKeyboardSessionConsent = false
    @State private var isEnablingKeyboardMode = false
    @State private var lastKeyboardHeartbeat = Date.distantPast
    @State private var lastKeyboardLiveActivityUpdate = Date.distantPast
    @AppStorage(KeyboardInactivityTimeout.defaultsKey) private var keyboardTimeout = KeyboardInactivityTimeout.fiveMinutes.rawValue
    @AppStorage(KeyboardInactivityTimeout.enabledKey) private var keyboardDictationEnabled = false
    @AppStorage(KeyboardInactivityTimeout.consentKey) private var keyboardConsentGranted = false
    @State private var profileImageData = VyrraProfileImageStore.loadData()

    init(fixture: VisualFixture? = nil) {
        self.fixture = fixture
        let initialPhase = fixture?.recordPhase ?? .idle
        let recoverableRecording = fixture == nil ? PendingRecordingStore.load() : nil
        _session = StateObject(
            wrappedValue: DictationSessionController(
                initialPhase: initialPhase,
                initialPolishedText: initialPhase == .copied ? fixture?.samplePolishedText ?? "" : "",
                initialRecoverableRecording: recoverableRecording
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VyrraTheme.pageBackground
                    .ignoresSafeArea()

                GeometryReader { proxy in
                    speakLayout(in: proxy)
                        .animation(phaseAnimation, value: displayPhase.animationID)
                }

                if let toastMessage {
                    ToastView(message: toastMessage)
                        .padding(.bottom, 104)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(ProductIdentity.publicName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button {
                            showsProfile = true
                        } label: {
                            if profileImageData != nil {
                                VyrraProfileAvatar(imageData: profileImageData, initials: "V", size: 34)
                            } else {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 34, height: 34)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open profile")

                        if shouldShowHeaderStatusPill {
                            VyrraStatusPill(title: headerStatus.title, icon: headerStatus.icon, tint: headerStatus.tint)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if shouldShowModelStorageBadge {
                        VyrraStatusPill(title: modelManager.selectedModel.storageLabel, icon: "internaldrive", tint: .secondary)
                    }
                }
            }
            .onAppear {
                if fixture == nil {
                    keyboardCommandObservation = KeyboardStoreObservation(.command) { consumeKeyboardCommandIfNeeded() }
                }
                profileImageData = VyrraProfileImageStore.loadData()
                voiceReadiness.refreshForForeground()
                syncBusyClock(for: displayPhase)
                syncKeyboardSessionClock(for: displayPhase)
                syncKeyboardSharedPayload()
                syncLiveActivity(for: displayPhase)
                consumePendingLaunchAction()
                resumeKeyboardModeIfNeeded()
            }
            .onDisappear { keyboardCommandObservation = nil }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background, audioRecorder.isStarting {
                    audioRecorder.endKeyboardSession()
                }
                guard newPhase == .active else { return }
                voiceReadiness.refreshForForeground()
                consumePendingLaunchAction()
                syncLiveActivity(for: displayPhase)
                resumeKeyboardModeIfNeeded()
            }
            .onChange(of: displayPhase) { oldPhase, newPhase in
                announcePhaseChange(from: oldPhase, to: newPhase)
                audioRecorder.setKeyboardPhraseProcessing(newPhase == .transcribing || newPhase == .processing)
                switch newPhase {
                case .error, .emptyTranscript, .microphoneDenied:
                    if audioRecorder.keyboardSession != nil { audioRecorder.endKeyboardSession() }
                default:
                    break
                }
                syncBusyClock(for: newPhase)
                syncKeyboardSessionClock(for: newPhase)
                syncKeyboardSharedPayload()
                syncLiveActivity(for: newPhase)
                if newPhase == .idle, modelIsReady {
                    startPreparedDictationIfNeeded()
                    resumeKeyboardModeIfNeeded()
                }
                if newPhase != .recording {
                    showsKeyboardReturnGuide = false
                }
                presentKeyboardReturnGuideIfNeeded(for: newPhase)
            }
            .onChange(of: transcriptionEngine.state) { _, newState in
                if case .ready = newState {
                    voiceReadiness.refreshFromCurrentState()
                    if displayPhase == .idle {
                        startPreparedDictationIfNeeded()
                        resumeKeyboardModeIfNeeded()
                    }
                } else if case .failed = newState {
                    shouldStartAfterModelPreparation = false
                    preparedStartUsesQuickAccess = false
                }
                syncKeyboardSharedPayload()
            }
            .onChange(of: voiceReadiness.state) { _, _ in
                syncKeyboardSharedPayload()
            }
            .onChange(of: audioRecorder.interruptionMessage) { _, message in
                session.handleInterruptionMessage(message)
            }
            .onChange(of: audioRecorder.keyboardResumeID) { _, _ in
                if case .error = session.phase, !session.hasRecoverableRecording {
                    resetKeyboardSessionIdentity()
                    session.phase = .idle
                }
                syncKeyboardSharedPayload()
            }
            .onChange(of: audioRecorder.maximumDurationReached) { _, reachedLimit in
                guard reachedLimit, displayPhase == .recording else { return }
                toast("5-minute limit reached")
                stopRecording()
            }
            .onChange(of: audioRecorder.keyboardSession) { _, _ in
                syncKeyboardSharedPayload()
                syncLiveActivity(for: displayPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppNavigationRequest.didRequestNavigation)) { _ in
                consumePendingLaunchAction()
            }
            .onReceive(keyboardCommandTimer) { _ in
                consumeKeyboardCommandIfNeeded()
                if audioRecorder.keyboardSession != nil,
                   Date().timeIntervalSince(lastKeyboardHeartbeat) >= 1 {
                    lastKeyboardHeartbeat = Date()
                    syncKeyboardSharedPayload()
                    if Date().timeIntervalSince(lastKeyboardLiveActivityUpdate) >= 30 {
                        lastKeyboardLiveActivityUpdate = Date()
                        syncLiveActivity(for: displayPhase)
                    }
                }
            }
            .alert("Enable keyboard dictation?", isPresented: $showsKeyboardSessionConsent) {
                Button("Enable Keyboard Dictation", action: enableKeyboardMode)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Vyrra keeps the microphone available so you can dictate from the keyboard. Audio between phrases is discarded. Your inactivity setting controls when it turns off; Never keeps it on until you stop it. Once enabled, opening Vyrra makes keyboard dictation ready again. Stop it at any time in Vyrra or the keyboard menu.")
            }
            .onChange(of: showsProfile) { _, isShowing in
                guard !isShowing else { return }
                profileImageData = VyrraProfileImageStore.loadData()
            }
            .sheet(isPresented: $showsProfile) {
                ProfileView()
                    .environmentObject(transcriptionEngine)
                    .environmentObject(modelManager)
                    .environmentObject(recordingDiagnostics)
            }
            .fullScreenCover(isPresented: $showsKeyboardReturnGuide) {
                KeyboardReturnGuideView(
                    finish: {
                        showsKeyboardReturnGuide = false
                        stopRecording()
                    },
                    cancel: {
                        showsKeyboardReturnGuide = false
                        cancelRecording()
                    }
                )
            }
        }
    }

    private var displayPhase: RecordingPhase {
        switch session.phase {
        case .idle, .modelPreparing, .modelDownloading:
            switch transcriptionEngine.state {
            case .downloadingModel(let modelName, let progress) where modelName == modelManager.selectedModelName:
                return .modelDownloading(progress)
            case .loadingModel(let modelName) where modelName == modelManager.selectedModelName:
                return .modelPreparing
            default:
                break
            }
        default:
            break
        }

        switch session.phase {
        case .processing, .modelPreparing, .modelDownloading:
            switch transcriptionEngine.state {
            case .downloadingModel(_, let progress):
                return .modelDownloading(progress)
            case .loadingModel:
                return .modelPreparing
            case .transcribing:
                return .transcribing
            default:
                break
            }
        default:
            break
        }

        return session.phase
    }

    private var modelIsReady: Bool {
        if case .ready(let modelName) = transcriptionEngine.state {
            return modelName == modelManager.selectedModelName
        }
        return false
    }

    private var modelIsReadyForUI: Bool {
        modelIsReady || fixture != nil
    }

    private var modelCacheSummary: ModelCacheSummary {
        ModelCacheStore.summary(for: modelManager.selectedModelName)
    }

    private var displayLevel: Double {
        if fixture == .recordRecording { return 0.62 }
        let adjustedLevel = min(max(audioRecorder.level * modelManager.waveformSensitivity, 0), 1)
        let gatedLevel = adjustedLevel < 0.025 ? 0 : adjustedLevel
        return pow(gatedLevel, 0.82)
    }

    private var waveformPreparationProgress: Double? {
        if case .modelDownloading(let progress) = displayPhase {
            return progress
        }

        return nil
    }

    private var waveformHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 72 : 64
    }

    private var preparationWaveformHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 88 : 80
    }

    private var activitySurfaceHeight: CGFloat {
        switch displayPhase {
        case .copied:
            dynamicTypeSize.isAccessibilitySize ? 74 : 96
        case .modelDownloading, .modelPreparing:
            preparationWaveformHeight
        case .recording:
            waveformHeight
        default:
            waveformHeight
        }
    }

    private var shouldUseScrollableSpeakLayout: Bool {
        if dynamicTypeSize.isAccessibilitySize { return true }

        // Errors carry a variable-length message and, for a saved recording,
        // an extra button. Every other state is one title and one short line.
        if case .error = displayPhase { return true }
        return false
    }

    private var bottomContentPadding: CGFloat {
        shouldUseScrollableSpeakLayout ? 132 : 92
    }

    @ViewBuilder
    private func speakLayout(in proxy: GeometryProxy) -> some View {
        let availableHeight = max(proxy.size.height - 28, 1)

        if shouldUseScrollableSpeakLayout {
            ScrollView(.vertical, showsIndicators: false) {
                speakContent
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: availableHeight, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, bottomContentPadding)
            }
            .id(displayPhase.animationID)
        } else {
            speakContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, bottomContentPadding)
                .frame(height: availableHeight, alignment: .center)
        }
    }

    @ViewBuilder
    private var speakContent: some View {
        VStack(spacing: contentSpacing) {
            if shouldShowPreparationSurface {
                ModelPreparationSurface(
                    title: preparationSurfaceTitle,
                    phase: displayPhase,
                    waveformHeight: preparationWaveformHeight,
                    waveformMotion: modelManager.waveformMotion,
                    cacheSummary: modelCacheSummary,
                    selectedModel: modelManager.selectedModel,
                    prepareError: session.prepareError,
                    progress: waveformPreparationProgress,
                    startsRecordingWhenReady: shouldStartAfterModelPreparation,
                    prepare: prepareModel
                )
            } else {
                activitySurface
                    .frame(height: activitySurfaceHeight)

                RecordStatusBlock(title: statusTitle, detail: statusDetail)
                    .equatable()

                statePanel

                if shouldShowTranscriptBeforeButton {
                    LastTranscriptPreview(title: nil, text: session.lastPolishedText, isProminent: true) {
                        ClipboardService.copy(session.lastPolishedText)
                        toast("Copied")
                        HapticManager.completed()
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }

                if shouldShowRecordButton {
                    if let fix = recoveryDisc {
                        Button(action: fix.action) {
                            RecordDiscFace(
                                title: fix.title,
                                systemImage: fix.systemImage,
                                tone: .ready,
                                diameter: recordButtonDiameter
                            )
                        }
                        .buttonStyle(RecordDiscButtonStyle())
                        .accessibilityLabel(fix.accessibilityLabel)
                        .accessibilityHint(fix.accessibilityHint)
                        .padding(.top, 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
                    } else {
                        RecordButton(
                            title: recordButtonTitle,
                            systemImage: recordButtonIcon,
                            isRecording: displayPhase == .recording,
                            isProcessing: false,
                            tone: buttonTone,
                            isEnabled: displayPhase.canRecord || displayPhase == .recording,
                            start: performPrimaryRecordingAction,
                            stop: stopRecording,
                            accessibilityLabelOverride: session.hasRecoverableRecording
                                ? "Retry saved recording"
                                : nil,
                            diameter: recordButtonDiameter
                        )
                        .disabled(!(displayPhase.canRecord || displayPhase == .recording))
                        .padding(.top, displayPhase == .copied ? 0 : 2)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
                    }
                }

                if shouldShowTranscriptAfterButton {
                    LastTranscriptPreview(title: nil, text: session.lastPolishedText, isProminent: false) {
                        ClipboardService.copy(session.lastPolishedText)
                        toast("Copied")
                        HapticManager.completed()
                    }
                }
                keyboardSessionControls
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Phase changes use one critically damped curve; under Reduce Motion
    /// they cross-fade (the transitions above fall back to opacity).
    private var phaseAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.32)
    }

    private var toastAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.28)
    }

    private var contentSpacing: CGFloat {
        switch displayPhase {
        case .copied:
            18
        case .recording:
            22
        default:
            20
        }
    }

    @ViewBuilder
    private var keyboardSessionControls: some View {
        if fixture == nil {
            if let activation = audioRecorder.keyboardSession {
                // The Mic on status stays visible for as long as the session
                // holds the microphone. How to dictate lives on the keyboard.
                VStack(spacing: 8) {
                    Label("Keyboard Session · Mic on", systemImage: "mic.fill")
                        .font(.footnote.weight(.semibold))
                    HStack {
                        if let expiresAt = activation.expiresAt {
                            Text("Turns off in")
                            Text(expiresAt, style: .relative)
                        } else {
                            Text(keyboardTimeout == KeyboardInactivityTimeout.never.rawValue ? "Until you stop" : "Ready while in use")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Stop Keyboard Session", systemImage: "mic.slash", action: endKeyboardMode)
                        .buttonStyle(.bordered)
                }
            } else if modelIsReady {
                Button("Enable Keyboard Session", systemImage: "keyboard") {
                    if keyboardConsentGranted {
                        enableKeyboardMode()
                    } else {
                        showsKeyboardSessionConsent = true
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!displayPhase.canRecord || session.hasRecoverableRecording || audioRecorder.isStarting)
            }
            // "Turn off when unused" lives in Settings › Keyboard, not here.
        }
    }

    private func enableKeyboardMode() {
        guard scenePhase == .active, displayPhase.canRecord, modelIsReady,
              !session.hasRecoverableRecording, !isEnablingKeyboardMode else { return }
        isEnablingKeyboardMode = true
        Task { @MainActor in
            defer { isEnablingKeyboardMode = false }
            do {
                try await audioRecorder.enableKeyboardSession()
                keyboardConsentGranted = true
                keyboardDictationEnabled = true
                resetKeyboardSessionIdentity()
                session.phase = .idle
                syncKeyboardSharedPayload()
                syncLiveActivity(for: displayPhase)
            } catch {
                session.phase = .error(error.localizedDescription)
                syncKeyboardSharedPayload()
            }
        }
    }

    private func endKeyboardMode() {
        keyboardDictationEnabled = false
        if displayPhase == .recording { stopRecording() }
        audioRecorder.endKeyboardSession()
        syncKeyboardSharedPayload()
        syncLiveActivity(for: displayPhase)
    }

    private func resumeKeyboardModeIfNeeded() {
        guard fixture == nil, keyboardConsentGranted, keyboardDictationEnabled,
              audioRecorder.keyboardSession == nil, !audioRecorder.isStarting,
              !audioRecorder.isRecording, !shouldStartAfterModelPreparation,
              displayPhase == .idle || displayPhase == .copied else { return }
        enableKeyboardMode()
    }

    @ViewBuilder
    private var activitySurface: some View {
        if displayPhase == .copied {
            CopiedSuccessMark()
                .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
        } else {
            VyrraWaveformPill(
                level: displayLevel,
                isActive: displayPhase == .recording,
                isMuted: displayPhase == .microphoneDenied || displayPhase == .offlineBeforeDownload,
                isPreparing: displayPhase.isBusy,
                preparationProgress: waveformPreparationProgress,
                motion: modelManager.waveformMotion,
                height: activitySurfaceHeight,
                accessibilityDescription: displayPhase.isBusy ? statusTitle : nil
            )
            .animation(.easeOut(duration: 0.12), value: displayLevel)
            .animation(.easeInOut(duration: 0.32), value: waveformPreparationProgress)
            .transition(.opacity)
        }
    }

    private var shouldShowPreparationSurface: Bool {
        guard !modelIsReadyForUI else { return false }

        switch displayPhase {
        case .idle, .modelDownloading, .modelPreparing:
            return true
        default:
            return false
        }
    }

    /// When recording can't start but one tap fixes it, the disc becomes that
    /// fix instead of a disabled control, so the screen has one action.
    private var recoveryDisc: (
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        action: () -> Void
    )? {
        switch displayPhase {
        case .microphoneDenied:
            ("Settings", "gearshape.fill", "Open Settings", "Opens Vyrra in the Settings app.", openAppSettings)
        case .needsMicrophone:
            ("Allow", "mic.fill", "Allow microphone", "Shows the microphone permission prompt.", { startRecording() })
        default:
            nil
        }
    }

    private var shouldShowTranscriptBeforeButton: Bool {
        !session.lastPolishedText.isEmpty && displayPhase == .copied
    }

    private var shouldShowTranscriptAfterButton: Bool {
        !session.lastPolishedText.isEmpty && displayPhase != .copied
    }

    private var shouldShowRecordButton: Bool {
        guard modelIsReadyForUI else { return false }
        return !displayPhase.isBusy
    }

    private var recordButtonDiameter: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 94 }
        if displayPhase == .copied { return 116 }
        return 132
    }

    private var shouldShowModelStorageBadge: Bool {
        switch displayPhase {
        case .modelDownloading, .modelPreparing, .modelUnavailable, .lowStorage, .offlineBeforeDownload:
            true
        default:
            shouldShowPreparationSurface
        }
    }

    private var shouldShowHeaderStatusPill: Bool {
        switch displayPhase {
        case .copied:
            false
        case .idle:
            false
        default:
            true
        }
    }

    private var headerStatus: (title: String, icon: String, tint: Color) {
        if shouldShowPreparationSurface {
            return ("Setup", "cpu", .primary)
        }

        return switch displayPhase {
        case .recording:
            ("Listening", "waveform", .primary)
        case .modelPreparing, .modelDownloading:
            ("Preparing", "cpu", .primary)
        case .transcribing:
            ("Transcribing", "waveform", .primary)
        case .processing:
            ("Processing", "ellipsis", .primary)
        case .copied:
            ("Copied", "checkmark.circle.fill", VyrraTheme.success)
        case .microphoneDenied, .needsMicrophone:
            ("Microphone", "mic.slash", VyrraTheme.warning)
        case .lowStorage:
            ("Storage", "internaldrive", VyrraTheme.warning)
        case .offlineBeforeDownload:
            ("Offline", "wifi.slash", VyrraTheme.warning)
        case .emptyTranscript:
            ("No Speech", "waveform.slash", VyrraTheme.warning)
        case .error:
            session.hasRecoverableRecording
                ? ("Saved", "waveform.badge.exclamationmark", .primary)
                : ("Retry", "exclamationmark.circle", VyrraTheme.danger)
        default:
            ("Ready", "circle.fill", .secondary)
        }
    }

    private var preparationSurfaceTitle: String {
        switch displayPhase {
        case .modelDownloading:
            "Downloading"
        case .modelPreparing:
            "Preparing"
        default:
            "Prepare"
        }
    }

    private var statusTitle: String {
        switch displayPhase {
        case .idle:
            "Ready"
        case .needsMicrophone:
            "Microphone Needed"
        case .microphoneDenied:
            "Microphone Off"
        case .modelUnavailable:
            "Model Needed"
        case .modelDownloading:
            "Downloading"
        case .modelPreparing:
            "Preparing"
        case .lowStorage:
            "Storage Needed"
        case .offlineBeforeDownload:
            "Connect First"
        case .recording:
            "Listening"
        case .transcribing:
            "Transcribing"
        case .processing:
            "Processing"
        case .copied:
            "Copied"
        case .emptyTranscript:
            "No Speech"
        case .error:
            session.hasRecoverableRecording ? "Recording Saved" : "Try Again"
        }
    }

    private var statusDetail: String? {
        switch displayPhase {
        case .idle:
            nil
        case .needsMicrophone:
            "Tap to allow."
        case .microphoneDenied:
            "Turn on Microphone for Vyrra."
        case .modelUnavailable:
            "Choose another model."
        case .modelDownloading(let progress):
            preparationStatusLine(progress: progress, startsRecordingWhenReady: shouldStartAfterModelPreparation)
        case .modelPreparing:
            preparationStatusLine(progress: nil, startsRecordingWhenReady: shouldStartAfterModelPreparation)
        case .lowStorage:
            // A no-break space keeps "626 MB" together at large text sizes.
            "Free up space for the \(modelManager.selectedModel.storageLabel.replacingOccurrences(of: " ", with: "\u{00A0}")) model."
        case .offlineBeforeDownload:
            "Needed once to download the model."
        case .recording:
            nil
        case .transcribing, .processing:
            nil
        case .copied:
            nil
        case .emptyTranscript:
            "Speak a little longer, mic uncovered."
        case .error(let message):
            session.hasRecoverableRecording ? "Transcription didn’t finish." : message
        }
    }

    private var buttonTone: RecordButtonTone {
        switch displayPhase {
        case .copied:
            .ready
        case .processing, .transcribing, .modelPreparing, .modelDownloading:
            .processing
        case .recording:
            .recording
        case .idle, .emptyTranscript, .error:
            .ready
        default:
            .disabled
        }
    }

    private var recordButtonTitle: String {
        if session.hasRecoverableRecording { return "Retry" }
        return displayPhase == .copied ? "Again" : displayPhase.buttonTitle
    }

    private var recordButtonIcon: String {
        if session.hasRecoverableRecording { return "arrow.clockwise" }
        return displayPhase == .copied ? "mic.fill" : displayPhase.buttonIcon
    }

    /// The only extra control under the status: discarding a saved recording.
    /// Every other state says what it needs in its one line, and the disc
    /// below is the action.
    @ViewBuilder
    private var statePanel: some View {
        if case .error = displayPhase, session.hasRecoverableRecording {
            Button("Discard recording", role: .destructive, action: discardRecoverableRecording)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
        }
    }

    private func syncBusyClock(for phase: RecordingPhase) {
        switch phase {
        case .modelDownloading, .modelPreparing, .transcribing, .processing:
            if busyStartedAt == nil {
                busyStartedAt = Date()
            }
        default:
            busyStartedAt = nil
        }
    }

    private func syncKeyboardSessionClock(for phase: RecordingPhase) {
        switch phase {
        case .recording, .copied:
            if keyboardSessionStartedAt == nil {
                keyboardSessionStartedAt = Date()
            }
            if keyboardSessionID == nil {
                keyboardSessionID = UUID().uuidString
            }
        case .error where session.hasRecoverableRecording:
            if keyboardSessionID == nil {
                keyboardSessionID = UUID().uuidString
            }
        case .modelDownloading, .modelPreparing, .transcribing, .processing:
            if keyboardSessionStartedAt == nil {
                keyboardSessionStartedAt = busyStartedAt ?? Date()
            }
            if keyboardSessionID == nil {
                keyboardSessionID = UUID().uuidString
            }
        case .idle where shouldStartAfterModelPreparation:
            break
        default:
            resetKeyboardSessionIdentity()
        }
    }

    private func syncLiveActivity(for phase: RecordingPhase) {
        guard fixture == nil else { return }
        liveActivityController.sync(
            phase: phase,
            startedAt: keyboardSessionStartedAt ?? busyStartedAt,
            keyboardSessionExpiresAt: audioRecorder.keyboardActivation?.expiresAt,
            keyboardSessionIsActive: audioRecorder.keyboardActivation != nil
        )
    }

    private func startRecording(
        preservingSessionIdentity: Bool = false,
        onStartCompleted: @escaping () -> Void = {}
    ) {
        toastMessage = nil
        if !preservingSessionIdentity {
            beginKeyboardSession(requestsAutomaticInsertion: false)
        }
        if !modelIsReady {
            recordKeyboardDiagnostic(.recordingStartBlocked, detail: "modelNotReady")
        } else if !displayPhase.canRecord {
            recordKeyboardDiagnostic(.recordingStartBlocked, detail: displayPhase.diagnosticName)
        } else {
            recordKeyboardDiagnostic(.recordingStartRequested, detail: "ready")
        }
        session.startRecording(
            audioRecorder: audioRecorder,
            transcriptionEngine: transcriptionEngine,
            modelManager: modelManager,
            cacheSummary: modelCacheSummary,
            modelIsReady: modelIsReady,
            clearDiagnostics: recordingDiagnostics.clear,
            onStartCompleted: onStartCompleted
        )
    }

    private func performPrimaryRecordingAction() {
        if session.hasRecoverableRecording {
            retryRecoverableRecording()
        } else {
            startRecording()
        }
    }

    private func stopRecording() {
        guard displayPhase == .recording else {
            recordKeyboardDiagnostic(.commandIgnored, detail: "finish:notRecording")
            return
        }
        session.stopRecording(
            audioRecorder: audioRecorder,
            transcriptionEngine: transcriptionEngine,
            configuration: dictationConfiguration,
            saveRecord: saveRecord,
            recordTiming: recordingDiagnostics.record,
            notifyCopied: {
                // The phase change already announces "Copied" with the text.
                toast("Copied", announces: false)
            },
            shareDraft: { text in
                if quickAccessSessionRequestsInsertion, automaticInsertionRequestedAt == nil {
                    automaticInsertionRequestedAt = Date()
                }
                syncKeyboardSharedPayload(latestDraft: text)
            }
        )
    }

    private func retryRecoverableRecording() {
        toastMessage = nil
        session.retryRecoverableRecording(
            transcriptionEngine: transcriptionEngine,
            configuration: dictationConfiguration,
            saveRecord: saveRecord,
            recordTiming: recordingDiagnostics.record,
            notifyCopied: {
                toast("Copied", announces: false)
            },
            shareDraft: { text in
                if quickAccessSessionRequestsInsertion, automaticInsertionRequestedAt == nil {
                    automaticInsertionRequestedAt = Date()
                }
                syncKeyboardSharedPayload(latestDraft: text)
            }
        )
    }

    private func discardRecoverableRecording() {
        session.discardRecoverableRecording()
        resetKeyboardSessionIdentity()
        syncKeyboardSharedPayload()
    }

    private func cancelRecording() {
        guard displayPhase == .recording else {
            recordKeyboardDiagnostic(.commandIgnored, detail: "cancel:notRecording")
            return
        }
        session.cancelRecording(audioRecorder: audioRecorder)
        resetKeyboardSessionIdentity()
        syncKeyboardSharedPayload()
    }

    private func prepareModel() {
        session.prepareModel(
            transcriptionEngine: transcriptionEngine,
            modelManager: modelManager,
            cacheSummary: modelCacheSummary
        )
    }

    private func consumePendingLaunchAction() {
        guard fixture == nil else { return }
        guard let action = AppNavigationRequest.consumePendingAction() else { return }
        handleLaunchAction(action)
    }

    private func consumeKeyboardCommandIfNeeded() {
        guard fixture == nil,
              scenePhase == .active || displayPhase == .recording || audioRecorder.keyboardActivation != nil
        else { return }
        guard let command = try? KeyboardSharedStore.consumeCommand() else { return }
        guard command.id != lastHandledKeyboardCommandID else {
            recordKeyboardDiagnostic(.commandIgnored, detail: command.type.rawValue)
            return
        }

        lastHandledKeyboardCommandID = command.id
        var accepted = false
        defer {
            if command.type != .endKeyboardSession {
                keyboardCommandAcknowledgment = .init(commandID: command.id, accepted: accepted)
                syncKeyboardSharedPayload()
            }
        }

        if command.type == .start || command.type == .endKeyboardSession {
            guard let activation = audioRecorder.keyboardActivation,
                  KeyboardSessionContinuity.commandTargetsKeyboardActivation(command, activation: activation)
            else {
                recordKeyboardDiagnostic(.commandIgnored, detail: "\(command.type.rawValue):expiredActivation")
                return
            }
            if command.type == .endKeyboardSession {
                endKeyboardMode()
            } else if displayPhase.canRecord, openingKeyboardCommand == nil,
                      !audioRecorder.isStarting, !session.hasRecoverableRecording {
                accepted = true
                beginKeyboardSession(requestsAutomaticInsertion: true)
                openingKeyboardCommand = command
                startRecording(preservingSessionIdentity: true) {
                    openingKeyboardCommand = nil
                    syncKeyboardSharedPayload()
                }
            }
            return
        }

        guard KeyboardSessionContinuity.commandTargetsActiveSession(
            command,
            activeSessionID: keyboardSessionID
        ) else {
            recordKeyboardDiagnostic(.commandIgnored, detail: "\(command.type.rawValue):stale")
            return
        }

        recordKeyboardDiagnostic(.commandConsumed, detail: command.type.rawValue)

        switch command.type {
        case .start, .endKeyboardSession:
            break
        case .finish:
            accepted = displayPhase == .recording
            handleLaunchAction(.finishDictation)
        case .cancel:
            accepted = displayPhase == .recording
            handleLaunchAction(.cancelDictation)
        }
    }

    private func handleLaunchAction(_ action: AppLaunchAction) {
        recordKeyboardDiagnostic(.commandConsumed, detail: action.rawValue)
        switch action {
        case .startDictation:
            beginRequestedDictation(usesQuickAccess: true)
        case .finishDictation:
            stopRecording()
        case .cancelDictation:
            cancelRecording()
        case .endKeyboardSession:
            endKeyboardMode()
        }
    }

    private func beginRequestedDictation(usesQuickAccess: Bool) {
        guard !session.hasRecoverableRecording else {
            toast("Retry saved recording first")
            syncKeyboardSharedPayload()
            return
        }

        beginKeyboardSession(requestsAutomaticInsertion: usesQuickAccess)

        guard modelIsReady else {
            shouldStartAfterModelPreparation = true
            preparedStartUsesQuickAccess = usesQuickAccess
            if modelCacheSummary.isUsable {
                prepareModel()
            } else {
                recordKeyboardDiagnostic(.recordingStartBlocked, detail: "modelNotDownloaded")
                toast("Download once to continue")
                syncKeyboardSharedPayload()
            }
            return
        }

        shouldShowReturnGuideWhenRecording = usesQuickAccess
        startRecording(preservingSessionIdentity: true)
    }

    private func startPreparedDictationIfNeeded() {
        guard shouldStartAfterModelPreparation else { return }
        shouldStartAfterModelPreparation = false
        shouldShowReturnGuideWhenRecording = preparedStartUsesQuickAccess
        preparedStartUsesQuickAccess = false
        if keyboardSessionID == nil {
            beginKeyboardSession(requestsAutomaticInsertion: shouldShowReturnGuideWhenRecording)
        }
        startRecording(preservingSessionIdentity: true)
    }

    private func presentKeyboardReturnGuideIfNeeded(for phase: RecordingPhase) {
        guard shouldShowReturnGuideWhenRecording,
              phase == .recording
        else { return }

        shouldShowReturnGuideWhenRecording = false
        showsKeyboardReturnGuide = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func syncKeyboardSharedPayload(latestDraft: String? = nil) {
        guard fixture == nil else { return }

        let latestText = latestDraft.flatMap(PersonalizationFormatter.normalizedOptional)
            ?? records.first.flatMap { PersonalizationFormatter.normalizedOptional($0.polishedText) }
        let shortcuts = snippetEntries
            .filter(\.isEnabled)
            .compactMap { entry -> KeyboardShortcutPayload? in
                guard let trigger = PersonalizationFormatter.normalizedOptional(entry.trigger),
                      let body = PersonalizationFormatter.normalizedOptional(entry.body)
                else { return nil }
                return KeyboardShortcutPayload(trigger: trigger, body: body)
            }

        let candidateSession = keyboardSessionPayload(latestDraft: latestDraft)
        let existingSession = (try? KeyboardSharedStore.read())?.session
        let sharedSession = KeyboardSessionContinuity.preservingInsertedResult(
            candidate: candidateSession,
            existing: existingSession
        )
        let payload = KeyboardSharedPayload(
            latestDraft: latestText,
            shortcuts: shortcuts,
            session: sharedSession,
            polishingMode: KeyboardPolishingModePayload(
                rawValue: modelManager.polishingMode.rawValue,
                title: keyboardTitle(for: modelManager.polishingMode)
            ),
            activation: audioRecorder.keyboardActivation,
            commandAcknowledgment: keyboardCommandAcknowledgment,
            updatedAt: Date()
        )
        try? KeyboardSharedStore.write(payload)
    }

    private func keyboardTitle(for mode: PolishingMode) -> String {
        switch mode {
        case .cleanUp:
            return "Clean"
        case .casual:
            return "Reply"
        case .notes:
            return "Note"
        default:
            return mode.title
        }
    }

    private var dictationConfiguration: DictationSessionConfiguration {
        DictationSessionConfiguration(
            modelName: modelManager.selectedModelName,
            languageCode: modelManager.selectedLanguageCode,
            polishingMode: modelManager.polishingMode,
            savesHistory: modelManager.savesHistory,
            vocabulary: vocabularyEntries.map(VocabularyReplacement.init(entry:)),
            snippets: snippetEntries.map(SnippetExpansion.init(entry:))
        )
    }

    private func saveRecord(_ record: TranscriptionRecord) {
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func recordKeyboardDiagnostic(_ type: KeyboardDiagnosticEventType, detail: String) {
        guard fixture == nil else { return }
        try? KeyboardSharedStore.appendDiagnostic(
            KeyboardDiagnosticEntry(type: type, detail: detail)
        )
    }

    private func keyboardSessionPayload(latestDraft: String?) -> KeyboardSessionPayload {
        let now = Date()
        let readiness = keyboardVoiceReadinessPayload(updatedAt: now)
        if let openingKeyboardCommand, displayPhase.canRecord {
            // The app may still be showing the previous phrase's result while
            // audio capture starts. Report the new phrase as opening.
            return KeyboardSessionPayload(
                state: .opening, startedAt: openingKeyboardCommand.requestedAt,
                resultText: nil, errorText: nil, updatedAt: openingKeyboardCommand.requestedAt,
                voiceReadiness: readiness, sessionID: keyboardSessionID
            )
        }
        let normalizedLatestDraft = latestDraft.flatMap(PersonalizationFormatter.normalizedOptional)
        let resultText = KeyboardSessionContinuity.completedSessionResult(
            latestDraft: normalizedLatestDraft,
            inMemoryResult: session.lastPolishedText
        )

        switch displayPhase {
        case .modelDownloading, .modelPreparing:
            return KeyboardSessionPayload(
                state: .warming,
                startedAt: keyboardSessionStartedAt ?? busyStartedAt ?? now,
                resultText: nil,
                errorText: modelManager.selectedModel.warmupExpectation,
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID
            )
        case .recording:
            return KeyboardSessionPayload(
                state: .listening,
                startedAt: keyboardSessionStartedAt ?? now,
                resultText: nil,
                errorText: nil,
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID
            )
        case .processing, .transcribing:
            return KeyboardSessionPayload(
                state: .processing,
                startedAt: keyboardSessionStartedAt ?? busyStartedAt ?? now,
                resultText: nil,
                errorText: nil,
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID
            )
        case .copied:
            return KeyboardSessionPayload(
                state: .insertReady,
                startedAt: keyboardSessionStartedAt,
                resultText: resultText,
                errorText: nil,
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID,
                automaticInsertionRequestedAt: automaticInsertionRequestedAt
            )
        case .emptyTranscript:
            return KeyboardSessionPayload(
                state: .error,
                startedAt: nil,
                resultText: nil,
                errorText: "No speech detected.",
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID
            )
        case .error(let message):
            return KeyboardSessionPayload(
                state: .error,
                startedAt: nil,
                resultText: nil,
                errorText: message,
                updatedAt: now,
                voiceReadiness: readiness,
                sessionID: keyboardSessionID
            )
        default:
            return .ready(updatedAt: now, voiceReadiness: readiness)
        }
    }

    private func beginKeyboardSession(requestsAutomaticInsertion: Bool) {
        keyboardSessionID = UUID().uuidString
        keyboardSessionStartedAt = nil
        quickAccessSessionRequestsInsertion = requestsAutomaticInsertion
        automaticInsertionRequestedAt = nil
    }

    private func resetKeyboardSessionIdentity() {
        keyboardSessionStartedAt = nil
        keyboardSessionID = nil
        quickAccessSessionRequestsInsertion = false
        automaticInsertionRequestedAt = nil
    }

    private func keyboardVoiceReadinessPayload(updatedAt: Date) -> KeyboardVoiceReadinessPayload {
        switch displayPhase {
        case .modelDownloading:
            return KeyboardVoiceReadinessPayload(
                state: .downloading,
                detail: "Preparing in Vyrra",
                updatedAt: updatedAt
            )
        case .modelPreparing:
            return KeyboardVoiceReadinessPayload(
                state: .preparing,
                detail: "Preparing in Vyrra",
                updatedAt: updatedAt
            )
        default:
            break
        }

        switch voiceReadiness.state {
        case .notDownloaded:
            return KeyboardVoiceReadinessPayload(
                state: .notDownloaded,
                detail: "Open Vyrra",
                updatedAt: updatedAt
            )
        case .downloading:
            return KeyboardVoiceReadinessPayload(
                state: .downloading,
                detail: "Preparing in Vyrra",
                updatedAt: updatedAt
            )
        case .cachedCold:
            return KeyboardVoiceReadinessPayload(
                state: .cachedCold,
                detail: "Preparing in Vyrra",
                updatedAt: updatedAt
            )
        case .warming:
            return KeyboardVoiceReadinessPayload(
                state: .preparing,
                detail: "Preparing in Vyrra",
                updatedAt: updatedAt
            )
        case .ready:
            return KeyboardVoiceReadinessPayload(
                state: .ready,
                detail: "Ready",
                updatedAt: updatedAt
            )
        case .failed:
            return KeyboardVoiceReadinessPayload(
                state: .needsAttention,
                detail: "Open Vyrra",
                updatedAt: updatedAt
            )
        }
    }

    private func announcePhaseChange(from oldPhase: RecordingPhase, to newPhase: RecordingPhase) {
        DictationAnnouncement.forTransition(
            from: oldPhase,
            to: newPhase,
            polishedText: session.lastPolishedText,
            hasRecoverableRecording: session.hasRecoverableRecording
        )?.post()
    }

    /// Shows a transient confirmation. VoiceOver hears it as an announcement
    /// and, while VoiceOver runs, the toast stays long enough to reach.
    private func toast(_ message: String, announces: Bool = true) {
        let id = UUID()
        toastID = id
        withAnimation(toastAnimation) {
            toastMessage = message
        }
        if announces {
            DictationAnnouncement(message: message, priority: .normal).post()
        }

        let duration: TimeInterval = UIAccessibility.isVoiceOverRunning ? 5 : 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard toastID == id else { return }
            // Leave along the same path and curve it entered on.
            withAnimation(toastAnimation) {
                toastMessage = nil
            }
        }
    }
}

private struct ModelPreparationSurface: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    let title: String
    let phase: RecordingPhase
    let waveformHeight: CGFloat
    let waveformMotion: WaveformMotion
    let cacheSummary: ModelCacheSummary
    let selectedModel: SpeechModel
    let prepareError: String?
    let progress: Double?
    let startsRecordingWhenReady: Bool
    let prepare: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if phase.isBusy {
                VyrraWaveformPill(
                    level: 0.08,
                    isActive: false,
                    isMuted: false,
                    isPreparing: true,
                    preparationProgress: progress,
                    motion: waveformMotion,
                    height: waveformHeight
                )
                .animation(.easeInOut(duration: 0.32), value: progress)
                .transition(.opacity)
            }

            RecordStatusBlock(title: title, detail: preparationDetail)
                .equatable()

            if let prepareError {
                Text(prepareError)
                    .font(.footnote)
                    .foregroundStyle(VyrraTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }

            if phase == .idle {
                Button(action: prepare) {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .accessibilityHint(accessibilityHint)
            }
        }
        .frame(maxWidth: 380)
    }

    private var primaryActionTitle: String {
        cacheSummary.isUsable ? "Prepare" : selectedModel.downloadActionTitle
    }

    private var preparationDetail: String? {
        switch phase {
        case .idle:
            if startsRecordingWhenReady {
                return cacheSummary.isUsable
                    ? "Prepare once. Recording starts when ready."
                    : "Download once. Recording starts when ready."
            }
            return cacheSummary.isUsable
                ? selectedModel.warmupExpectation
                : selectedModel.downloadExpectation
        case .modelDownloading, .modelPreparing:
            return preparationStatusLine(progress: progress, startsRecordingWhenReady: startsRecordingWhenReady)
        default:
            return nil
        }
    }

    private var primaryActionIcon: String {
        cacheSummary.isUsable ? "cpu" : "arrow.down.circle"
    }

    private var accessibilityHint: String {
        cacheSummary.isUsable
            ? "Prepares the speech model for dictation"
            : "Downloads the speech model. \(selectedModel.downloadExpectation)"
    }
}

/// The one line under "Downloading" or "Preparing": the percent when it's
/// known, then the one thing to do, or what happens next.
private func preparationStatusLine(progress: Double?, startsRecordingWhenReady: Bool) -> String {
    let next = startsRecordingWhenReady ? "Recording starts when ready." : "Keep Vyrra open."
    guard let progress else { return next }
    return "\(progress.formatted(.percent.precision(.fractionLength(0)))) · \(next)"
}

private struct RecordStatusBlock: View, Equatable {
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .contentTransition(.opacity)

            if let detail {
                Text(detail)
                    // Fixed-width digits keep a changing percent from jittering.
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: title)
    }
}

private struct CopiedSuccessMark: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.14))
                .frame(width: 62, height: 62)

            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct LastTranscriptPreview: View {
    let title: String?
    let text: String
    let isProminent: Bool
    let copy: () -> Void

    var body: some View {
        VyrraPanel {
            if let title {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(title, systemImage: "text.quote")
                            .font(.headline)

                        Spacer()

                        VyrraIconButton(systemName: "doc.on.doc", label: "Copy last transcript", action: copy)
                    }

                    transcriptText
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    transcriptText
                        .padding(.trailing, 58)

                    VyrraIconButton(systemName: "doc.on.doc", label: "Copy last transcript", action: copy)
                }
            }
        }
    }

    private var transcriptText: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isProminent ? .primary : .secondary)
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KeyboardReturnGuideView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let finish: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            VyrraTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Spacer()

                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Cancel dictation")
                }

                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "waveform")
                        .font(.system(size: 42, weight: .semibold))
                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                        .frame(width: 86, height: 86)
                        .background(VyrraTheme.quietFill, in: Circle())
                        .accessibilityHidden(true)

                    VStack(spacing: 12) {
                        Text("Listening")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text("Swipe right along the bottom")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    KeyboardReturnIllustration(reduceMotion: reduceMotion)
                        .frame(width: 230, height: 58)
                        .accessibilityHidden(true)
                }

                Spacer()

                Button(action: finish) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 72, height: 72)
                        .background(Color.primary, in: Circle())
                }
                .accessibilityLabel("Finish dictation")
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
    }
}

private struct KeyboardReturnIllustration: View {
    let reduceMotion: Bool

    @State private var offset: CGFloat = -72

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 190, height: 7)

            Image(systemName: "chevron.right")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
                .offset(x: reduceMotion ? 0 : offset, y: -18)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: false)) {
                offset = 72
            }
        }
    }
}

private extension RecordingPhase {
    var animationID: String {
        switch self {
        case .modelDownloading:
            "modelDownloading"
        case .error:
            "error"
        default:
            "\(self)"
        }
    }
}

#Preview {
    RecordView(fixture: .recordCopied)
        .environmentObject(AudioRecorder())
        .environmentObject(TranscriptionEngine())
        .environmentObject(ModelManager())
        .environmentObject(RecordingDiagnostics())
        .environmentObject(VyrraLiveActivityController())
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
