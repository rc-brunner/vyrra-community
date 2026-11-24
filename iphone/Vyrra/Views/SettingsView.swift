import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var recordingDiagnostics: RecordingDiagnostics
    @EnvironmentObject private var voiceReadiness: VoiceReadinessCoordinator
    @Query(sort: \TranscriptionRecord.createdAt, order: .reverse) private var records: [TranscriptionRecord]
    @Query(sort: \NoteFolder.name) private var folders: [NoteFolder]
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var vocabularyEntries: [VocabularyEntry]
    @Query(sort: \SnippetEntry.createdAt, order: .reverse) private var snippetEntries: [SnippetEntry]
    @State private var showsClearConfirmation = false
    @State private var showsAcknowledgements = false
    @State private var modelCacheSummaries = Self.makeModelCacheSummaries()
    @State private var activeModelDownload: SpeechModel?
    @State private var modelStorageError: String?
    @State private var dataExportError: String?
    @State private var exportShare: SettingsExportShare?
    @State private var modelDeleteTarget: SpeechModel?
    @State private var showsDeleteModelConfirmation = false
    @State private var showsClearClipboardConfirmation = false
    @State private var showsClearKeyboardDataConfirmation = false
    @State private var showsClearModelDownloadsConfirmation = false
    @State private var showsProfile = false
    @State private var showsModelStorage = false
    @State private var showsDataPrivacy = false
    @State private var showsAbout = false
    @State private var showsKeyboardSetup = false
    @State private var showsShortcutSetup = false
    @State private var showsKeyboardDiagnostics = false
    @State private var keyboardDiagnostics: [KeyboardDiagnosticEntry] = []

    init(fixture: VisualFixture? = nil) {
        _showsAcknowledgements = State(initialValue: fixture == .settingsAcknowledgements)
        _showsAbout = State(initialValue: fixture == .settingsAcknowledgements)
        _showsProfile = State(initialValue: fixture == .profile)
    }

    var body: some View {
        NavigationStack {
            settingsContent
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .modifier(settingsConfirmationDialogs)
            .sheet(isPresented: $showsProfile) {
                ProfileView()
                    .environmentObject(modelManager)
            }
            .sheet(isPresented: $showsModelStorage) {
                modelStorageDetails
            }
            .sheet(isPresented: $showsDataPrivacy) {
                dataPrivacyDetails
            }
            .sheet(isPresented: $showsAbout) {
                aboutDetails
            }
            .sheet(isPresented: $showsKeyboardSetup) {
                KeyboardSetupView()
            }
            .sheet(isPresented: $showsShortcutSetup) {
                ShortcutSetupView(openShortcuts: openShortcuts)
            }
            .sheet(item: $exportShare) { exportShare in
                SettingsActivityView(activityItems: exportShare.items)
            }
            .onAppear {
                refreshModelCacheSummaries()
            }
            .onChange(of: modelManager.selectedModel) { _, _ in
                refreshModelCacheSummaries()
            }
            .onChange(of: transcriptionEngine.state) { _, newState in
                if case .downloadingModel = newState { return }
                refreshModelCacheSummaries()
            }
        }
    }

    private var settingsContent: some View {
        ZStack {
            VyrraTheme.pageBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                settingsSections
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 24)
                    .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 48 : 28)
            }
        }
    }

    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 22) {
            appSection
            voiceAndAccessSection
            aboutSection
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var appSection: some View {
        SettingsSection(title: "App") {
            SettingsButtonRow(title: "Profile", systemImage: "person.crop.circle") {
                showsProfile = true
            }
            SettingsToggleRow(
                title: "Save History",
                systemImage: "clock",
                isOn: $modelManager.savesHistory
            )
            SettingsButtonValueRow(
                title: "Data & Privacy",
                value: "Local",
                systemImage: "lock"
            ) {
                showsDataPrivacy = true
            }
        }
    }

    private var voiceAndAccessSection: some View {
        SettingsSection(title: "Voice & Access") {
            SettingsButtonValueRow(
                title: "Model",
                value: modelManager.selectedModel.title,
                systemImage: "internaldrive"
            ) {
                showsModelStorage = true
            }
            SettingsButtonRow(title: "Keyboard", systemImage: "keyboard") {
                showsKeyboardSetup = true
            }
            SettingsButtonRow(title: "Shortcuts & Action Button", systemImage: "button.programmable") {
                showsShortcutSetup = true
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            SettingsValueRow(title: "Account", value: "None")
            SettingsValueRow(title: "Analytics", value: "None")
            SettingsValueRow(title: "Transcription", value: "On-device after download")
            SettingsValueRow(title: "Keyboard", value: "Local insert")
        }
    }

    private var modelStorageSection: some View {
        SettingsSection(title: "Downloads") {
            speechModelRows
            SettingsValueRow(title: "Free Space", value: ModelCacheStore.availableStorageLabel())
            clearDownloadsButton
            modelStorageErrorText
        }
    }

    private var modelSelectionSection: some View {
        SettingsSection(title: "Dictation") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speech model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Speech model", selection: $modelManager.selectedModel) {
                    ForEach(SpeechModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spoken language")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Spoken language", selection: $modelManager.selectedLanguageCode) {
                    ForEach(SpeechLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.vertical, 10)

            Text("Choose the language you speak. Auto Detect guesses each recording; a fixed language is more reliable for short phrases.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Model details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Speech recognition runs on this iPhone using OpenAI Whisper and WhisperKit 0.18.0. Audio is not sent to a transcription service. Text cleanup uses local rules.")
                    Text("Model files are converted to Core ML by Argmax and downloaded from Hugging Face. A download is required before first use.")
                    Text("Variant: \(selectedModelVariant)")
                        .textSelection(.enabled)
                    Text("Download: \(modelManager.selectedModel.storageLabel)")
                    Link("View model source", destination: modelManager.selectedModel.sourceURL)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            }
            .padding(.vertical, 10)
        }
    }

    private var selectedModelVariant: String {
        modelCacheSummary(for: modelManager.selectedModel).folderPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? modelManager.selectedModel.sourceVariant
    }

    private var speechModelRows: some View {
        ForEach(SpeechModel.allCases) { model in
            SettingsModelRow(
                model: model,
                summary: modelCacheSummary(for: model),
                isDownloading: isDownloading(model),
                progress: downloadProgress(for: model),
                isDisabled: hasActiveModelDownload,
                download: {
                    downloadModel(model)
                },
                delete: {
                    modelDeleteTarget = model
                    showsDeleteModelConfirmation = true
                }
            )
        }
    }

    private var clearDownloadsButton: some View {
        Button(role: .destructive) {
            showsClearModelDownloadsConfirmation = true
        } label: {
            HStack {
                Label("Clear Downloads", systemImage: "externaldrive.badge.xmark")
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.vertical, 13)
        }
        .disabled(!hasCachedModels || hasActiveModelDownload)
    }

    @ViewBuilder
    private var modelStorageErrorText: some View {
        if let modelStorageError {
            Text(modelStorageError)
                .font(.footnote)
                .foregroundStyle(VyrraTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private var dataSection: some View {
        SettingsSection(title: "Local Data") {
            localDataRows
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsButtonValueRow(
                title: ProductIdentity.publicName,
                value: appVersion,
                systemImage: "info.circle"
            ) {
                showsAbout = true
            }
        }
    }

    private var aboutLinksSection: some View {
        SettingsSection(title: "App Information") {
            SettingsButtonRow(title: "Diagnostics", systemImage: "waveform.path.ecg") {
                refreshKeyboardDiagnostics()
                showsKeyboardDiagnostics = true
            }
            SettingsLinkRow(
                title: "Privacy Policy",
                systemImage: "lock",
                destination: VyrraExternalLinks.privacyPolicy
            )
            SettingsLinkRow(
                title: "Support",
                systemImage: "questionmark.circle",
                destination: VyrraExternalLinks.supportPage
            )
            SettingsButtonRow(title: "Acknowledgements", systemImage: "doc.text") {
                showsAcknowledgements = true
            }
        }
    }

    private var aboutDetails: some View {
        NavigationStack {
            settingsDetailPage {
                aboutLinksSection
            }
            .navigationTitle("About \(ProductIdentity.publicName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsAbout = false
                    }
                }
            }
        }
        .sheet(isPresented: $showsAcknowledgements) {
            AcknowledgementsView()
        }
        .sheet(isPresented: $showsKeyboardDiagnostics) {
            DiagnosticsView(
                timing: recordingDiagnostics.lastTiming,
                entries: $keyboardDiagnostics
            ) {
                refreshKeyboardDiagnostics()
            }
        }
    }

    private var modelStorageDetails: some View {
        NavigationStack {
            settingsDetailPage {
                modelSelectionSection
                modelStorageSection
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsModelStorage = false
                    }
                }
            }
            .modifier(settingsConfirmationDialogs)
        }
    }

    private var dataPrivacyDetails: some View {
        NavigationStack {
            settingsDetailPage {
                privacySection
                dataSection
            }
            .navigationTitle("Data & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsDataPrivacy = false
                    }
                }
            }
            .modifier(settingsConfirmationDialogs)
        }
    }

    private func settingsDetailPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            VyrraTheme.pageBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
        }
    }

    private var settingsConfirmationDialogs: SettingsConfirmationDialogs {
        SettingsConfirmationDialogs(
            showsClearHistory: $showsClearConfirmation,
            showsClearClipboard: $showsClearClipboardConfirmation,
            showsClearKeyboardData: $showsClearKeyboardDataConfirmation,
            showsDeleteModel: $showsDeleteModelConfirmation,
            showsClearModels: $showsClearModelDownloadsConfirmation,
            clearHistory: clearHistory,
            clearClipboard: clearClipboard,
            clearKeyboardData: { clearKeyboardData() },
            deleteModel: deleteSelectedModelDownload,
            clearModels: clearModelDownloads
        )
    }

    @ViewBuilder
    private var localDataRows: some View {
        SettingsValueRow(title: "Saved Transcripts", value: "\(records.count)")
        SettingsButtonRow(title: "Export Vyrra Data", systemImage: "square.and.arrow.up") {
            exportVyrraData()
        }
        dataExportErrorText

        Button(role: .destructive) {
            showsClearConfirmation = true
        } label: {
            HStack {
                Label("Clear History", systemImage: "trash")
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.vertical, 13)
        }
        .disabled(records.isEmpty)

        Button(role: .destructive) {
            showsClearClipboardConfirmation = true
        } label: {
            HStack {
                Label("Clear Clipboard", systemImage: "doc.on.clipboard")
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.vertical, 13)
        }

        Button(role: .destructive) {
            showsClearKeyboardDataConfirmation = true
        } label: {
            HStack {
                Label("Clear Keyboard Data", systemImage: "keyboard.badge.ellipsis")
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.vertical, 13)
        }
    }

    @ViewBuilder
    private var dataExportErrorText: some View {
        if let dataExportError {
            Text(dataExportError)
                .font(.footnote)
                .foregroundStyle(VyrraTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(height: 0.5)
                }
        }
    }

    private func clearHistory() {
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        clearKeyboardData(playsHaptic: false)
        HapticManager.warning()
    }

    private func clearClipboard() {
        ClipboardService.clearText()
        HapticManager.warning()
    }

    private func clearKeyboardData(playsHaptic: Bool = true) {
        try? KeyboardSharedStore.clear()
        try? KeyboardSharedStore.clearCommand()
        try? KeyboardSharedStore.clearDiagnostics()
        _ = try? KeyboardSharedStore.bootstrapIfNeeded()
        if playsHaptic {
            HapticManager.warning()
        }
    }

    private func exportVyrraData() {
        do {
            let payload = VyrraExportPayload.make(
                records: records,
                folders: folders,
                vocabulary: vocabularyEntries,
                snippets: snippetEntries,
                modelManager: modelManager
            )
            let url = try VyrraExportWriter.exportURL(for: payload)
            dataExportError = nil
            exportShare = SettingsExportShare(items: [url])
            HapticManager.completed()
        } catch {
            dataExportError = "Couldn't export Vyrra data. \(error.localizedDescription)"
            HapticManager.warning()
        }
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func refreshKeyboardDiagnostics() {
        keyboardDiagnostics = (try? KeyboardSharedStore.readDiagnostics()) ?? []
    }

    private func deleteSelectedModelDownload() {
        guard let modelDeleteTarget else { return }
        let didDelete = ModelCacheStore.deleteCachedModel(for: modelDeleteTarget.rawValue)
        if didDelete {
            transcriptionEngine.unload(modelName: modelDeleteTarget.rawValue)
            voiceReadiness.refreshFromCurrentState()
            modelStorageError = nil
            HapticManager.warning()
        } else {
            modelStorageError = "Couldn't delete \(modelDeleteTarget.title). The download is still on iPhone."
            HapticManager.warning()
        }
        refreshModelCacheSummaries()
        self.modelDeleteTarget = nil
    }

    private func clearModelDownloads() {
        let cachedCount = SpeechModel.allCases.filter { modelCacheSummary(for: $0).isUsable }.count
        transcriptionEngine.unload()
        let deletedCount = ModelCacheStore.deleteCachedModels(for: SpeechModel.allCases.map(\.rawValue))
        voiceReadiness.refreshFromCurrentState()
        if deletedCount == cachedCount {
            modelStorageError = nil
        } else if deletedCount == 0 {
            modelStorageError = "Couldn't clear model downloads. The downloads are still on iPhone."
        } else {
            modelStorageError = "Cleared some downloads. \(cachedCount - deletedCount) still need attention."
        }
        refreshModelCacheSummaries()
        HapticManager.warning()
    }

    private var hasCachedModels: Bool {
        SpeechModel.allCases.contains { modelCacheSummary(for: $0).isUsable }
    }

    private var hasActiveModelDownload: Bool {
        activeModelDownload != nil || downloadingModelName != nil
    }

    private var downloadingModelName: String? {
        guard case .downloadingModel(let modelName, _) = transcriptionEngine.state else { return nil }
        return modelName
    }

    private func modelCacheSummary(for model: SpeechModel) -> ModelCacheSummary {
        modelCacheSummaries[model.rawValue] ?? ModelCacheStore.summary(for: model.rawValue)
    }

    private func isDownloading(_ model: SpeechModel) -> Bool {
        activeModelDownload == model || downloadingModelName == model.rawValue
    }

    private func downloadProgress(for model: SpeechModel) -> Double? {
        guard case .downloadingModel(let modelName, let progress) = transcriptionEngine.state,
              modelName == model.rawValue else {
            return nil
        }

        return progress
    }

    private func downloadModel(_ model: SpeechModel) {
        guard !hasActiveModelDownload else { return }

        guard ModelCacheStore.hasEnoughStorage(forModelBytes: model.estimatedStorageBytes) else {
            modelStorageError = "Free storage before downloading \(model.storageLabel)."
            HapticManager.warning()
            return
        }

        activeModelDownload = model
        modelStorageError = nil

        Task { @MainActor in
            do {
                try await transcriptionEngine.download(modelName: model.rawValue)
                refreshModelCacheSummaries()
                voiceReadiness.handleDownloadCompleted(model: model)
                HapticManager.completed()
            } catch {
                modelStorageError = error.localizedDescription
                HapticManager.warning()
            }

            activeModelDownload = nil
        }
    }

    private func refreshModelCacheSummaries() {
        modelCacheSummaries = Self.makeModelCacheSummaries()
    }

    private static func makeModelCacheSummaries() -> [String: ModelCacheSummary] {
        Dictionary(uniqueKeysWithValues: SpeechModel.allCases.map { model in
            (model.rawValue, ModelCacheStore.summary(for: model.rawValue))
        })
    }
}

