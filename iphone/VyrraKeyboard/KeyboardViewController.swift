import UIKit
#if KEYBOARD_TESTING
@testable import Vyrra
#endif

class KeyboardViewController: UIInputViewController {
    private let containerStack = UIStackView()
    private let commandBar = UIStackView()
    private let vyrraButton = UIButton(type: .system)
    private static let voiceMark = UIImage(named: "VyrraMark", in: Bundle(for: KeyboardViewController.self), compatibleWith: nil)
        ?? UIImage(systemName: "waveform")
    private let dictationPanel = KeyboardDictationPanel()
    private let menuButton = UIButton(type: .system)
    private let keyboardShell = KeyboardTouchRegion()
    private let keyboardStack = UIStackView()
    private let guidanceBubble = UIView()
    private let guidanceLabel = UILabel()
    private var showsDictationPanel = false

    private var payload: KeyboardSharedPayload?
    private var pendingCommand: KeyboardSessionCommand?
    private var pollTimer: Timer?
    private var payloadObservation: KeyboardStoreObservation?
    private var keyButtons: [KeyboardKeyButton] = []
    private let keyPreview = UILabel()
    private var activeKeyTouches = 0
    private var isTrackpadActive = false
    private var lastShiftTap: TimeInterval?
    private var manualShift = false
    private var documentID: UUID?
    private var inputType: UIKeyboardType = .default
    private var hasSharedContainer = true
    private var hasRenderedPayload = false
    private var keyboardMode: KeyboardMode = .letters
    private var shiftState: KeyboardShiftState = .lower
    private var showsInputModeSwitchKey = true
    private var lastRenderedKeyboardSignature = ""
    private var lastPayloadReadSignature: String?
    private var primaryAction: KeyboardPrimaryAction = .quickStart
    private var guidanceResetWorkItem: DispatchWorkItem?
    private var consumedAutomaticInsertionSessionIDs: Set<String> = []
    private var pendingSpaceTap: KeyboardSpaceTap?
    private let presenceID = UUID().uuidString
    private var lastPresenceWrite = Date.distantPast
    private var isKeyboardVisible = false
    private var appearance = KeyboardAppearancePreferences()
    private var preferredHeightConstraint: NSLayoutConstraint?
    private var keyRowsHeightConstraint: NSLayoutConstraint?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    override func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showsInputModeSwitchKey = needsInputModeSwitchKey
        configureView()
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: KeyboardViewController, _) in
                controller.refreshAppearance()
            }
        }
        recordDiagnostic(.keyboardAppeared, detail: "viewDidLoad")
        reloadPayload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isKeyboardVisible = true
        payloadObservation = KeyboardStoreObservation(.payload) { [weak self] in
            guard let self, self.isKeyboardVisible, self.hasFullAccess else { return }
            self.reloadPayload()
        }
        publishPresence(force: true)
        recordDiagnostic(.keyboardAppeared, detail: "viewWillAppear")
        recordDiagnostic(.fullAccessState, detail: hasFullAccess ? "on" : "off")
        hasRenderedPayload = false
        synchronizeInputTraits()
        reloadPayload()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isKeyboardVisible = false
        payloadObservation = nil
        publishPresence(force: true)
        stopPolling()
        applySurfaceTransition(animated: false)
        dictationPanel.waveform.activity = .idle
        keyButtons.forEach { $0.cancelTrackingTouch() }
        dismissGuidance()
        pendingSpaceTap = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        synchronizeInputTraits()
        updateColors()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if let pendingSpaceTap,
           pendingSpaceTap.expectedContextBeforeInput != textDocumentProxy.documentContextBeforeInput
            || pendingSpaceTap.expectedContextAfterInput != (textDocumentProxy.documentContextAfterInput ?? "")
            || textDocumentProxy.selectedText?.isEmpty == false {
            self.pendingSpaceTap = nil
        }
        manualShift = false
        synchronizeInputTraits()
    }

    private func synchronizeInputTraits() {
        let newType = textDocumentProxy.keyboardType ?? .default
        if documentID != textDocumentProxy.documentIdentifier || inputType != newType {
            documentID = textDocumentProxy.documentIdentifier
            inputType = newType
            keyboardMode = KeyboardInputPolicy.startsWithNumbers(newType) ? .symbols : .letters
            shiftState = .lower
            manualShift = false
            lastShiftTap = nil
            pendingSpaceTap = nil
        }
        showsInputModeSwitchKey = needsInputModeSwitchKey
        dictationPanel.inputModeButton.isHidden = !showsInputModeSwitchKey
        if shiftState != .locked, !manualShift {
            shiftState = KeyboardInputPolicy.capitalizes(
                textDocumentProxy.autocapitalizationType ?? .sentences,
                before: textDocumentProxy.documentContextBeforeInput,
                hasText: textDocumentProxy.hasText
            ) ? .upper : .lower
        }
        rebuildKeyboardRowsIfNeeded()
    }

    private func refreshAppearance() {
        lastRenderedKeyboardSignature = ""
        rebuildKeyboardRowsIfNeeded(force: true)
        updateColors()
    }

    private func configureView() {
        view.backgroundColor = palette.background
        view.clipsToBounds = true

        let height = view.heightAnchor.constraint(equalToConstant: appearance.size.contentHeight)
        preferredHeightConstraint = height
        height.priority = .required
        height.isActive = true

        containerStack.axis = .vertical
        containerStack.spacing = KeyboardGeometry.sectionGap
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: KeyboardGeometry.horizontalInset),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -KeyboardGeometry.horizontalInset),
            containerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: KeyboardGeometry.topInset),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -KeyboardGeometry.bottomInset)
        ])

        configureCommandBar()
        containerStack.addArrangedSubview(commandBar)

        configureKeyboardShell()
        containerStack.addArrangedSubview(keyboardShell)
        configureDictationPanel()
        configureGuidanceBubble()

        keyPreview.isHidden = true
        keyPreview.isUserInteractionEnabled = false
        keyPreview.isAccessibilityElement = false
        keyPreview.accessibilityIdentifier = "key-character-preview"
        keyPreview.textAlignment = .center
        keyPreview.font = .systemFont(ofSize: 32)
        keyPreview.layer.cornerRadius = KeyboardGeometry.cornerRadius
        keyPreview.layer.cornerCurve = .continuous
        keyPreview.clipsToBounds = true
        view.addSubview(keyPreview)
        rebuildKeyboardRowsIfNeeded(force: true)
        updateColors()
    }

    private func configureCommandBar() {
        commandBar.axis = .horizontal
        commandBar.alignment = .center
        commandBar.spacing = 8
        commandBar.heightAnchor.constraint(equalToConstant: KeyboardGeometry.commandBarHeight).isActive = true

        configureIconButton(vyrraButton, size: KeyboardGeometry.primaryControlSize)
        vyrraButton.configuration?.image = Self.voiceMark
        vyrraButton.configurationUpdateHandler = { button in
            guard let icon = button.imageView else { return }
            let pressed = button.isHighlighted && !UIAccessibility.isReduceMotionEnabled
            let scale = pressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            guard icon.transform != scale else { return }
            if UIAccessibility.isReduceMotionEnabled {
                icon.transform = .identity
            } else {
                UIView.animate(withDuration: pressed ? 0.08 : 0.16, delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                    icon.transform = scale
                }
            }
        }
        vyrraButton.accessibilityLabel = "How to start Vyrra dictation"
        vyrraButton.accessibilityHint = "Shows how to start a recording and return to this keyboard."
        vyrraButton.addAction(UIAction { [weak self] _ in
            self?.prepareImpact()
        }, for: .touchDown)
        vyrraButton.addAction(UIAction { [weak self] _ in
            self?.handleVyrraButton()
        }, for: .touchUpInside)

        configureIconButton(menuButton, size: KeyboardGeometry.secondaryControlSize)
        menuButton.configuration?.image = UIImage(systemName: "line.3.horizontal")
        menuButton.accessibilityLabel = "Vyrra keyboard menu"
        menuButton.showsMenuAsPrimaryAction = true

        commandBar.addArrangedSubview(vyrraButton)
        commandBar.addArrangedSubview(UIView())
        commandBar.addArrangedSubview(menuButton)
    }

    private func configureDictationPanel() {
        dictationPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dictationPanel)
        NSLayoutConstraint.activate([
            dictationPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dictationPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dictationPanel.topAnchor.constraint(equalTo: view.topAnchor),
            dictationPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        for (button, command) in [(dictationPanel.cancelButton, KeyboardSessionCommandType.cancel),
                                  (dictationPanel.finishButton, .finish)] {
            button.addAction(UIAction { [weak self] _ in self?.prepareImpact() }, for: .touchDown)
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.showsDictationPanel, self.primaryAction == .finish,
                      let session = self.payload?.session else { return }
                self.dismissGuidance()
                self.requestSessionCommand(command, session: session)
            }, for: .touchUpInside)
        }
        dictationPanel.inputModeButton.isHidden = !showsInputModeSwitchKey
        dictationPanel.inputModeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        dictationPanel.accessibilityElementsHidden = true
        dictationPanel.isUserInteractionEnabled = false
        applySurfaceTransition(animated: false)
    }

    private func setDictationPanelVisible(_ visible: Bool, animated: Bool) {
        guard visible != showsDictationPanel else { return }
        showsDictationPanel = visible
        containerStack.isUserInteractionEnabled = !visible
        containerStack.accessibilityElementsHidden = visible
        dictationPanel.isUserInteractionEnabled = visible
        dictationPanel.accessibilityElementsHidden = !visible
        if visible {
            keyButtons.forEach { $0.cancelTrackingTouch() }
            keyPreview.isHidden = true
            pendingSpaceTap = nil
        }
        applySurfaceTransition(animated: animated)
    }

    private func applySurfaceTransition(animated: Bool) {
        let visible = showsDictationPanel
        let reduceMotion = dictationPanel.waveform.reduceMotionEnabled()
        containerStack.isHidden = false
        dictationPanel.isHidden = false
        let layout = {
            self.containerStack.alpha = visible ? 0 : 1
            self.containerStack.transform = visible && !reduceMotion ? CGAffineTransform(translationX: 0, y: 24) : .identity
            self.dictationPanel.alpha = visible ? 1 : 0
            self.dictationPanel.transform = visible || reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: 12)
        }
        let settle = { [weak self] in
            guard let self, self.showsDictationPanel == visible else { return }
            self.containerStack.isHidden = visible
            self.dictationPanel.isHidden = !visible
            if !visible { self.dictationPanel.waveform.activity = .idle }
            if self.isKeyboardVisible, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .layoutChanged, argument: visible ? self.dictationPanel.finishButton : self.vyrraButton)
            }
        }
        if animated, !reduceMotion, isKeyboardVisible, view.window != nil {
            UIView.animate(withDuration: 0.28, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                           animations: layout) { finished in if finished { settle() } }
        } else {
            containerStack.layer.removeAllAnimations()
            dictationPanel.layer.removeAllAnimations()
            UIView.performWithoutAnimation(layout)
            settle()
        }
    }

    @objc private func reduceMotionChanged() {
        applySurfaceTransition(animated: false)
    }

    private func configureGuidanceBubble() {
        guidanceBubble.isHidden = true
        guidanceBubble.translatesAutoresizingMaskIntoConstraints = false
        guidanceBubble.layer.cornerRadius = KeyboardGeometry.cornerRadius
        guidanceBubble.layer.cornerCurve = .continuous
        guidanceBubble.layoutMargins = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        guidanceBubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissGuidance)))
        view.addSubview(guidanceBubble)

        guidanceLabel.translatesAutoresizingMaskIntoConstraints = false
        guidanceLabel.accessibilityIdentifier = "keyboard-guidance"
        guidanceLabel.font = .systemFont(ofSize: 12, weight: .medium)
        guidanceLabel.numberOfLines = 0
        guidanceBubble.addSubview(guidanceLabel)
        let margins = guidanceBubble.layoutMarginsGuide
        NSLayoutConstraint.activate([
            guidanceBubble.leadingAnchor.constraint(equalTo: vyrraButton.leadingAnchor),
            guidanceBubble.topAnchor.constraint(equalTo: vyrraButton.bottomAnchor, constant: 4),
            guidanceBubble.trailingAnchor.constraint(lessThanOrEqualTo: commandBar.trailingAnchor),
            guidanceLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            guidanceLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            guidanceLabel.topAnchor.constraint(equalTo: margins.topAnchor),
            guidanceLabel.bottomAnchor.constraint(equalTo: margins.bottomAnchor)
        ])
    }

    private func configureIconButton(_ button: UIButton, size: CGFloat) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: size == KeyboardGeometry.primaryControlSize ? 24 : 20,
            weight: .semibold
        )
        button.configuration = configuration
        button.layer.cornerRadius = size / 2
        button.layer.cornerCurve = .continuous
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        button.imageView?.contentMode = .scaleAspectFit
    }

    private func configureKeyboardShell() {
        keyboardShell.translatesAutoresizingMaskIntoConstraints = false
        let shellHeight = keyboardShell.heightAnchor.constraint(equalToConstant: appearance.size.keyRowsHeight)
        keyRowsHeightConstraint = shellHeight
        shellHeight.priority = .required
        shellHeight.isActive = true
        keyboardShell.setContentCompressionResistancePriority(.required, for: .vertical)
        keyboardShell.setContentHuggingPriority(.required, for: .vertical)

        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fill
        keyboardStack.spacing = appearance.size.rowGap
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        keyboardShell.addSubview(keyboardStack)

        NSLayoutConstraint.activate([
            keyboardStack.leadingAnchor.constraint(equalTo: keyboardShell.leadingAnchor),
            keyboardStack.trailingAnchor.constraint(equalTo: keyboardShell.trailingAnchor),
            keyboardStack.topAnchor.constraint(equalTo: keyboardShell.topAnchor),
            keyboardStack.bottomAnchor.constraint(equalTo: keyboardShell.bottomAnchor)
        ])
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reloadPayload()
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Whether the App Group is reachable, and its payload. Tests override this
    /// to render session states without touching the shared container.
    func readSharedPayload() -> (hasSharedContainer: Bool, payload: KeyboardSharedPayload?) {
        let hasSharedContainer = hasFullAccess && KeyboardSharedStore.defaultContainerURL() != nil
        return (hasSharedContainer, hasSharedContainer ? try? KeyboardSharedStore.read() : nil)
    }

    func writeSharedCommand(_ command: KeyboardSessionCommand) throws {
        try KeyboardSharedStore.writeCommand(command)
    }

    func reloadPayload() {
        publishPresence()
        reloadAppearance()
        let previousContainer = hasSharedContainer
        let previousPayload = payload
        let previousCommand = pendingCommand
        let (newHasSharedContainer, newPayload) = readSharedPayload()
        hasSharedContainer = newHasSharedContainer
        payload = newPayload
        let session = effectiveSession(newPayload?.session ?? .ready())
        let confirmedAction = KeyboardPrimaryActionResolver.action(for: session, activation: newPayload?.activation)
        let guidance = reconcilePendingCommand(for: session, confirmedAction: confirmedAction)
        let action = pendingCommand == nil ? confirmedAction : .wait
        recordPayloadReadIfNeeded()

        guard !hasRenderedPayload || previousContainer != newHasSharedContainer
            || previousPayload != newPayload || previousCommand != pendingCommand || action != primaryAction
        else { return }
        let animated = hasRenderedPayload
        hasRenderedPayload = true
        renderPayload(animated: animated)
        if let guidance { showGuidance(guidance) }
    }

    private func publishPresence(force: Bool = false) {
        guard hasFullAccess else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPresenceWrite) >= 2 else { return }
        lastPresenceWrite = now
        try? KeyboardSharedStore.writePresence(KeyboardPresencePayload(
            id: presenceID, isVisible: isKeyboardVisible, updatedAt: now
        ))
    }

    private func reloadAppearance() {
        guard let newAppearance = try? KeyboardSharedStore.readAppearance(), newAppearance != appearance else { return }
        appearance = newAppearance
        preferredHeightConstraint?.constant = appearance.size.contentHeight
        keyRowsHeightConstraint?.constant = appearance.size.keyRowsHeight
        keyboardStack.spacing = appearance.size.rowGap
        guidanceLabel.font = .systemFont(ofSize: 12 * appearance.textSize.scale, weight: .medium)
        rebuildKeyboardRowsIfNeeded(force: true)
        view.setNeedsLayout()
    }

    private func recordPayloadReadIfNeeded() {
        let sessionState = payload?.session?.state.rawValue ?? "none"
        let readinessState = payload?.session?.voiceReadiness?.state.rawValue ?? "unknown"
        let hasDraft = normalized(payload?.latestDraft) == nil ? "noDraft" : "draft"
        let shortcutCount = payload?.shortcuts.count ?? 0
        let tone = payload?.polishingMode?.rawValue ?? "unknown"
        let signature = "\(hasSharedContainer)-\(sessionState)-\(readinessState)-\(hasDraft)-\(shortcutCount)-\(tone)"
        guard signature != lastPayloadReadSignature else { return }
        lastPayloadReadSignature = signature
        recordDiagnostic(.payloadRead, detail: signature)
    }

    private func renderPayload(animated: Bool = true) {
        let session = effectiveSession(payload?.session ?? .ready())
        let displayState: KeyboardSessionState = switch pendingCommand?.type {
        case .start: .opening
        case .finish: .processing
        default: session.state
        }
        let action = pendingCommand == nil
            ? KeyboardPrimaryActionResolver.action(for: session, activation: payload?.activation)
            : .wait
        if action != primaryAction { dismissGuidance() }
        primaryAction = action

        // Enter only on confirmed capture. An old payload after a finish/cancel
        // tap must not bring back the keys or re-enable the other button.
        let inPhrase = session.state == .listening || session.state == .paused
        let endingPhrase = pendingCommand?.type == .finish || pendingCommand?.type == .cancel
        let finishing = session.state == .processing && showsDictationPanel
        let showPanel = hasSharedContainer && (inPhrase || endingPhrase || finishing)
        if showPanel {
            dictationPanel.update(for: session.state, pending: pendingCommand?.type)
        }
        if !showPanel {
            configureVyrraButton(for: displayState)
            menuButton.menu = keyboardMenu(for: session, displayState: displayState)
        }
        setDictationPanelVisible(showPanel, animated: animated)
        rebuildKeyboardRowsIfNeeded()
        updateColors()
        consumeAutomaticInsertionIfNeeded(session)
    }

    private func configureVyrraButton(for state: KeyboardSessionState) {
        let icon: UIImage?
        vyrraButton.accessibilityValue = primaryAction == .start ? "Microphone on" : nil
        switch primaryAction {
        case .start:
            icon = Self.voiceMark
            vyrraButton.accessibilityLabel = "Start Vyrra dictation"
            vyrraButton.accessibilityHint = "Starts a phrase in your active keyboard session."
        case .quickStart:
            icon = Self.voiceMark
            vyrraButton.accessibilityLabel = !hasSharedContainer
                ? "Set up Vyrra keyboard"
                : "How to start Vyrra dictation"
            vyrraButton.accessibilityHint = hasSharedContainer
                ? "Shows how to start a recording and return to this keyboard."
                : "Opens Settings. Full Access enables local session status and insertion."
        case .attention:
            icon = UIImage(systemName: "exclamationmark")
            vyrraButton.accessibilityLabel = "Vyrra needs attention"
            vyrraButton.accessibilityHint = "Open Vyrra from the Home Screen to resolve the last dictation."
        case .finish:
            icon = UIImage(systemName: "checkmark")
            vyrraButton.accessibilityLabel = "Finish Vyrra dictation"
            vyrraButton.accessibilityHint = "Finishes this recording and prepares the text."
        case .insertResult:
            icon = UIImage(systemName: "arrow.down.doc")
            vyrraButton.accessibilityLabel = "Insert Vyrra result"
            vyrraButton.accessibilityHint = "Inserts the completed dictation at the cursor."
        case .wait:
            icon = state == .opening || state == .warming ? Self.voiceMark : UIImage(systemName: "ellipsis")
            switch state {
            case .opening:
                vyrraButton.accessibilityLabel = "Vyrra is starting dictation"
                vyrraButton.accessibilityHint = "Wait for Vyrra to start listening."
            case .warming:
                vyrraButton.accessibilityLabel = "Vyrra is preparing voice"
                vyrraButton.accessibilityHint = "Keep Vyrra open. This can take a minute or two."
            default:
                vyrraButton.accessibilityLabel = "Vyrra is preparing text"
                vyrraButton.accessibilityHint = "Your dictation will appear when it is ready."
            }
        }

        if vyrraButton.configuration?.image != icon {
            UIView.performWithoutAnimation { vyrraButton.configuration?.image = icon }
        }
    }

    private func keyboardMenu(for session: KeyboardSessionPayload, displayState: KeyboardSessionState) -> UIMenu {
        var actions: [UIMenuElement] = []

        if payload?.activation?.isCurrent() == true {
            actions.append(UIAction(title: "Stop Keyboard Session", image: UIImage(systemName: "mic.slash")) { [weak self] _ in
                self?.requestSessionCommand(.endKeyboardSession, session: session)
            })
        }

        if normalized(payload?.latestDraft) != nil {
            actions.append(UIAction(title: "Insert Last Draft", image: UIImage(systemName: "arrow.down.doc")) { [weak self] _ in
                self?.insertLastDraft()
            })
        }

        for shortcut in usableShortcuts {
            let trigger = normalized(shortcut.trigger) ?? "Shortcut"
            actions.append(UIAction(title: trigger, image: UIImage(systemName: "text.badge.plus")) { [weak self] _ in
                guard let self, let text = self.normalized(shortcut.body) else { return }
                self.impact()
                self.recordDiagnostic(.shortcutTapped, detail: "insert")
                self.textDocumentProxy.insertText(text)
            })
        }

        if let stateAction = sessionStateAction(for: displayState, errorText: session.errorText) {
            actions.append(stateAction)
        }

        if !hasSharedContainer {
            actions.append(UIAction(
                title: "Full Access Off",
                image: UIImage(systemName: "lock"),
                attributes: .disabled
            ) { _ in })
        }

        actions.append(UIAction(title: "Hide Keyboard", image: UIImage(systemName: "keyboard.chevron.compact.down")) { [weak self] _ in
            self?.dismissKeyboard()
        })

        return UIMenu(children: actions)
    }

    private func sessionStateAction(for state: KeyboardSessionState, errorText: String?) -> UIAction? {
        let title: String
        let image: String

        switch state {
        case .opening, .warming:
            title = "Preparing in Vyrra"
            image = "hourglass"
        case .listening:
            title = "Listening in Vyrra"
            image = "waveform"
        case .paused:
            title = "Paused in Vyrra"
            image = "pause"
        case .processing:
            title = "Processing in Vyrra"
            image = "ellipsis"
        case .error:
            title = normalized(errorText) ?? "Vyrra Needs Attention"
            image = "exclamationmark.circle"
        case .ready, .insertReady, .inserted:
            return nil
        }

        return UIAction(title: title, image: UIImage(systemName: image), attributes: .disabled) { _ in }
    }

    private func handleVyrraButton() {
        dismissGuidance()
        let session = effectiveSession(payload?.session ?? .ready())
        let action = pendingCommand == nil
            ? KeyboardPrimaryActionResolver.action(for: session, activation: payload?.activation)
            : .wait
        switch action {
        case .start:
            requestSessionCommand(.start, session: session)
        case .quickStart:
            impact()
            if hasSharedContainer {
                recordDiagnostic(.primaryTapped, detail: "quickStartGuide")
                showGuidance("Open Vyrra or run Start Dictation")
            } else {
                recordDiagnostic(.primaryTapped, detail: "settings")
                openKeyboardSettings()
            }
        case .attention:
            impact()
            recordDiagnostic(.primaryTapped, detail: "attention")
            showGuidance("Open Vyrra to continue")
        case .finish:
            requestSessionCommand(.finish, session: session)
        case .insertResult:
            impact()
            guard let text = normalized(session.resultText) else { return }
            guard markSessionInserted(session) else {
                showGuidance("Couldn’t insert text. Try again.")
                return
            }
            if let sessionID = normalized(session.sessionID) {
                consumedAutomaticInsertionSessionIDs.insert(sessionID)
            }
            textDocumentProxy.insertText(text)
            recordDiagnostic(.insertTapped, detail: "session")
        case .wait:
            break
        }
    }

    private func openKeyboardSettings() {
        recordDiagnostic(.openAppRequested, detail: "settings")

        guard let url = URL(string: UIApplication.openSettingsURLString),
              let extensionContext
        else {
            recordDiagnostic(.openAppFailed, detail: "settings:unavailable")
            showGuidance("Turn on Full Access in Settings")
            return
        }

        extensionContext.open(url) { [weak self] didOpen in
            DispatchQueue.main.async {
                guard let self else { return }
                if didOpen {
                    self.recordDiagnostic(.openAppSucceeded, detail: "settings")
                } else {
                    self.recordDiagnostic(.openAppFailed, detail: "settings:denied")
                    self.showGuidance("Turn on Full Access in Settings")
                }
            }
        }
    }

    private func showGuidance(_ message: String) {
        guidanceResetWorkItem?.cancel()
        guidanceLabel.text = message
        guidanceBubble.isHidden = false
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissGuidance()
        }
        guidanceResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    @objc private func dismissGuidance() {
        guidanceResetWorkItem?.cancel()
        guidanceResetWorkItem = nil
        guidanceBubble.isHidden = true
    }

    private func insertLastDraft() {
        guard let text = normalized(payload?.latestDraft) else { return }
        impact()
        textDocumentProxy.insertText(text)
        recordDiagnostic(.insertTapped, detail: "latest")
    }

    private func requestSessionCommand(
        _ commandType: KeyboardSessionCommandType,
        session: KeyboardSessionPayload
    ) {
        guard pendingCommand == nil else { return }
        let isDictationTap = commandType != .endKeyboardSession
        let now = Date()
        let command = KeyboardSessionCommand(
            type: commandType,
            requestedAt: now,
            sessionID: commandType == .start || commandType == .endKeyboardSession
                ? payload?.activation?.id : session.sessionID,
            expiresAt: isDictationTap ? now.addingTimeInterval(VyrraSessionPolicy.keyboardTapResponseWindow) : nil
        )
        do {
            try writeSharedCommand(command)
            recordDiagnostic(.commandWriteSucceeded, detail: commandType.rawValue)
        } catch {
            recordDiagnostic(.commandWriteFailed, detail: commandType.rawValue)
            showGuidance("Couldn’t reach Vyrra. Try again.")
            return
        }

        if isDictationTap {
            pendingCommand = command
            renderPayload()
        }
    }

    private func reconcilePendingCommand(
        for session: KeyboardSessionPayload,
        confirmedAction: KeyboardPrimaryAction
    ) -> String? {
        guard let command = pendingCommand else { return nil }
        let isStarting = command.type == .start
        let acknowledgment = payload?.commandAcknowledgment
        let accepted = acknowledgment?.commandID == command.id ? acknowledgment?.accepted : nil
        let matchesPreviousState = isStarting
            ? (confirmedAction == .start || (session.state == .opening && accepted == true))
                && payload?.activation?.id == command.sessionID
            : confirmedAction == .finish && session.sessionID == command.sessionID
        guard hasSharedContainer, payload == nil || matchesPreviousState else {
            pendingCommand = nil
            if hasSharedContainer, command.type == .finish, accepted == true,
               session.sessionID == command.sessionID,
               [.processing, .insertReady, .inserted].contains(session.state) {
                playFinishFeedback()
            }
            return nil
        }

        // Accepting a start can precede microphone readiness. Wait for an actual
        // phase change and let older snapshots leave the pending UI in place.
        let deadline = accepted == true
            ? command.requestedAt.addingTimeInterval(VyrraSessionPolicy.openingStaleInterval)
            : command.expiresAt ?? command.requestedAt
        guard accepted == false || Date() >= deadline else { return nil }
        pendingCommand = nil
        switch command.type {
        case .start: return "Couldn’t start. Try again."
        case .cancel: return "Couldn’t cancel. Try again."
        default: return "Couldn’t finish. Try again."
        }
    }

    func playFinishFeedback() {
        guard isKeyboardVisible else { return }
        // The containing app plays the release sound at the end of capture.
        impact()
    }

    private func rebuildKeyboardRowsIfNeeded(force: Bool = false) {
        guard activeKeyTouches == 0 else { return }
        let signature = "\(keyboardMode)-\(shiftState)-\(showsInputModeSwitchKey)-\(traitCollection.userInterfaceStyle)-\(textDocumentProxy.keyboardAppearance?.rawValue ?? 0)-\(textDocumentProxy.returnKeyType?.rawValue ?? 0)-\(textDocumentProxy.hasText)-\(textDocumentProxy.enablesReturnKeyAutomatically == true)-\(appearance.size)-\(appearance.textSize)"
        guard force || signature != lastRenderedKeyboardSignature else { return }
        lastRenderedKeyboardSignature = signature

        keyboardStack.arrangedSubviews.forEach { view in
            keyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        keyButtons.removeAll()
        keyRows.forEach { keyboardStack.addArrangedSubview(makeKeyRow($0)) }
    }

    private var keyRows: [KeyboardRowSpec] {
        switch keyboardMode {
        case .letters:
            return [
                KeyboardRowSpec(
                    keys: "qwertyuiop".map { .text(String($0)) },
                    height: KeyboardGeometry.letterKeyHeight
                ),
                KeyboardRowSpec(
                    keys: "asdfghjkl".map { .text(String($0)) },
                    referenceUnitCount: 10,
                    height: KeyboardGeometry.letterKeyHeight
                ),
                KeyboardRowSpec(keys: [
                    KeySpec(kind: .shift, width: 1.25),
                    .text("z"),
                    .text("x"),
                    .text("c"),
                    .text("v"),
                    .text("b"),
                    .text("n"),
                    .text("m"),
                    KeySpec(kind: .delete, width: 1.25)
                ], height: KeyboardGeometry.letterKeyHeight, letterControls: true),
                KeyboardRowSpec(keys: bottomRow(modeTitle: "123"))
            ]
        case .symbols:
            return [
                KeyboardRowSpec(
                    keys: "1234567890".map { .text(String($0)) },
                    height: KeyboardGeometry.compactKeyHeight
                ),
                KeyboardRowSpec(
                    keys: ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { .text($0) },
                    height: KeyboardGeometry.compactKeyHeight
                ),
                KeyboardRowSpec(keys: [
                    KeySpec(kind: .modeSwitch("#+="), width: 1.25),
                    .text("."),
                    .text(","),
                    .text("?"),
                    .text("!"),
                    .text("'"),
                    KeySpec(kind: .delete, width: 1.25)
                ]),
                KeyboardRowSpec(keys: bottomRow(modeTitle: "ABC"))
            ]
        case .alternateSymbols:
            return [
                KeyboardRowSpec(
                    keys: ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { .text($0) },
                    height: KeyboardGeometry.compactKeyHeight
                ),
                KeyboardRowSpec(
                    keys: ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { .text($0) },
                    height: KeyboardGeometry.compactKeyHeight
                ),
                KeyboardRowSpec(keys: [
                    KeySpec(kind: .modeSwitch("123"), width: 1.25),
                    .text("."),
                    .text(","),
                    .text("?"),
                    .text("!"),
                    .text("'"),
                    KeySpec(kind: .delete, width: 1.25)
                ]),
                KeyboardRowSpec(keys: bottomRow(modeTitle: "ABC"))
            ]
        }
    }

    private func bottomRow(modeTitle: String) -> [KeySpec] {
        var row: [KeySpec] = [KeySpec(kind: .modeSwitch(modeTitle), width: 1.35)]
        if showsInputModeSwitchKey {
            row.append(KeySpec(kind: .globe, width: 1.15))
        }
        let usesAddressKeys = inputType == .emailAddress || inputType == .URL
        row.append(KeySpec(kind: .space, width: usesAddressKeys ? 3.8 : 6))
        if usesAddressKeys {
            row.append(.text(inputType == .emailAddress ? "@" : "/", width: 1))
            row.append(.text(".", width: 1))
        }
        row.append(KeySpec(kind: .return, width: 2.4))
        return row
    }

    private func makeKeyRow(_ rowSpec: KeyboardRowSpec) -> KeyboardKeyRowView {
        KeyboardKeyRowView(
            buttons: rowSpec.keys.map { (makeKeyButton($0), $0.width) },
            referenceUnitCount: rowSpec.referenceUnitCount,
            height: appearance.size.rowHeight(rowSpec.height),
            letterControls: rowSpec.letterControls
        )
    }

    private func makeKeyButton(_ spec: KeySpec) -> UIButton {
        let isGlobe: Bool = { if case .globe = spec.kind { return true }; return false }()
        let button: UIButton = isGlobe ? UIButton(type: .system) : KeyboardKeyButton(type: .custom)
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = KeyboardGeometry.cornerRadius
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        configuration.baseBackgroundColor = palette.key
        configuration.baseForegroundColor = palette.text
        configuration.imagePadding = 0
        let keyFontSize = fontSize(for: spec.kind) * appearance.textSize.scale
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: keyFontSize, weight: .regular)
        var title: String?
        switch spec.kind {
        case .text(let value): title = keyTitle(for: value)
        case .shift:
            configuration.image = UIImage(systemName: shiftState == .locked ? "capslock.fill" : shiftState.isUpper ? "shift.fill" : "shift")
            configuration.baseBackgroundColor = shiftState.isUpper ? palette.key : palette.control
            button.accessibilityValue = shiftState == .locked ? "Caps Lock on" : shiftState.isUpper ? "Uppercase" : "Lowercase"
        case .delete:
            configuration.image = UIImage(systemName: "delete.left")
            configuration.baseBackgroundColor = palette.control
        case .modeSwitch(let value):
            title = value
            configuration.baseBackgroundColor = palette.control
        case .space:
            if #available(iOS 26.0, *) { title = "" } else { title = "space" }
        case .return:
            title = KeyboardInputPolicy.returnTitle(textDocumentProxy.returnKeyType ?? .default)
            if title == nil { configuration.image = UIImage(systemName: "return") }
            configuration.baseBackgroundColor = title == nil ? palette.control : .systemBlue
            configuration.baseForegroundColor = title == nil ? palette.text : .white
            button.isEnabled = textDocumentProxy.enablesReturnKeyAutomatically != true || textDocumentProxy.hasText
        case .globe:
            configuration.image = UIImage(systemName: "globe")
            configuration.baseBackgroundColor = palette.control
        }
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: keyFontSize, weight: .regular)
            return outgoing
        }
        button.configuration = configuration
        button.layer.cornerCurve = .continuous
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.accessibilityLabel = accessibilityLabel(for: spec.kind)
        button.accessibilityTraits.insert(.keyboardKey)
        if isGlobe {
            button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        } else {
            button.addAction(UIAction { [weak self] _ in self?.handleKey(spec.kind) }, for: .touchUpInside)
        }
        if let key = button as? KeyboardKeyButton {
            if case .text = spec.kind { key.previewText = title }
            if case .delete = spec.kind { key.behavior = .delete }
            if case .space = spec.kind {
                key.behavior = .space
                key.accessibilityHint = "Touch and hold, then slide to move the cursor."
            }
            key.neighborAtPoint = { [weak self] point, source in
                guard let self else { return nil }
                let position = source.convert(point, to: self.keyboardShell)
                guard self.keyboardShell.bounds.insetBy(dx: -6, dy: -8).contains(position) else { return nil }
                return self.keyButtons.filter { $0.isEnabled }.min { lhs, rhs in
                    let a = lhs.convert(CGPoint(x: lhs.bounds.midX, y: lhs.bounds.midY), to: self.keyboardShell)
                    let b = rhs.convert(CGPoint(x: rhs.bounds.midX, y: rhs.bounds.midY), to: self.keyboardShell)
                    return hypot(a.x - position.x, a.y - position.y) < hypot(b.x - position.x, b.y - position.y)
                }
            }
            key.touchActivity = { [weak self] began in
                guard let self else { return }
                self.activeKeyTouches = max(0, self.activeKeyTouches + (began ? 1 : -1))
                if !began { self.synchronizeInputTraits() }
            }
            key.moveCursor = { [weak self] offset in
                self?.pendingSpaceTap = nil
                self?.manualShift = false
                self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            }
            key.previewChanged = { [weak self] key in self?.showPreview(for: key) }
            key.trackpadActivity = { [weak self] active in
                guard let self else { return }
                self.isTrackpadActive = active
                self.keyButtons.forEach { $0.showTrackpad(active) }
            }
            keyButtons.append(key)
        }
        return button
    }

    private func showPreview(for key: KeyboardKeyButton?) {
        guard let key, let text = key.previewText, !isTrackpadActive, !UIAccessibility.isVoiceOverRunning else {
            keyPreview.isHidden = true
            return
        }
        let frame = key.convert(key.bounds, to: view)
        let width = max(frame.width + 18, 48)
        keyPreview.frame = CGRect(x: min(max(frame.midX - width / 2, 2), view.bounds.width - width - 2),
                                  y: max(0, frame.minY - 48), width: width, height: 48)
        keyPreview.backgroundColor = palette.key
        keyPreview.textColor = palette.text
        keyPreview.text = text
        keyPreview.isHidden = false
        view.bringSubviewToFront(keyPreview)
    }

    private func fontSize(for kind: KeyKind) -> CGFloat {
        switch kind {
        case .text:
            return keyboardMode == .letters ? 23 : 22
        case .space:
            return 16
        case .modeSwitch:
            return 17
        case .return:
            return 16
        case .shift, .delete, .globe:
            return 21
        }
    }

    private func keyTitle(for value: String) -> String {
        guard keyboardMode == .letters else { return value }
        return shiftState.isUpper ? value.uppercased() : value
    }

    private func accessibilityLabel(for kind: KeyKind) -> String {
        switch kind {
        case .text(let value):
            return accessibilityLabel(forTextKey: value)
        case .shift:
            return "Shift"
        case .delete:
            return "Delete"
        case .modeSwitch(let title):
            switch title {
            case "ABC": return "Letters"
            case "#+=": return "More symbols"
            default: return "Numbers"
            }
        case .space:
            return "Space"
        case .return:
            return KeyboardInputPolicy.returnTitle(textDocumentProxy.returnKeyType ?? .default)?.capitalized ?? "Return"
        case .globe:
            return "Next keyboard"
        }
    }

    private func accessibilityLabel(forTextKey value: String) -> String {
        switch value {
        case "-": "Hyphen"
        case "/": "Slash"
        case ":": "Colon"
        case ";": "Semicolon"
        case "(": "Left parenthesis"
        case ")": "Right parenthesis"
        case "$": "Dollar sign"
        case "&": "Ampersand"
        case "@": "At sign"
        case "\"": "Quotation mark"
        case ".": "Period"
        case ",": "Comma"
        case "?": "Question mark"
        case "!": "Exclamation mark"
        case "'": "Apostrophe"
        case "[": "Left bracket"
        case "]": "Right bracket"
        case "{": "Left brace"
        case "}": "Right brace"
        case "#": "Number sign"
        case "%": "Percent sign"
        case "^": "Caret"
        case "*": "Asterisk"
        case "+": "Plus sign"
        case "=": "Equals sign"
        case "_": "Underscore"
        case "\\": "Backslash"
        case "|": "Vertical bar"
        case "~": "Tilde"
        case "<": "Less than"
        case ">": "Greater than"
        case "€": "Euro sign"
        case "£": "Pound sign"
        case "¥": "Yen sign"
        case "•": "Bullet"
        default: value
        }
    }

    private func handleKey(_ kind: KeyKind) {
        guard !showsDictationPanel else { return }
        dismissGuidance()
        guard !isTrackpadActive else { return }
        if case .shift = kind {} else { lastShiftTap = nil; manualShift = false }
        defer { synchronizeInputTraits() }
        switch kind {
        case .text(let value):
            pendingSpaceTap = nil
            let output = keyboardMode == .letters && shiftState.isUpper ? value.uppercased() : value
            textDocumentProxy.insertText(output)
            if keyboardMode == .letters, shiftState == .upper {
                shiftState = .lower
                rebuildKeyboardRowsIfNeeded(force: true)
            }
        case .shift:
            pendingSpaceTap = nil
            let now = Date.timeIntervalSinceReferenceDate
            let wasLocked = shiftState == .locked
            shiftState = shiftState.tapped(at: now, after: lastShiftTap)
            lastShiftTap = wasLocked ? nil : now
            manualShift = true
            rebuildKeyboardRowsIfNeeded(force: true)
        case .delete:
            pendingSpaceTap = nil
            textDocumentProxy.deleteBackward()
        case .modeSwitch(let title):
            pendingSpaceTap = nil
            switch title {
            case "ABC": keyboardMode = .letters
            case "#+=": keyboardMode = .alternateSymbols
            default: keyboardMode = .symbols
            }
            shiftState = .lower
            rebuildKeyboardRowsIfNeeded(force: true)
        case .space:
            insertSpace()
            if !KeyboardInputPolicy.startsWithNumbers(inputType) { keyboardMode = .letters }
        case .return:
            pendingSpaceTap = nil
            textDocumentProxy.insertText("\n")
        case .globe:
            pendingSpaceTap = nil
            break
        }
    }

    private func insertSpace() {
        let now = Date()
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        let contextAfterInput = textDocumentProxy.documentContextAfterInput ?? ""
        let selectedText = textDocumentProxy.selectedText
        if KeyboardDoubleSpacePeriodPolicy.shouldInsertPeriod(
            after: pendingSpaceTap,
            contextBeforeInput: contextBeforeInput,
            contextAfterInput: contextAfterInput,
            selectedText: selectedText,
            now: now
        ) {
            pendingSpaceTap = nil
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            return
        }

        textDocumentProxy.insertText(" ")
        guard selectedText?.isEmpty != false,
              let contextBeforeInput
        else {
            pendingSpaceTap = nil
            return
        }

        pendingSpaceTap = KeyboardSpaceTap(
            occurredAt: now,
            expectedContextBeforeInput: contextBeforeInput + " ",
            expectedContextAfterInput: contextAfterInput
        )
    }

    private var usableShortcuts: [KeyboardShortcutPayload] {
        Array(
            (payload?.shortcuts.compactMap { shortcut -> KeyboardShortcutPayload? in
                guard normalized(shortcut.body) != nil else { return nil }
                return shortcut
            } ?? []).prefix(4)
        )
    }

    private func effectiveSession(_ session: KeyboardSessionPayload) -> KeyboardSessionPayload {
        session.collapsedIfStale()
    }

    @discardableResult
    private func markSessionInserted(_ session: KeyboardSessionPayload) -> Bool {
        do {
            guard let newPayload = try KeyboardSharedStore.claimInsertion(for: session) else {
                reloadPayload()
                return false
            }
            payload = newPayload
            renderPayload()
            return true
        } catch {
            recordDiagnostic(.commandWriteFailed, detail: "inserted")
            return false
        }
    }

    private func consumeAutomaticInsertionIfNeeded(_ session: KeyboardSessionPayload) {
        guard viewIfLoaded?.window != nil,
              KeyboardSessionContinuity.shouldAutomaticallyInsert(session),
              let sessionID = normalized(session.sessionID),
              !consumedAutomaticInsertionSessionIDs.contains(sessionID),
              let text = normalized(session.resultText)
        else {
            return
        }

        guard markSessionInserted(session) else { return }
        consumedAutomaticInsertionSessionIDs.insert(sessionID)

        impact()
        textDocumentProxy.insertText(KeyboardSessionContinuity.automaticInsertionText(
            text,
            contextBeforeInput: textDocumentProxy.documentContextBeforeInput,
            selectedText: textDocumentProxy.selectedText
        ))
        recordDiagnostic(.insertTapped, detail: "automatic")
        UIAccessibility.post(notification: .announcement, argument: "Dictation inserted.")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updateColors() {
        view.backgroundColor = palette.background
        keyboardShell.backgroundColor = .clear
        UIView.performWithoutAnimation {
            style(vyrraButton, emphasized: true)
            style(menuButton, emphasized: false)
            dictationPanel.apply(palette)
        }
        guidanceBubble.backgroundColor = palette.primary
        guidanceLabel.textColor = palette.primaryText
    }

    private func style(_ button: UIButton, emphasized: Bool) {
        button.configuration?.baseBackgroundColor = emphasized ? palette.primary : palette.control
        button.configuration?.baseForegroundColor = emphasized ? palette.primaryText : palette.text
        button.tintColor = emphasized ? palette.primaryText : palette.text
        button.alpha = 1
        button.semanticContentAttribute = .forceLeftToRight
        button.imageView?.contentMode = .scaleAspectFit
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = emphasized ? 0.14 : 0.04
        button.layer.shadowRadius = emphasized ? 8 : 4
        button.layer.shadowOffset = CGSize(width: 0, height: emphasized ? 3 : 1)
    }

    /// Wakes the Taptic Engine on touch-down so the tap's impact isn't late.
    private func prepareImpact() {
        guard appearance.hapticsEnabled != false else { return }
        impactGenerator.prepare()
    }

    private func impact() {
        guard appearance.hapticsEnabled != false else { return }
        impactGenerator.impactOccurred()
        impactGenerator.prepare()
    }

    private func recordDiagnostic(_ type: KeyboardDiagnosticEventType, detail: String) {
        try? KeyboardSharedStore.appendDiagnostic(
            KeyboardDiagnosticEntry(type: type, detail: detail)
        )
    }

    private var palette: KeyboardPalette {
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance {
        case .dark: style = .dark
        case .light: style = .light
        default: style = traitCollection.userInterfaceStyle
        }
        return KeyboardPalette(style: style)
    }
}
