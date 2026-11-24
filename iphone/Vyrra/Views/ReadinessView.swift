import SwiftUI

struct ReadinessView: View {
    @Environment(\.vyrraAccentColor) private var accentColor
    @EnvironmentObject private var transcriptionEngine: TranscriptionEngine
    @EnvironmentObject private var modelManager: ModelManager
    @State private var prepareError: String?
    @State private var hasRequestedPrepare = false
    @State private var requestedCachedModel = false

    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            // Status zone: what the model is doing. Its height holds steady so the wordmark never moves.
            VStack(spacing: 24) {
                Text(ProductIdentity.publicName)
                    .font(.largeTitle.weight(.semibold))
                    .kerning(-0.4)
                    .accessibilityAddTraits(.isHeader)

                status
                    .frame(minHeight: 48, alignment: .top)
            }

            Spacer(minLength: 32)

            // Action zone: the one thing to do next, or the one thing to know while waiting.
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: 104)
                actions
            }

            Text("Private. Free. Forever.")
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(.tertiary)
                .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VyrraTheme.pageBackground)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .onAppear(perform: syncPrepareState)
        .onChange(of: transcriptionEngine.state) { _, _ in
            syncPrepareState()
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var status: some View {
        if phase == .idle {
            VStack(spacing: 10) {
                Text(modelReadinessDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)

                if let prepareError {
                    Text(prepareError)
                        .font(.footnote)
                        .foregroundStyle(VyrraTheme.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)
                }
            }
            .transition(.opacity)
        } else {
            // A readout aligned to the line's edges: phase on the left, value on the right.
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(statusTitle)
                        .foregroundStyle(phase == .ready ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)

                    Spacer(minLength: 12)

                    statusValue
                }
                .font(.footnote)

                QuietProgressLine(progress: lineProgress, isSettled: phase == .ready)
            }
            .frame(width: QuietProgressLine.width)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice model")
            .accessibilityValue(statusAccessibilityValue)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var statusValue: some View {
        if let downloadProgress {
            Text(downloadProgress, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
        } else if phase == .ready {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isPreparingModel {
            Text(modelManager.selectedModel.activePreparationGuidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .transition(.opacity)
        } else {
            VStack(spacing: 18) {
                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(.systemBackground))
                .background(accentColor, in: RoundedRectangle(cornerRadius: VyrraTheme.cornerRadius, style: .continuous))
                .accessibilityHint(primaryAccessibilityHint)

                if !modelIsReady {
                    Button("Skip for Now", action: continueAction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the app. Recording will ask to prepare the model later.")
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - State

    private enum Phase: Equatable {
        case idle, downloading, preparing, ready
    }

    private var phase: Phase {
        if modelIsReady { return .ready }
        if case .downloadingModel = transcriptionEngine.state { return .downloading }
        return isPreparingModel ? .preparing : .idle
    }

    private var statusTitle: String {
        switch phase {
        case .downloading: "Downloading"
        case .preparing: "Preparing"
        case .ready: "Ready"
        case .idle: ""
        }
    }

    /// Determinate while downloading, a slow glide while preparing, full once ready.
    private var lineProgress: Double? {
        phase == .ready ? 1 : downloadProgress
    }

    private var statusAccessibilityValue: String {
        switch phase {
        case .downloading:
            guard let downloadProgress else { return "Downloading" }
            return "Downloading, \(Int(min(max(downloadProgress, 0), 1) * 100)) percent"
        case .preparing:
            return "Preparing"
        case .ready:
            return "Ready"
        case .idle:
            return ""
        }
    }

    private var modelIsReady: Bool {
        if case .ready(let modelName) = transcriptionEngine.state {
            return modelName == modelManager.selectedModelName
        }
        return false
    }

    private var isPreparingModel: Bool {
        switch transcriptionEngine.state {
        case .downloadingModel, .loadingModel:
            true
        default:
            hasRequestedPrepare && !modelIsReady
        }
    }

    private var downloadProgress: Double? {
        if case .downloadingModel(_, let progress) = transcriptionEngine.state {
            return progress
        }
        return nil
    }

    private var modelReadinessDetail: String {
        switch transcriptionEngine.state {
        case .downloadingModel:
            return modelManager.selectedModel.downloadExpectation
        case .loadingModel:
            return modelManager.selectedModel.warmupExpectation
        case .ready:
            return "Ready."
        case .failed:
            return "Retry anytime."
        default:
            if hasRequestedPrepare {
                return requestedCachedModel ? modelManager.selectedModel.warmupExpectation : "Starting download."
            }
            return modelCacheSummary.isUsable ? modelManager.selectedModel.warmupExpectation : modelManager.selectedModel.downloadExpectation
        }
    }

    private var primaryButtonTitle: String {
        if modelIsReady { return "Continue" }
        if isPreparingModel { return "Preparing" }
        return modelCacheSummary.isUsable ? "Prepare" : modelManager.selectedModel.downloadActionTitle
    }

    private var primaryAccessibilityHint: String {
        if modelIsReady {
            return "Opens the record screen"
        }

        if modelCacheSummary.isUsable {
            return "Prepares the speech model for dictation"
        }

        return "Downloads the speech model. \(modelManager.selectedModel.downloadExpectation)"
    }

    private var modelCacheSummary: ModelCacheSummary {
        ModelCacheStore.summary(for: modelManager.selectedModelName)
    }

    private func primaryAction() {
        guard !isPreparingModel else { return }
        if modelIsReady {
            continueAction()
            return
        }

        prepareError = nil
        requestedCachedModel = modelCacheSummary.isUsable
        hasRequestedPrepare = true
        Task {
            do {
                try await transcriptionEngine.prepare(modelName: modelManager.selectedModelName)
            } catch {
                prepareError = error.localizedDescription
                hasRequestedPrepare = false
            }
        }
    }

    private func syncPrepareState() {
        if modelIsReady {
            hasRequestedPrepare = false
        }
    }
}

/// A hairline that fills with download progress. Without a progress value a short
/// segment glides slowly across it; once settled it rests full and still.
/// Motion is shallow and stops under Reduce Motion.
private struct QuietProgressLine: View {
    static let width: CGFloat = 220

    @Environment(\.vyrraAccentColor) private var accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double?
    var isSettled = false

    private let thickness: CGFloat = 2

    var body: some View {
        Group {
            if reduceMotion || isSettled {
                line(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    line(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: Self.width, height: thickness)
        .accessibilityHidden(true)
    }

    private func line(time: TimeInterval) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.08))

            if let progress {
                Capsule()
                    .fill(accentColor.opacity(breath(at: time)))
                    .frame(width: max(thickness, Self.width * min(max(progress, 0), 1)))
                    .animation(.easeOut(duration: 0.6), value: progress)
            } else {
                Capsule()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: Self.width * 0.28)
                    .offset(x: Self.width * 0.72 * glide(at: time))
            }
        }
    }

    /// A slow, shallow pulse so a long single-file download never looks frozen.
    private func breath(at time: TimeInterval) -> Double {
        guard !reduceMotion, !isSettled else { return 1 }
        return 0.72 + 0.28 * (sin(time * 2.2) + 1) / 2
    }

    /// Eased back-and-forth position between 0 and 1.
    private func glide(at time: TimeInterval) -> Double {
        guard !reduceMotion else { return 0.36 }
        return (sin(time * 1.6) + 1) / 2
    }
}

#Preview {
    ReadinessView(continueAction: {})
        .environmentObject(TranscriptionEngine())
        .environmentObject(ModelManager())
}
