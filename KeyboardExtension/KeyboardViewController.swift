import KalamEngine
import UIKit

/// The keyboard (SPEC 5): pages, shift, feedback and the suggestion bar. Typing state lives in
/// InputController, the engine behind EngineClient.
final class KeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    private var settings = Settings.load()
    private let feedback = FeedbackPlayer()
    private let client = EngineClient()
    private lazy var input = InputController(proxy: textDocumentProxy, client: client)
    private var writeTimer: Timer?
    private var isVisible = false
    private let keyboardView = KeyboardView()
    private let bar = SuggestionBar()
    private let clipboard = Clipboard()
    private let panel = ClipboardPanel()
    private let globeButton = UIButton(type: .custom)
    #if DEBUG
    private let overlay = DebugOverlay()
    #endif

    private var lang = lastLanguage
    private var page = "letters"
    private var shift = ShiftState()

    private static let lastLanguageKey = "lastLanguage"

    /// The last EN/AR choice (SPEC 5.2), in the extension's own defaults: App Group writes need Full Access.
    private static var lastLanguage: Lang {
        get { UserDefaults.standard.string(forKey: lastLanguageKey).flatMap(Lang.init(rawValue:)) ?? .en }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastLanguageKey) }
    }

    override func loadView() {
        let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "kalam"
        keyboardView.delegate = self
        input.lang = lang
        input.isShifted = { [weak self] in self?.shift.mode != .off }
        input.onEdit = { [weak self] in
            self?.refreshAutoShift()
            self?.refreshReturnKey()
        }
        input.onSlots = { [weak self] in
            self?.bar.slots = $0
            self?.showChip()
        }
        bar.onPick = { [weak self] in self?.input.accept($0) }
        bar.onBlock = { [weak self] in self?.input.block($0) }
        bar.onClipboard = { [weak self] in self?.togglePanel() }
        bar.onChip = { [weak self] in
            guard let self, let clip = clipboard.history.chip(now: Date()) else { return }
            paste(clip.text)
        }
        panel.onPaste = { [weak self] in self?.paste($0) }
        panel.onPin = { [weak self] text, pinned in self?.changeClipboard { $0.setPinned(pinned, text: text) } }
        panel.onDelete = { [weak self] text in self?.changeClipboard { $0.delete(text) } }
        bar.onClear = { [weak self] in self?.changeClipboard { $0.clear() } }
        bar.onClose = { [weak self] in self?.closePanel() }
        panel.isHidden = true
        for name in [NSNotification.Name.NSExtensionHostWillResignActive, .NSExtensionHostDidEnterBackground] {
            NotificationCenter.default.addObserver(self, selector: #selector(hostWillHide), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(hostDidBecomeActive), name: .NSExtensionHostDidBecomeActive, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.refreshAppearance() }
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        for subview in [bar, keyboardView, globeButton, panel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: KeyboardView.height),
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: KeyboardView.barHeight),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.topAnchor.constraint(equalTo: bar.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #if DEBUG
        overlay.frame = CGRect(x: 28, y: 2, width: 220, height: 12)
        overlay.latencyMs = { [weak self] in self?.client.latest?.latencyMs }
        #endif
        reloadLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        applySettings()
        feedback.prepare()
        reloadLayout()  // needsInputModeSwitchKey is reliable from here on
        client.open()  // also picks up the host app's changes (import, forget, reset, restore)
        refreshHostState()
        input.resync()
        closePanel()
        if clipboardEnabled { clipboard.load() }
        importLexiconIfDue()
        writeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.client.writeIfDue() }
    }

    /// Captured once the keys are on screen: reading the pasteboard can block main on iOS's
    /// "Allow Paste" prompt until Moe answers it (SPEC 5.5).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureClip()
        stopDelayingTouches()
    }

    /// The system gesture gate on the keyboard's window delays touchesBegan near the screen edges,
    /// which can hold back and reorder fast edge keys (device round 1).
    private func stopDelayingTouches() {
        for view in sequence(first: view as UIView, next: \.superview) {
            for recognizer in view.gestureRecognizers ?? [] {
                trace("gesture \(type(of: view)) \(type(of: recognizer)) delaysTouchesBegan \(recognizer.delaysTouchesBegan)")
                recognizer.delaysTouchesBegan = false
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        writeTimer?.invalidate()
        client.close()
        clipboard.flush()
    }

    @objc private func hostWillHide() { client.close() }

    @objc private func hostDidBecomeActive() {
        if isVisible { client.open() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        globeButton.frame = keyboardView.globeFrame ?? .zero
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshHostState()
        captureClipIfDue()
        input.hostTextChanged()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        captureClipIfDue()
        input.hostTextChanged()
    }

    /// CLAUDE.md: the controller is recreated per host app; release its views a turn later.
    deinit {
        writeTimer?.invalidate()
        let views = viewIfLoaded?.subviews ?? []
        DispatchQueue.main.async { views.forEach { $0.removeFromSuperview() } }
    }

    // MARK: State

    /// Settings are re-read on every appear, so the host app's changes apply the next time.
    private func applySettings() {
        settings = Settings.load()
        feedback.settings = settings
        input.settings = settings
        keyboardView.showsHints = settings.digitHints
        client.setLearning(traits: input.traits, paused: settings.pauseLearning)
        #if DEBUG
        if settings.debugOverlay { view.addSubview(overlay) } else { overlay.removeFromSuperview() }
        #endif
    }

    /// SPEC 9.2: UILexicon entries (contact names, text replacements) on the first launch, then weekly.
    private func importLexiconIfDue() {
        let key = "lexiconImportedAt"
        guard hasFullAccess, !settings.pauseLearning, let defaults = UserDefaults(suiteName: Settings.appGroup) else { return }
        let now = Date().timeIntervalSince1970
        guard now - defaults.double(forKey: key) >= 7 * 86_400 else { return }
        defaults.set(now, forKey: key)
        requestSupplementaryLexicon { [client] lexicon in client.addLexiconEntries(lexicon.entries.map(\.documentText)) }
    }

    private func reloadLayout() {
        let id = "\(lang.rawValue)-\(page)"
        let bundled = Layout.bundled(id)
        let layout = lang == .ar ? bundled?.withDigits(eastern: settings.easternArabicDigits) : bundled
        view.accessibilityValue = id  // lets UI tests see the page; keys are layer-drawn
        keyboardView.layout = needsInputModeSwitchKey ? layout?.withGlobeKey() : layout
        keyboardView.shift = shift.mode
        view.setNeedsLayout()
    }

    private func refreshHostState() {
        bar.hasFullAccess = hasFullAccess
        bar.showsClipboardButton = clipboardEnabled
        let traits = fieldTraits
        if traits != input.traits {
            input.traits = traits
            client.setLearning(traits: traits, paused: settings.pauseLearning)
        }
        refreshAppearance()
        refreshReturnKey()
        refreshAutoShift()
    }

    /// SPEC 8.5 rule 1 and 9.2: no autocorrect or learning in URL, email, password and code fields.
    /// Safari's address bar is a web-search field, so web search counts as URL. Without Full Access
    /// the bar shows its banner instead of suggestions, so an autocorrect couldn't be seen coming: none.
    private var fieldTraits: FieldTraits {
        let proxy = textDocumentProxy
        let keyboardType: FieldTraits.KeyboardType = switch proxy.keyboardType ?? .default {
        case .URL, .webSearch: .url
        case .emailAddress: .email
        default: .other
        }
        let contentType: FieldTraits.ContentType = switch proxy.textContentType ?? nil {
        case UITextContentType.password?, UITextContentType.newPassword?: .password
        case UITextContentType.oneTimeCode?: .oneTimeCode
        default: .other
        }
        return FieldTraits(autocorrection: proxy.autocorrectionType != .no && hasFullAccess, keyboardType: keyboardType, contentType: contentType)
    }

    private func refreshAppearance() {
        let appearance = textDocumentProxy.keyboardAppearance ?? .default
        let dark = appearance == .dark || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        let palette = dark ? Palette.dark : Palette.light
        keyboardView.palette = palette
        bar.palette = palette
        panel.palette = palette
    }

    private func refreshReturnKey() {
        let proxy = textDocumentProxy
        let type = proxy.returnKeyType ?? .default
        let enabled = !(proxy.enablesReturnKeyAutomatically ?? false) || proxy.hasText
        keyboardView.returnKey = ReturnKeyStyle(title: returnTitle(type), prominent: enabled && isProminent(type), enabled: enabled)
    }

    private func returnTitle(_ type: UIReturnKeyType) -> String? {
        let titles: [UIReturnKeyType: (String, String)] = [
            .go: ("go", "انتقال"), .google: ("search", "بحث"), .yahoo: ("search", "بحث"), .search: ("search", "بحث"),
            .join: ("join", "انضمام"), .next: ("next", "التالي"), .route: ("route", "مسار"), .send: ("send", "إرسال"),
            .done: ("done", "تم"), .emergencyCall: ("SOS", "طوارئ"), .continue: ("continue", "متابعة"),
        ]
        return titles[type].map { lang == .ar ? $0.1 : $0.0 }
    }

    private func isProminent(_ type: UIReturnKeyType) -> Bool {
        [.go, .google, .yahoo, .search, .join, .route, .send, .done, .emergencyCall, .continue].contains(type)
    }

    private func refreshAutoShift() {
        let mode = autocapitalization(textDocumentProxy.autocapitalizationType ?? .sentences)
        let on = lang == .en && settings.autoCapitalize
            && shouldAutoShift(before: textDocumentProxy.documentContextBeforeInput, autocapitalization: mode)
        shift.setAuto(on)
        keyboardView.shift = shift.mode
    }

    private func autocapitalization(_ type: UITextAutocapitalizationType) -> Autocapitalization {
        switch type {
        case .none: .none
        case .words: .words
        case .allCharacters: .allCharacters
        default: .sentences
        }
    }

    // MARK: KeyboardViewDelegate

    func keyDown(_ key: Layout.Key) {
        switch key.kind {
        case .char: feedback.touchDown(.key)
        case .backspace:
            feedback.touchDown(.delete)
            input.backspace(1)
        case .shift:
            feedback.touchDown(.modifier)
            shift.tap(at: ProcessInfo.processInfo.systemUptime)
            keyboardView.shift = shift.mode
            input.redrawBar()
        default: feedback.touchDown(.modifier)
        }
    }

    func keyUp(_ key: Layout.Key) {
        switch key.kind {
        case .space:
            input.typeSpace()
            if page == "numbers" { showLetters() }
        case .return: input.typeReturn()
        case .page:
            page = key.output
            reloadLayout()
        case .lang:
            lang = lang == .en ? .ar : .en
            Self.lastLanguage = lang
            page = "letters"
            reloadLayout()
            refreshHostState()
            input.lang = lang
            input.refresh()
        default: break
        }
    }

    func commit(_ text: String, at point: Point?) {
        clipboard.dismissChip()  // SPEC 5.5: typing ends the chip's offer
        let output = lang == .en && shift.mode != .off ? text.uppercased() : text
        shift.letterTyped()
        input.type(output, at: page == "letters" ? point : nil)  // the engine's spatial model knows the letters page only
        // SPEC 5.2: an apostrophe on the 123 page returns to letters.
        if page == "numbers", output == "'" { showLetters() }
    }

    func backspaceRepeated(_ count: Int) {
        let word = BackspaceRepeat.deletesWord(repeat: count)
        input.backspace(word ? BackspaceRepeat.wordLength(before: textDocumentProxy.documentContextBeforeInput ?? "") : 1)
        feedback.play(.delete)
    }

    func moveCursor(by offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    private func showLetters() {
        page = "letters"
        reloadLayout()
    }

    // MARK: Clipboard (SPEC 5.5)

    /// The App Group container and the pasteboard both need Full Access.
    private var clipboardEnabled: Bool { hasFullAccess && settings.clipboard }

    /// On appear and when the panel opens.
    private func captureClip() {
        if clipboardEnabled, clipboard.capture() { showNewClip() }
    }

    /// On host text and selection changes, which can come with every keystroke.
    private func captureClipIfDue() {
        if clipboardEnabled, clipboard.captureIfDue() { showNewClip() }
    }

    private func showNewClip() {
        showChip()
        if !panel.isHidden { panel.items = clipboard.history.panelItems }
    }

    private func showChip() {
        bar.chip = clipboardEnabled && !input.hasWord ? clipboard.history.chip(now: Date())?.text : nil
    }

    private func paste(_ text: String) {
        input.paste(text)
        changeClipboard { $0.useChip() }
    }

    private func changeClipboard(_ edit: (inout ClipboardHistory) -> Void) {
        clipboard.change(edit)
        showChip()
        if !panel.isHidden { panel.items = clipboard.history.panelItems }
    }

    private func togglePanel() {
        guard panel.isHidden else { return closePanel() }
        captureClip()
        panel.items = clipboard.history.panelItems
        panel.isHidden = false
        keyboardView.isHidden = true
        globeButton.isHidden = true
        bar.isPanelOpen = true
        view.accessibilityValue = "clipboard"
    }

    private func closePanel() {
        guard !panel.isHidden else { return }
        panel.isHidden = true
        keyboardView.isHidden = false
        globeButton.isHidden = false
        bar.isPanelOpen = false
        reloadLayout()
    }
}
