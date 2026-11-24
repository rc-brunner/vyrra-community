import ActivityKit
import SwiftUI
import WidgetKit

struct VyrraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VyrraActivityAttributes.self) { context in
            VyrraLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VyrraLiveActivityExpandedView(state: context.state)
                }
            } compactLeading: {
                VyrraLiveActivityMark(state: context.state.state, size: 18)
            } compactTrailing: {
                Text(context.state.state.compactTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(context.state.state.tint)
            } minimal: {
                Image(systemName: context.state.state.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.state.state.tint)
            }
            .keylineTint(context.state.state.tint)
            .widgetURL(URL(string: "vyrra://"))
        }
    }
}

private struct VyrraLiveActivityLockScreenView: View {
    let state: VyrraActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VyrraLiveActivityMark(state: state.state, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Vyrra")
                    .font(.headline.weight(.semibold))
                Text(state.state.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if state.state.shouldShowTimer {
                Text(state.startedAt, style: .timer)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if state.state == .listening {
                Link(destination: URL(string: "vyrra://finish-dictation")!) {
                    Image(systemName: "stop.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel("Finish dictation")
            }
            if state.hasKeyboardSession {
                Link(destination: URL(string: "vyrra://end-keyboard-session")!) {
                    Image(systemName: "mic.slash")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Stop keyboard session and turn off microphone")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct VyrraLiveActivityExpandedView: View {
    let state: VyrraActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            VyrraLiveActivityMark(state: state.state, size: 38)

            HStack(spacing: 8) {
                Text(state.state.title)
                    .font(.headline.weight(.semibold))

                if state.state.shouldShowTimer {
                    Text(state.startedAt, style: .timer)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }

            if state.state == .listening {
                Link(destination: URL(string: "vyrra://finish-dictation")!) {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.white, in: Capsule())
                }
                .accessibilityLabel("Finish dictation")
            }
            if state.hasKeyboardSession {
                Link("Stop Keyboard Session", destination: URL(string: "vyrra://end-keyboard-session")!)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct VyrraLiveActivityMark: View {
    let state: VyrraLiveActivityState
    let size: CGFloat

    var body: some View {
        Image(systemName: state.systemImage)
            .font(.system(size: size * 0.72, weight: .semibold))
            .symbolEffect(.variableColor.iterative, isActive: state == .listening)
            .foregroundStyle(state.tint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private extension VyrraLiveActivityState {
    var tint: Color {
        switch self {
        case .keyboardReady, .listening:
            .white
        case .polishing:
            .gray
        case .copied:
            .white
        case .attention:
            .white
        }
    }
}
