import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var audioRecorder: AudioRecorder
    @StateObject private var transcriptionEngine: TranscriptionEngine
    @StateObject private var modelManager: ModelManager
    @StateObject private var recordingDiagnostics: RecordingDiagnostics
    @StateObject private var voiceReadiness: VoiceReadinessCoordinator
    @StateObject private var liveActivityController: VyrraLiveActivityController
    @AppStorage("hasSeenReadiness") private var hasSeenReadiness = false
    @AppStorage(VyrraAccent.storageKey) private var accentRawValue = VyrraAccent.monochrome.rawValue
    @AppStorage(VyrraAppearance.storageKey) private var appearanceRawValue = VyrraAppearance.system.rawValue
    @State private var selectedTab: AppTab
    @State private var showsReadiness: Bool

    private let fixture: VisualFixture?

    init(fixture: VisualFixture? = VisualFixture.current) {
        let audioRecorder = AudioRecorder()
        let transcriptionEngine = TranscriptionEngine()
        let modelManager = ModelManager()
        let recordingDiagnostics = RecordingDiagnostics()
        let liveActivityController = VyrraLiveActivityController()

        _audioRecorder = StateObject(wrappedValue: audioRecorder)
        _transcriptionEngine = StateObject(wrappedValue: transcriptionEngine)
        _modelManager = StateObject(wrappedValue: modelManager)
        _recordingDiagnostics = StateObject(wrappedValue: recordingDiagnostics)
        _voiceReadiness = StateObject(
            wrappedValue: VoiceReadinessCoordinator(
                modelManager: modelManager,
                preparer: transcriptionEngine
            )
        )
        _liveActivityController = StateObject(wrappedValue: liveActivityController)

        self.fixture = fixture
        _selectedTab = State(initialValue: fixture?.defaultTab ?? .speak)
        _showsReadiness = State(initialValue: fixture?.shouldShowReadiness ?? false)
    }

    var body: some View {
        ZStack {
            VyrraTheme.pageBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                RecordView(fixture: fixture)
                    .environmentObject(audioRecorder)
                    .environmentObject(transcriptionEngine)
                    .environmentObject(modelManager)
                    .environmentObject(recordingDiagnostics)
                    .environmentObject(voiceReadiness)
                    .environmentObject(liveActivityController)
                    .tabItem {
                        Label("Speak", systemImage: "record.circle")
                    }
                    .tag(AppTab.speak)

                HistoryView(fixture: fixture)
                    .tabItem {
                        Label("Library", systemImage: "tray.full")
                    }
                    .tag(AppTab.library)

                PersonalizeView(fixture: fixture)
                    .environmentObject(transcriptionEngine)
                    .environmentObject(modelManager)
                    .environmentObject(recordingDiagnostics)
                    .tabItem {
                        Label("Personalize", systemImage: "person.text.rectangle")
                    }
                    .tag(AppTab.personalize)

                SettingsView(fixture: fixture)
                    .environmentObject(transcriptionEngine)
                    .environmentObject(modelManager)
                    .environmentObject(recordingDiagnostics)
                    .environmentObject(voiceReadiness)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(AppTab.settings)
            }
            // The tab bar keeps its system appearance: Liquid Glass with a
            // scroll edge effect on iOS 26, the default material on iOS 18.
        }
        // System chrome (tab bar, toolbars, default controls) stays monochrome.
        // The optional accent is applied only where views read `vyrraAccentColor`:
        // the Hold disc, the Copied mark, selected presets and a few fills.
        .tint(.primary)
        .preferredColorScheme(VyrraAppearance.colorScheme(for: appearanceRawValue))
        .environment(\.vyrraAccentColor, accentColor)
        .onAppear {
            consumePendingNavigation()
            voiceReadiness.refreshForForeground()
            guard shouldShowReadinessOnLaunch else { return }
            showsReadiness = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            consumePendingNavigation()
            voiceReadiness.refreshForForeground()
        }
        .onChange(of: modelManager.selectedModel) { _, _ in
            voiceReadiness.handlePreferredModelChanged()
        }
        .onOpenURL(perform: handleDeepLink)
        .fullScreenCover(isPresented: $showsReadiness) {
            ReadinessView {
                hasSeenReadiness = true
                voiceReadiness.refreshFromCurrentState()
                showsReadiness = false
            }
            .environmentObject(transcriptionEngine)
            .environmentObject(modelManager)
            .environmentObject(voiceReadiness)
        }
    }

    private var accentColor: Color {
        VyrraAccent.color(for: accentRawValue)
    }

    private func consumePendingNavigation() {
        guard fixture == nil, let tab = AppNavigationRequest.consumePendingTab() else { return }
        selectedTab = tab
    }

    private func handleDeepLink(_ url: URL) {
        guard fixture == nil, url.scheme == "vyrra" else { return }

        let targetTab: AppTab
        let action: AppLaunchAction?
        let route = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .compactMap({ $0?.isEmpty == false ? $0 : nil })
            .joined(separator: "/")
        try? KeyboardSharedStore.appendDiagnostic(
            KeyboardDiagnosticEntry(type: .appDeepLinkReceived, detail: route)
        )

        switch route {
        case "start-dictation":
            targetTab = .speak
            action = .startDictation
        case "keyboard/finish", "finish-dictation":
            targetTab = .speak
            action = .finishDictation
        case "keyboard/cancel", "cancel-dictation":
            targetTab = .speak
            action = .cancelDictation
        case "end-keyboard-session":
            targetTab = .speak
            action = .endKeyboardSession
        case "keyboard/tone":
            targetTab = .personalize
            action = nil
        default:
            targetTab = .speak
            action = nil
        }

        AppNavigationRequest.request(targetTab, action: action)
        selectedTab = targetTab
    }

    private var shouldShowReadinessOnLaunch: Bool {
        fixture == nil && !hasSeenReadiness && AppNavigationRequest.pendingAction() == nil
    }
}