private struct SettingsExportShare: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct SettingsActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SettingsConfirmationDialogs: ViewModifier {
    @Binding var showsClearHistory: Bool
    @Binding var showsClearClipboard: Bool
    @Binding var showsClearKeyboardData: Bool
    @Binding var showsDeleteModel: Bool
    @Binding var showsClearModels: Bool

    let clearHistory: () -> Void
    let clearClipboard: () -> Void
    let clearKeyboardData: () -> Void
    let deleteModel: () -> Void
    let clearModels: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Clear history?", isPresented: $showsClearHistory, titleVisibility: .visible) {
                Button("Clear History", role: .destructive, action: clearHistory)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This does not affect the clipboard or other apps where text was pasted.")
            }
            .confirmationDialog("Clear system clipboard?", isPresented: $showsClearClipboard, titleVisibility: .visible) {
                Button("Clear Clipboard", role: .destructive, action: clearClipboard)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears text currently on the system clipboard.")
            }
            .confirmationDialog("Clear keyboard inserts?", isPresented: $showsClearKeyboardData, titleVisibility: .visible) {
                Button("Clear Keyboard Data", role: .destructive, action: clearKeyboardData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears Vyrra's shared last draft and shortcut inserts.")
            }
            .confirmationDialog("Delete model download?", isPresented: $showsDeleteModel, titleVisibility: .visible) {
                Button("Delete Download", role: .destructive, action: deleteModel)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The model can be downloaded again later.")
            }
            .confirmationDialog("Clear model downloads?", isPresented: $showsClearModels, titleVisibility: .visible) {
                Button("Clear Downloads", role: .destructive, action: clearModels)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Models can be downloaded again later.")
            }
    }
}

private struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsLicenseTexts = false

    private let packages = [
        AcknowledgementItem(
            name: "WhisperKit / argmax-oss-swift",
            role: "On-device speech transcription runtime",
            license: "MIT",
            source: "github.com/argmaxinc/argmax-oss-swift"
        ),
        AcknowledgementItem(
            name: "OpenAI Whisper large-v3",
            role: "Base speech recognition model family",
            license: "Apache License 2.0",
            source: "huggingface.co/openai/whisper-large-v3"
        ),
        AcknowledgementItem(
            name: "swift-transformers",
            role: "Transformer model support",
            license: "Apache License 2.0",
            source: "github.com/huggingface/swift-transformers"
        ),
        AcknowledgementItem(
            name: "swift-jinja",
            role: "Template support dependency",
            license: "Apache License 2.0",
            source: "github.com/huggingface/swift-jinja"
        ),
        AcknowledgementItem(
            name: "yyjson",
            role: "JSON parsing dependency",
            license: "MIT",
            source: "github.com/ibireme/yyjson"
        ),
        AcknowledgementItem(
            name: "Swift Collections",
            role: "Data structures dependency",
            license: "Apache License 2.0",
            source: "github.com/apple/swift-collections"
        ),
        AcknowledgementItem(
            name: "Swift Crypto",
            role: "Crypto support dependency",
            license: "Apache License 2.0 with NOTICE",
            source: "github.com/apple/swift-crypto"
        ),
        AcknowledgementItem(
            name: "Swift ASN.1",
            role: "Resolved crypto stack dependency",
            license: "Apache License 2.0 with NOTICE",
            source: "github.com/apple/swift-asn1"
        ),
        AcknowledgementItem(
            name: "Swift Argument Parser",
            role: "Resolved transitive package",
            license: "Apache License 2.0",
            source: "github.com/apple/swift-argument-parser"
        )
    ]

    var body: some View {
        ZStack {
            VyrraTheme.pageBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Acknowledgements")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        Spacer(minLength: 12)

                        Button("Done") {
                            dismiss()
                        }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open-source software used by \(ProductIdentity.publicName).")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(packages) { item in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.name)
                                    .font(.headline)

                                Text(item.role)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(item.license)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.08), in: Capsule())

                                    Text(item.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.82)
                                }
                            }
                            .padding(.vertical, 4)

                            if item.id != packages.last?.id {
                                Divider()
                            }
                        }
                    }

                    Button {
                        showsLicenseTexts = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.plaintext")
                                .frame(width: 24)

                            Text("License Texts")
                                .font(.body.weight(.semibold))

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 18)
                        .frame(minHeight: 56)
                        .background(VyrraTheme.quietFill, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(VyrraTheme.thinLine, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows bundled open-source license and notice text")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showsLicenseTexts) {
            ThirdPartyNoticesView()
        }
    }
}

