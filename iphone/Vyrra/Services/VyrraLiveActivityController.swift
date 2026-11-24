import ActivityKit
import Foundation

@MainActor
final class VyrraLiveActivityController: ObservableObject {
    private var currentActivity: Activity<VyrraActivityAttributes>?
    private var updateTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?
    private var updateRevision = 0

    func sync(phase: RecordingPhase, startedAt: Date?, keyboardSessionExpiresAt: Date? = nil, keyboardSessionIsActive: Bool = false) {
        let hasKeyboardSession = keyboardSessionIsActive || keyboardSessionExpiresAt.map { $0 > Date() } == true
        let keyboardIsReady = hasKeyboardSession
            && (phase == .idle || phase == .copied)
        guard let liveState = keyboardIsReady ? .keyboardReady : Self.liveState(for: phase) else {
            endNow()
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            endNow()
            return
        }

        let contentState = VyrraActivityAttributes.ContentState(
            state: liveState,
            startedAt: startedAt ?? Date(),
            updatedAt: Date(),
            keyboardSessionExpiresAt: keyboardSessionExpiresAt,
            keyboardSessionIsActive: hasKeyboardSession
        )

        upsertActivity(with: contentState)

        if liveState == .copied || liveState == .attention {
            endAfterBriefConfirmation(using: contentState)
        } else {
            endTask?.cancel()
            endTask = nil
        }
    }

    func endNow() {
        endTask?.cancel()
        endTask = nil
        updateRevision += 1
        updateTask?.cancel()
        updateTask = nil

        let activities = liveActivities
        currentActivity = nil
        guard !activities.isEmpty else { return }

        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private var liveActivities: [Activity<VyrraActivityAttributes>] {
        var activities = Activity<VyrraActivityAttributes>.activities
        if let currentActivity, !activities.contains(where: { $0.id == currentActivity.id }) {
            activities.append(currentActivity)
        }
        return activities
    }

    private func upsertActivity(with state: VyrraActivityAttributes.ContentState) {
        let content = ActivityContent(
            state: state,
            staleDate: Self.staleDate(for: state, now: Date())
        )

        let activities = liveActivities
        if let activity = activities.first {
            currentActivity = activity
            updateRevision += 1
            let revision = updateRevision
            let previousUpdate = updateTask
            updateTask = Task {
                if let previousUpdate {
                    await previousUpdate.value
                }
                guard !Task.isCancelled else { return }
                await activity.update(content)
                guard !Task.isCancelled else { return }
                for duplicate in activities.dropFirst() {
                    await duplicate.end(nil, dismissalPolicy: .immediate)
                }
                if revision == updateRevision {
                    updateTask = nil
                }
            }
            return
        }

        do {
            currentActivity = try Activity.request(
                attributes: VyrraActivityAttributes(sessionID: UUID().uuidString),
                content: content,
                pushType: nil
            )
        } catch {
            currentActivity = nil
        }
    }

    private func endAfterBriefConfirmation(using state: VyrraActivityAttributes.ContentState) {
        endTask?.cancel()
        let content = ActivityContent(
            state: state,
            staleDate: Self.staleDate(for: state, now: Date())
        )
        let pendingUpdate = updateTask

        endTask = Task {
            if let pendingUpdate {
                await pendingUpdate.value
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let dismissAt = Date().addingTimeInterval(
                VyrraSessionPolicy.liveActivityCompletionVisibility
            )
            for activity in liveActivities {
                await activity.end(content, dismissalPolicy: .after(dismissAt))
            }
            currentActivity = nil
            endTask = nil
        }
    }

    static func liveState(for phase: RecordingPhase) -> VyrraLiveActivityState? {
        switch phase {
        case .recording:
            .listening
        case .transcribing, .processing:
            .polishing
        case .copied:
            .copied
        case .emptyTranscript, .error:
            .attention
        case .idle,
             .needsMicrophone,
             .microphoneDenied,
             .modelUnavailable,
             .modelDownloading,
             .modelPreparing,
             .lowStorage,
             .offlineBeforeDownload:
            nil
        }
    }

    static func staleDate(
        for contentState: VyrraActivityAttributes.ContentState,
        now: Date
    ) -> Date {
        switch contentState.state {
        case .keyboardReady:
            return contentState.keyboardSessionExpiresAt ?? now.addingTimeInterval(60)
        case .listening:
            return max(
                contentState.startedAt.addingTimeInterval(
                    VyrraSessionPolicy.listeningStaleInterval
                ),
                now.addingTimeInterval(45)
            )
        case .polishing:
            return now.addingTimeInterval(VyrraSessionPolicy.processingStaleInterval)
        case .copied, .attention:
            return now.addingTimeInterval(
                VyrraSessionPolicy.liveActivityCompletionVisibility + 2
            )
        }
    }
}