#Preview {
    ContentView(fixture: .recordCopied)
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}

private enum PersonalizeSheet: String, Identifiable {
    case terms
    case shortcuts
    case output

    var id: String { rawValue }
}

private struct PersonalizeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var modelManager: ModelManager
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var vocabulary: [VocabularyEntry]
    @Query(sort: \SnippetEntry.createdAt, order: .reverse) private var snippets: [SnippetEntry]
    @State private var activeSheet: PersonalizeSheet?

    let fixture: VisualFixture?

    init(fixture: VisualFixture?) {
        self.fixture = fixture
        _activeSheet = State(initialValue: Self.initialSheet(for: fixture))
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    PersonalizeToolRow(
                        title: "Terms",
                        detail: "Names, brands, acronyms",
                        value: enabledVocabularyCount == 0 ? "" : "\(enabledVocabularyCount)",
                        systemImage: "book.closed"
                    ) {
                        activeSheet = .terms
                    }

                    Divider()
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 40)

                    PersonalizeToolRow(
                        title: "Shortcuts",
                        detail: "Reusable phrases",
                        value: enabledSnippetCount == 0 ? "" : "\(enabledSnippetCount)",
                        systemImage: "bolt"
                    ) {
                        activeSheet = .shortcuts
                    }

                    Divider()
                        .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 40)

                    PersonalizeToolRow(
                        title: "Output",
                        detail: "Style, language, model",
                        value: modelManager.polishingMode.title,
                        systemImage: "textformat"
                    ) {
                        activeSheet = .output
                    }
                }
                .padding(.horizontal, 16)
                .background(
                    VyrraTheme.quietFill,
                    in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                        .stroke(VyrraTheme.thinLine, lineWidth: 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 52)
            }
            .background(VyrraTheme.pageBackground)
            .navigationTitle("Personalize")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .terms:
                DictionaryView(fixture: fixture)
            case .shortcuts:
                SnippetsView(fixture: fixture)
            case .output:
                StyleView()
                    .environmentObject(modelManager)
            }
        }
    }

    private var enabledVocabularyCount: Int {
        switch fixture {
        case .dictionaryPopulated:
            VisualFixture.sampleVocabulary.filter(\.isEnabled).count
        default:
            vocabulary.filter(\.isEnabled).count
        }
    }

    private var enabledSnippetCount: Int {
        switch fixture {
        case .snippetsPopulated:
            VisualFixture.sampleSnippets.filter(\.isEnabled).count
        default:
            snippets.filter(\.isEnabled).count
        }
    }

    private static func initialSheet(for fixture: VisualFixture?) -> PersonalizeSheet? {
        switch fixture {
        case .dictionaryEmpty, .dictionaryPopulated:
            .terms
        case .snippetsEmpty, .snippetsPopulated:
            .shortcuts
        case .style:
            .output
        default:
            nil
        }
    }
}

private struct PersonalizeToolRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let detail: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(title)
                                .font(.headline)

                            Spacer(minLength: 10)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }

                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !value.isEmpty {
                            Text(value)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .frame(width: 26, height: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.headline)

                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer(minLength: 10)

                        if !value.isEmpty {
                            Text(value)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(VyrraPressButtonStyle(scale: 0.992, opacity: 0.9))
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [title, detail, value].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