private struct ThirdPartyNoticesView: View {
    @Environment(\.dismiss) private var dismiss

    private let documents = ThirdPartyNoticeDocument.bundled

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(documents) { document in
                        DisclosureGroup(document.title) {
                            Text(document.contents)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        }
                        .font(.body.weight(.semibold))
                        .padding(16)
                        .background(VyrraTheme.quietFill, in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(VyrraTheme.thinLine, lineWidth: 1)
                        }
                    }

                    if documents.isEmpty {
                        ContentUnavailableView(
                            "Notices Unavailable",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                }
                .padding(20)
            }
            .background(VyrraTheme.pageBackground)
            .navigationTitle("License Texts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ThirdPartyNoticeDocument: Identifiable {
    let fileName: String
    let contents: String

    var id: String { fileName }

    var title: String {
        URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
    }

    static let bundled: [ThirdPartyNoticeDocument] = {
        let urls = Bundle.main.urls(
            forResourcesWithExtension: "txt",
            subdirectory: "ThirdPartyLicenses"
        ) ?? []

        return urls
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                ThirdPartyNoticeDocument(
                    fileName: url.lastPathComponent,
                    contents: (try? String(contentsOf: url, encoding: .utf8)) ?? "Notice text unavailable."
                )
            }
    }()
}

