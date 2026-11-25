import UIKit
#if KEYBOARD_TESTING
@testable import Vyrra
#endif

final class KeyboardDictationPanel: UIView {
    let cancelButton = UIButton(type: .system)
    let finishButton = UIButton(type: .system)
    let inputModeButton = UIButton(type: .system)
    let waveform = KeyboardWaveformView()

    private let pauseMark = UIImageView(image: UIImage(systemName: "pause.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 27, weight: .semibold)))

    private let caption = UILabel()
    private lazy var microphoneMeter = KeyboardLevelMeter(writable: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "dictation-panel"
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12)
        insetsLayoutMarginsFromSafeArea = false
        waveform.levelSource = { [weak self] in CGFloat(self?.microphoneMeter?.latest() ?? 0) }

        configure(cancelButton, symbol: "xmark", label: "Cancel Vyrra dictation")
        cancelButton.accessibilityHint = "Discards this phrase and returns to typing."
        configure(finishButton, symbol: "checkmark", label: "Finish Vyrra dictation")
        finishButton.accessibilityHint = "Ends recording and prepares your text."
        configure(inputModeButton, symbol: "globe", label: "Next keyboard")

        for mark in [waveform, pauseMark] {
            mark.translatesAutoresizingMaskIntoConstraints = false
            mark.isAccessibilityElement = false
            addSubview(mark)
            NSLayoutConstraint.activate([
                mark.centerXAnchor.constraint(equalTo: centerXAnchor),
                mark.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6)
            ])
        }
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.font = .preferredFont(forTextStyle: .caption1)
        caption.adjustsFontForContentSizeCategory = true
        caption.isAccessibilityElement = false
        caption.textAlignment = .center
        addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.topAnchor.constraint(equalTo: waveform.bottomAnchor, constant: 3)
        ])
        pauseMark.isHidden = true
        let margins = layoutMarginsGuide
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            cancelButton.topAnchor.constraint(equalTo: margins.topAnchor),
            finishButton.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            finishButton.topAnchor.constraint(equalTo: margins.topAnchor),
            inputModeButton.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            inputModeButton.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 156),
            waveform.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: UIButton, symbol: String, label: String) {
        let symbolStyle = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: symbolStyle), for: .normal)
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        let size = KeyboardGeometry.primaryControlSize
        button.layer.cornerRadius = size / 2
        addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
        ])
    }

    func update(for state: KeyboardSessionState, pending: KeyboardSessionCommandType?) {
        let phase: String
        if pending == .cancel { phase = String(localized: "Canceling…") }
        else if pending == .finish || state == .processing { phase = String(localized: "Finishing…") }
        else if state == .paused { phase = String(localized: "Paused") }
        else { phase = String(localized: "Listening") }
        let live = state == .listening && pending == nil
        waveform.isHidden = state == .paused
        waveform.activity = live ? .listening : .idle
        pauseMark.isHidden = state != .paused
        finishButton.isEnabled = pending == nil && state != .processing
        cancelButton.isEnabled = pending == nil && state != .processing
        caption.text = phase
        finishButton.accessibilityValue = phase.replacingOccurrences(of: "…", with: "")
        cancelButton.accessibilityValue = pending == .cancel ? phase : nil
    }

    func apply(_ palette: KeyboardPalette) {
        let ink = palette.text.withAlphaComponent(0.82)
        caption.textColor = ink
        waveform.tintColor = ink
        pauseMark.tintColor = ink
        cancelButton.backgroundColor = palette.key
        cancelButton.tintColor = palette.text
        finishButton.backgroundColor = ink
        finishButton.tintColor = palette.primaryText
        inputModeButton.tintColor = palette.text
    }
}
