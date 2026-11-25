import UIKit

final class KeyboardWaveformView: UIView {
    enum Activity: Equatable {
        case idle
        case listening
    }

    var activity: Activity = .idle {
        didSet {
            guard activity != oldValue else { return }
            updateAnimations()
        }
    }

    override var tintColor: UIColor! {
        didSet { updateBarColors() }
    }

    // The resting silhouette is also the still listening indicator for Reduce Motion.
    private let peaks: [CGFloat] = [0.32, 0.55, 0.43, 0.73, 0.88, 1, 0.57, 0.89, 0.71, 0.49, 0.32]
    private var barLayers: [CALayer] = []
    private var laidOutSize: CGSize = .zero
    var levelSource: (() -> CGFloat)? { didSet { updateAnimations() } }
    private var meterTimer: Timer?
    private var recentLevels: [CGFloat] = Array(repeating: 0, count: 11)
    // Read on every transition, including changes while the keyboard is visible.
    var reduceMotionEnabled: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        meterTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionPreferenceChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )

        for _ in peaks {
            let bar = CALayer()
            bar.masksToBounds = true
            layer.addSublayer(bar)
            barLayers.append(bar)
        }
        updateBarColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        updateAnimations()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Extensions can be detached and reused as the host changes focus.
        // Stop work offscreen and resume a still-active session on reattachment.
        updateAnimations()
    }

    private func updateBarColors() {
        let color = (tintColor ?? .label).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayers.forEach { $0.backgroundColor = color }
        CATransaction.commit()
    }

    private func updateAnimations() {
        meterTimer?.invalidate()
        meterTimer = nil
        guard bounds.width > 0, bounds.height > 0 else { return }
        let width = bounds.width / CGFloat(2 * peaks.count - 1)
        let animates = activity == .listening && window != nil && !reduceMotionEnabled()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let peak = bounds.height * peaks[index]
            let resting = max(width, peak * 0.87)
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: resting)
            bar.position = CGPoint(x: bounds.minX + (CGFloat(index) * 2 + 0.5) * width, y: bounds.midY)
            bar.cornerRadius = width / 2
            bar.removeAllAnimations()
            guard animates, levelSource == nil else { continue }

            // Animate height so the rounded ends keep their radius at every amplitude.
            let pulse = CAKeyframeAnimation(keyPath: "bounds.size.height")
            pulse.values = [resting, peak, max(width, peak * 0.42), resting]
            pulse.keyTimes = [0, 0.26, 0.68, 1]
            pulse.calculationMode = .cubic
            pulse.duration = 0.88 + Double(index % 4) * 0.11
            pulse.timeOffset = Double((index * 5) % peaks.count) / Double(peaks.count) * pulse.duration
            pulse.repeatCount = .infinity
            bar.add(pulse, forKey: "vyrra.keyboard.wave")
        }
        CATransaction.commit()
        if animates, levelSource != nil {
            recentLevels = Array(repeating: 0, count: peaks.count)
            updateMeter()
            let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in self?.updateMeter() }
            meterTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateMeter() {
        guard let read = levelSource else { return }
        recentLevels.removeFirst()
        recentLevels.append(min(1, max(0, read())))
        let width = bounds.width / CGFloat(2 * peaks.count - 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.085)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for (index, bar) in barLayers.enumerated() {
            let amplitude = recentLevels[index]
            let floor = width + (bounds.height * 0.13 * peaks[index])
            let height = floor + (bounds.height - floor) * sqrt(amplitude) * (0.55 + 0.45 * peaks[index])
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        }
        CATransaction.commit()
    }

    @objc private func reduceMotionPreferenceChanged() {
        updateAnimations()
    }
}