private struct AcknowledgementItem: Identifiable {
    let name: String
    let role: String
    let license: String
    let source: String

    var id: String { name }
}

private struct SettingsModelRow: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    let model: SpeechModel
    let summary: ModelCacheSummary
    let isDownloading: Bool
    let progress: Double?
    let isDisabled: Bool
    let download: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusTint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .foregroundStyle(.primary)

                Text(statusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .font(.body)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        if isDownloading { return "arrow.down.circle" }
        return summary.isUsable ? "checkmark.circle.fill" : "internaldrive"
    }

    private var statusTint: Color {
        if isDownloading { return accentColor }
        return summary.isUsable ? accentColor : .secondary
    }

    private var statusDetail: String {
        if isDownloading {
            return "\(model.detail) · Downloading \(model.storageLabel)"
        }

        if summary.isUsable {
            return "\(model.detail) · On iPhone · \(summary.sizeLabel)"
        }

        return "\(model.detail) · Not downloaded · \(model.storageLabel)"
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isDownloading {
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 58)
                    .tint(accentColor)

                Text(progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else if summary.isUsable {
            Menu {
                Button(role: .destructive, action: delete) {
                    Label("Delete Download", systemImage: "trash")
                }
            } label: {
                Label("On iPhone", systemImage: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .disabled(isDisabled)
        } else {
            Button(action: download) {
                Text(isDisabled ? "Not downloaded" : "Download")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isDisabled ? .secondary : accentColor)
            .buttonStyle(.plain)
            .disabled(isDisabled)
        }
    }

    private var progressLabel: String {
        guard let progress else { return "Starting" }
        return "\(Int((progress * 100).rounded()))%"
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font((dynamicTypeSize.isAccessibilitySize ? Font.footnote : .subheadline).weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 14 : 16)
            .background(
                VyrraTheme.quietFill,
                in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(VyrraTheme.quietFill)
                    .frame(height: 1)
                    .padding(.horizontal, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous)
                    .stroke(VyrraTheme.thinLine, lineWidth: 1)
            }
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text(value)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsSetupRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsFootnoteRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
    }
}

private struct SettingsToggleRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String?
    @Binding var isOn: Bool

    init(title: String, systemImage: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
            HapticManager.selected()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let systemImage, !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer(minLength: 12)

                SettingsSwitch(isOn: isOn)
            }
            .font(.body)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

private struct SettingsSwitch: View {
    let isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(trackColor)

            Circle()
                .fill(Color.white)
                .frame(width: 27, height: 27)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 2, x: 0, y: 1)
                .padding(2)
        }
        .frame(width: 52, height: 31)
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.08), lineWidth: 0.5)
        }
    }

    private var trackColor: Color {
        isOn ? Color(.systemGreen) : Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }
}

