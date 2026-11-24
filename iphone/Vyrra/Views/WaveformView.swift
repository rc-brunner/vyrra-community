import SwiftUI

struct WaveformView: View, Animatable {
    @Environment(\.vyrraAccentColor) private var accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var level: Double
    let isActive: Bool
    var isMuted: Bool = false
    var isPreparing: Bool = false
    var preparationProgress: Double?
    var motion: WaveformMotion = .flow

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, preparationProgress ?? -1) }
        set {
            level = newValue.first
            if preparationProgress != nil {
                preparationProgress = newValue.second
            }
        }
    }

    private var barCount: Int { motion.barCount }

    private var nominalBarWidth: CGFloat {
        motion == .detail ? 4.2 : 5.2
    }

    private var nominalBarSpacing: CGFloat {
        motion == .calm ? 4.4 : 3.8
    }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.animation) { timeline in
                    waveformCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                waveformCanvas(time: 0)
            }
        }
        .accessibilityHidden(true)
    }

    private var shouldAnimate: Bool {
        !reduceMotion && (isActive || isPreparing)
    }

    private func waveformCanvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            let maxBarHeight = max(size.height - 8, 1)
            let baseHeight = max(maxBarHeight * 0.12, min(10, maxBarHeight * 0.42))
            let metrics = barMetrics(for: size.width)
            let startX = (size.width - metrics.totalWidth) / 2

            for index in 0..<barCount {
                let idleHeight = baseHeight
                    + CGFloat(sin(Double(index) * 0.62) + 1) * maxBarHeight * 0.026
                let activeHeight = activeRecordingHeight(
                    index: index,
                    time: time,
                    baseHeight: baseHeight,
                    maxBarHeight: maxBarHeight
                )
                let preparingHeight = preparationHeight(
                    index: index,
                    time: time,
                    baseHeight: baseHeight,
                    maxBarHeight: maxBarHeight
                )
                let barHeight = min(maxBarHeight, isPreparing ? preparingHeight : (isActive ? activeHeight : idleHeight))
                let x = startX + CGFloat(index) * (metrics.width + metrics.spacing)
                let rect = CGRect(
                    x: x,
                    y: (size.height - barHeight) / 2,
                    width: metrics.width,
                    height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: metrics.width / 2)

                context.fill(path, with: .color(barColor(index: index, time: time)))
            }
        }
    }

    private func barMetrics(for availableWidth: CGFloat) -> (width: CGFloat, spacing: CGFloat, totalWidth: CGFloat) {
        let count = CGFloat(barCount)
        let nominalTotalWidth = nominalBarWidth * count + nominalBarSpacing * (count - 1)
        guard nominalTotalWidth > availableWidth else {
            return (nominalBarWidth, nominalBarSpacing, nominalTotalWidth)
        }

        let scale = max(availableWidth / nominalTotalWidth, 0)
        return (
            nominalBarWidth * scale,
            nominalBarSpacing * scale,
            nominalTotalWidth * scale
        )
    }

    private func barColor(index: Int, time: TimeInterval) -> Color {
        if isMuted {
            return Color.secondary.opacity(0.20)
        }

        if isPreparing {
            if let preparationProgress {
                let fill = preparationFill(index: index, progress: preparationProgress)
                let crest = preparationCrest(index: index, progress: preparationProgress)
                let drift = (sin(time * 1.4 + Double(index) * 0.28) + 1) / 2
                let opacity = 0.16 + fill * 0.52 + crest * 0.16 + drift * fill * 0.08
                return fill > 0.02 ? accentColor.opacity(opacity) : Color.secondary.opacity(0.16)
            }

            let scanner = (sin(scaledTime(time) * 2.0 + Double(index) * 0.34) + 1) / 2
            return accentColor.opacity(0.20 + scanner * 0.36)
        }

        if isActive {
            let flow = (sin(scaledTime(time) * 2.8 + Double(index) * 0.42) + 1) / 2
            let pulse = (sin(scaledTime(time) * 5.6 - Double(index) * 0.28) + 1) / 2
            return accentColor.opacity(0.56 + flow * 0.16 + pulse * 0.08)
        }

        return Color.secondary.opacity(0.28)
    }

    private func activeRecordingHeight(
        index: Int,
        time: TimeInterval,
        baseHeight: CGFloat,
        maxBarHeight: CGFloat
    ) -> CGFloat {
        let clampedLevel = min(max(level, 0), 1)
        let voiceLevel = pow(clampedLevel, 0.54)
        let motionTime = scaledTime(time)
        let slowFlow = (sin(motionTime * 2.6 + Double(index) * 0.42) + 1) / 2
        let crossFlow = (sin(motionTime * 4.1 - Double(index) * 0.34) + 1) / 2
        let fineMotion = (sin(motionTime * 7.2 + Double(index) * 0.68) + 1) / 2
        let staticShape = (sin(Double(index) * 0.52) + 1) / 2
        let center = Double(barCount - 1) / 2
        let centerDistance = abs(Double(index) - center) / max(center, 1)
        let centerPulse = max(0, 1 - centerDistance)
        let quietCurrent = 0.075 + slowFlow * 0.035 + crossFlow * 0.025 + staticShape * 0.020
        let voiceLift = voiceLevel * motion.energyMultiplier * (
            0.34
            + centerPulse * 0.34
            + staticShape * 0.09
            + slowFlow * 0.12
            + crossFlow * 0.08
            + fineMotion * 0.06
        )
        let heightRatio = min(0.90, quietCurrent + voiceLift)

        return baseHeight + maxBarHeight * CGFloat(heightRatio)
    }

    private func preparationHeight(
        index: Int,
        time: TimeInterval,
        baseHeight: CGFloat,
        maxBarHeight: CGFloat
    ) -> CGFloat {
        let indexWave = (sin(Double(index) * 0.7) + 1) / 2

        if let preparationProgress {
            let fill = preparationFill(index: index, progress: preparationProgress)
            let crest = preparationCrest(index: index, progress: preparationProgress)
            let breathing = (sin(scaledTime(time) * 1.35 + Double(index) * 0.31) + 1) / 2
            let quiet = 0.055 + CGFloat(indexWave) * 0.035
            let lift = CGFloat(fill) * (0.13 + CGFloat(breathing) * 0.045)
            let crestLift = CGFloat(crest) * 0.16

            return baseHeight + maxBarHeight * (quiet + lift + crestLift)
        }

        let scanner = (sin(scaledTime(time) * 2.0 + Double(index) * 0.34) + 1) / 2
        return baseHeight + maxBarHeight * (0.08 + CGFloat(scanner) * 0.20 + CGFloat(indexWave) * 0.035)
    }

    private func scaledTime(_ time: TimeInterval) -> TimeInterval {
        time * motion.speedMultiplier
    }

    private func preparationFill(index: Int, progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        let position = Double(index) / Double(max(barCount - 1, 1))
        return 1 - smoothStep(edge0: clampedProgress - 0.12, edge1: clampedProgress + 0.10, x: position)
    }

    private func preparationCrest(index: Int, progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        let position = Double(index) / Double(max(barCount - 1, 1))
        let distance = abs(position - clampedProgress)
        return max(0, 1 - distance / 0.13)
    }

    private func smoothStep(edge0: Double, edge1: Double, x: Double) -> Double {
        guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct VyrraWaveformPill: View {
    let level: Double
    let isActive: Bool
    var isMuted = false
    var isPreparing = false
    var preparationProgress: Double?
    var motion: WaveformMotion = .flow
    var height: CGFloat = 64
    var accessibilityDescription: String?

    var body: some View {
        WaveformView(
            level: level,
            isActive: isActive,
            isMuted: isMuted,
            isPreparing: isPreparing,
            preparationProgress: preparationProgress,
            motion: motion
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.primary.opacity(0.045), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription ?? accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityLabel: String {
        if isMuted {
            return "Voice input unavailable"
        }
        if isPreparing {
            return "Preparing voice model"
        }
        return isActive ? "Voice level" : "Voice waveform"
    }

    private var accessibilityValue: String {
        if isMuted {
            return "Unavailable"
        }
        if isPreparing {
            guard let preparationProgress else {
                return "In progress"
            }
            return "\(Int(min(max(preparationProgress, 0), 1) * 100)) percent"
        }
        guard isActive else {
            return "Idle"
        }
        switch level {
        case ..<0.2:
            return "Low"
        case 0.6...:
            return "High"
        default:
            return "Medium"
        }
    }
}

#Preview {
    VyrraWaveformPill(level: 0.5, isActive: true)
        .padding()
}
