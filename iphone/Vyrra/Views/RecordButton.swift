import SwiftUI

enum RecordButtonTone: Equatable {
    case ready
    case recording
    case processing
    case success
    case disabled

    func fill(accentColor: Color) -> Color {
        switch self {
        case .ready, .recording:
            accentColor
        case .processing:
            accentColor.opacity(0.78)
        case .success:
            VyrraTheme.success
        case .disabled:
            Color(.tertiarySystemFill)
        }
    }

    var foreground: Color {
        switch self {
        case .disabled:
            .secondary
        default:
            Color(.systemBackground)
        }
    }
}

struct RecordButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let systemImage: String
    let isRecording: Bool
    let isProcessing: Bool
    let tone: RecordButtonTone
    let isEnabled: Bool
    let start: () -> Void
    let stop: () -> Void
    var accessibilityLabelOverride: String? = nil
    var diameter: CGFloat = 132

    @GestureState private var isPressed = false
    @State private var didBeginPress = false

    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, state, _ in
                state = true
            }
            .onChanged { _ in
                if isEnabled && !didBeginPress && !isRecording && !isProcessing {
                    didBeginPress = true
                    HapticManager.buttonPressed()
                    start()
                }
            }
            .onEnded { _ in
                didBeginPress = false
                if isEnabled && isRecording {
                    stop()
                }
            }

        ZStack {
            RecordDiscFace(
                title: title,
                systemImage: systemImage,
                tone: tone,
                diameter: diameter,
                isProcessing: isProcessing
            )

            Circle()
                .stroke(Color.primary.opacity(isRecording ? 0.16 : 0.08), lineWidth: 1)
                .frame(width: diameter + 18, height: diameter + 18)
                .opacity(isRecording || isPressed ? 1 : 0)
        }
        .opacity(isEnabled ? 1 : 0.72)
        // Press: a subtle, critically damped shrink with no overshoot, like
        // every other pressable view. Recording shows through the ring, not
        // scale. Under Reduce Motion the disc dims instead of scaling.
        .modifier(RecordDiscPress(isPressed: isPressed))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25), value: isRecording)
        .gesture(gesture)
        .onAppear {
            if isEnabled {
                HapticManager.prepareForRecordButton()
            }
        }
        .onChange(of: isPressed) { _, pressed in
            guard pressed, isEnabled else { return }
            HapticManager.prepareForRecordButton()
        }
        // VoiceOver can't hold and release, so activation toggles instead:
        // activate to start, activate again to stop and copy. Touch-and-hold
        // still works through VoiceOver's pass-through gesture.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isRecording ? "Listening" : "")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, !isProcessing else { return }

            if isRecording {
                stop()
            } else {
                HapticManager.buttonPressed()
                start()
            }
        }
    }

    private var accessibilityLabel: String {
        if let accessibilityLabelOverride {
            return accessibilityLabelOverride
        }
        if !isEnabled {
            return "Recording unavailable"
        }

        return isRecording ? "Stop dictation" : "Start dictation"
    }

    private var accessibilityHint: String {
        guard isEnabled, accessibilityLabelOverride == nil else { return "" }
        return isRecording
            ? "Stops listening and copies the text."
            : "Starts listening. Activate again to stop and copy the text."
    }
}

/// The disc itself: fill, shadow, icon and one-word title. Shared by the
/// hold-to-record control and the tap-to-fix disc, so both read as one object.
struct RecordDiscFace: View {
    @Environment(\.vyrraAccentColor) private var accentColor

    let title: String
    let systemImage: String
    let tone: RecordButtonTone
    let diameter: CGFloat
    var isProcessing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tone.fill(accentColor: accentColor))
                .frame(width: diameter, height: diameter)
                .shadow(color: Color.primary.opacity(tone == .disabled ? 0.04 : 0.18), radius: 18, y: 10)

            if isProcessing {
                ProgressView()
                    .tint(tone.foreground)
                    .scaleEffect(1.25)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: systemImage)
                        .font(.system(size: max(22, diameter * 0.24), weight: .semibold))

                    Text(title)
                        .font(.system(size: max(17, diameter * 0.13), weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(tone.foreground)
                .frame(width: diameter * 0.76)
            }
        }
    }
}

/// The disc's press: a subtle, critically damped shrink with no overshoot;
/// under Reduce Motion it dims instead of scaling.
struct RecordDiscPress: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isPressed && reduceMotion ? 0.86 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.18), value: isPressed)
    }
}

/// A tap (not hold) disc, for states where the disc's one job is a fix such
/// as opening Settings. It presses exactly like the record disc.
struct RecordDiscButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(RecordDiscPress(isPressed: configuration.isPressed))
    }
}

#Preview {
    RecordButton(
        title: "Hold",
        systemImage: "mic.fill",
        isRecording: false,
        isProcessing: false,
        tone: .ready,
        isEnabled: true,
        start: {},
        stop: {}
    )
}