private struct SettingsPickerRow<PickerContent: View, ValueContent: View>: View {
    let title: String
    @ViewBuilder let picker: PickerContent
    @ViewBuilder let value: ValueContent

    var body: some View {
        Menu {
            picker
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                HStack(spacing: 5) {
                    value
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsButtonRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.body)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsButtonValueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(title)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)

                            Spacer(minLength: 10)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }

                        Text(value)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: systemImage)
                            .frame(width: 20)
                            .accessibilityHidden(true)

                        Text(title)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 10)

                        Text(value)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(.body)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsLinkRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let systemImage: String?
    let destination: URL

    init(title: String, systemImage: String? = nil, destination: URL) {
        self.title = title
        self.systemImage = systemImage
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                if let systemImage, !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.body)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 0.5)
            }
        }
    }
}

private struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let timing: RecordingTimingSummary?
    @Binding var entries: [KeyboardDiagnosticEntry]
    let refresh: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Diagnostics")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    SettingsSection(title: "Last Run") {
                        if let timing {
                            ForEach(timing.rows, id: \.title) { row in
                                SettingsValueRow(title: row.title, value: row.value)
                            }
                        } else {
                            SettingsValueRow(title: "Status", value: "Not captured")
                        }
                    }

                    SettingsSection(title: "Keyboard") {
                        if entries.isEmpty {
                            SettingsValueRow(title: "Events", value: "None yet")
                        } else {
                            ForEach(entries.reversed()) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(entry.type.rawValue)
                                            .foregroundStyle(.primary)

                                        Spacer(minLength: 12)

                                        Text(entry.createdAt, style: .time)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(entry.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.body)
                                .padding(.vertical, 14)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.14))
                                        .frame(height: 0.5)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    SettingsSection(title: "Scope") {
                        SettingsValueRow(title: "Text", value: "Not logged")
                        SettingsValueRow(title: "Audio", value: "Not shared")
                        SettingsValueRow(title: "Model", value: "Main app only")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 42)
            }
            .background(VyrraTheme.pageBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", action: refresh)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct KeyboardSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(KeyboardInactivityTimeout.defaultsKey) private var keyboardTimeout = KeyboardInactivityTimeout.fiveMinutes.rawValue
    @State private var keyboardAppearance = (try? KeyboardSharedStore.readAppearance()) ?? KeyboardAppearancePreferences()
    @State private var appearanceSaveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Keyboard")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    SettingsSection(title: "Set Up") {
                        SettingsSetupRow(
                            icon: "1.circle.fill",
                            title: "Add Vyrra",
                            detail: "iPhone Settings > General > Keyboard > Keyboards > Add New Keyboard > Vyrra"
                        )
                        SettingsSetupRow(
                            icon: "2.circle.fill",
                            title: "Allow Full Access",
                            detail: "Open Vyrra in the keyboard list. Full Access enables local drafts and shortcuts."
                        )
                        SettingsSetupRow(
                            icon: "3.circle.fill",
                            title: "Choose Vyrra",
                            detail: "In any text field, tap the globe and choose Vyrra."
                        )
                        SettingsSetupRow(
                            icon: "4.circle.fill",
                            title: "Start Dictation, Then Return",
                            detail: "Enable Keyboard Session in Speak, then return to your text field. Tap the mic to start. Tap the checkmark to finish or the × to discard the phrase. If the session times out, reopen Vyrra. You can also use Start Dictation through Shortcuts or the Action Button."
                        )

                        SettingsButtonRow(title: "Open Settings", systemImage: "gearshape") {
                            openAppSettings()
                        }
                    }

                    SettingsSection(title: "Size & Text") {
                        HStack {
                            Text("Keyboard height")
                            Spacer()
                            Picker("Keyboard height", selection: $keyboardAppearance.size) {
                                ForEach(KeyboardSize.allCases) { size in
                                    Text(size.title).tag(size)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 14)
                        Divider()
                        HStack {
                            Text("Key text size")
                            Spacer()
                            Picker("Key text size", selection: $keyboardAppearance.textSize) {
                                ForEach(KeyboardTextSize.allCases) { size in
                                    Text(size.title).tag(size)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 14)
                        if appearanceSaveFailed {
                            Text("Couldn't save keyboard preferences. Try again.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    SettingsSection(title: "Keyboard Dictation") {
                        HStack {
                            Text("Turn off when unused")
                            Spacer()
                            Picker("Turn off when unused", selection: $keyboardTimeout) {
                                ForEach(KeyboardInactivityTimeout.allCases) { timeout in
                                    Text(timeout.title).tag(timeout.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 14)
                        SettingsFootnoteRow("The countdown starts when Vyrra is in the background and its keyboard is no longer visible. It pauses while recording or processing. Never keeps the microphone on until you stop keyboard dictation. Audio between phrases is discarded.")
                    }

                    SettingsSection(title: "Privacy") {
                        SettingsFootnoteRow("Typing works without Full Access. Full Access shares local session results and shortcuts with the Vyrra keyboard.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 42)
            }
            .background(VyrraTheme.pageBackground)
            .onChange(of: keyboardAppearance) { _, appearance in
                do {
                    var preferences = appearance
                    preferences.hapticsEnabled = (UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool) ?? true
                    try KeyboardSharedStore.writeAppearance(preferences)
                    appearanceSaveFailed = false
                } catch {
                    appearanceSaveFailed = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct ShortcutSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let openShortcuts: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Quick Access")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))

                    SettingsSection(title: "Start Dictation") {
                        SettingsSetupRow(
                            icon: "1.circle.fill",
                            title: "Add the Shortcut",
                            detail: "In Shortcuts, tap +, search Vyrra, then choose Start Dictation."
                        )
                        SettingsSetupRow(
                            icon: "2.circle.fill",
                            title: "Assign the Action Button",
                            detail: "iPhone Settings > Action Button > Shortcut > Start Dictation"
                        )
                        SettingsButtonRow(title: "Open Shortcuts", systemImage: "square.grid.2x2") {
                            openShortcuts()
                        }
                    }

                    SettingsSection(title: "Also Available") {
                        SettingsValueRow(title: "Siri", value: "Start Dictation with Vyrra")
                        SettingsValueRow(title: "Spotlight", value: "Search Start Dictation")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 42)
            }
            .background(VyrraTheme.pageBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(TranscriptionEngine())
        .environmentObject(ModelManager())
        .environmentObject(RecordingDiagnostics())
        .modelContainer(for: [
            TranscriptionRecord.self,
            NoteFolder.self,
            VocabularyEntry.self,
            SnippetEntry.self
        ], inMemory: true)
}
