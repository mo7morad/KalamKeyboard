import KalamEngine
import UIKit

/// Phase 1 keyboard shell: pages, shift, editing keys and feedback, no engine (SPEC 5).
final class KeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    /// Every committed letter tap with its point in key units (SPEC 5.2). Phase 5 consumes it.
    var onTap: ((Tap) -> Void)?

    private let settings = KeyboardSettings.current
    private lazy var feedback = FeedbackPlayer(settings: settings)
    private let keyboardView = KeyboardView()
    private let bar = SuggestionBar()
    private let globeButton = UIButton(type: .custom)
    #if DEBUG
    private let overlay = DebugOverlay()
    #endif

    private var lang = KeyboardSettings.lastLanguage
    private var page = "letters"
    private var shift = ShiftState()
    private var lastKeyWasSpace = false

    override func loadView() {
        let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        inputView.allowsSelfSizing = true
        self.inputView = inputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "kalam"
        keyboardView.delegate = self
        keyboardView.showsHints = settings.digitHints
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.refreshAppearance() }
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        for subview in [bar, keyboardView, globeButton] {
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
        ])
        #if DEBUG
        if settings.debugOverlay {
            overlay.frame = CGRect(x: 28, y: 2, width: 220, height: 12)
            view.addSubview(overlay)
        }
        #endif
        reloadLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        feedback.prepare()
        reloadLayout()  // needsInputModeSwitchKey is reliable from here on
        refreshHostState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        globeButton.frame = keyboardView.globeFrame ?? .zero
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshHostState()
    }

    /// CLAUDE.md: the controller is recreated per host app; release its views a turn later.
    deinit {
        let views = viewIfLoaded?.subviews ?? []
        DispatchQueue.main.async { views.forEach { $0.removeFromSuperview() } }
    }

    // MARK: State

    private func reloadLayout() {
        let id = "\(lang.rawValue)-\(page)"
        let layout = Layout.bundled(id)
        view.accessibilityValue = id  // lets UI tests see the page; keys are layer-drawn
        keyboardView.layout = needsInputModeSwitchKey ? layout?.withGlobeKey() : layout
        keyboardView.shift = shift.mode
        view.setNeedsLayout()
    }

    private func refreshHostState() {
        bar.hasFullAccess = hasFullAccess
        refreshAppearance()
        refreshReturnKey()
        refreshAutoShift()
    }

    private func refreshAppearance() {
        let appearance = textDocumentProxy.keyboardAppearance ?? .default
        let dark = appearance == .dark || (appearance != .light && traitCollection.userInterfaceStyle == .dark)
        let palette = dark ? Palette.dark : Palette.light
        keyboardView.palette = palette
        bar.palette = palette
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
            deleteBackward(1)
        case .shift:
            feedback.touchDown(.modifier)
            shift.tap(at: ProcessInfo.processInfo.systemUptime)
            keyboardView.shift = shift.mode
        default: feedback.touchDown(.modifier)
        }
    }

    func keyUp(_ key: Layout.Key) {
        switch key.kind {
        case .space: typeSpace()
        case .return: insert("\n")
        case .page:
            page = key.output
            reloadLayout()
        case .lang:
            lang = lang == .en ? .ar : .en
            KeyboardSettings.lastLanguage = lang
            page = "letters"
            reloadLayout()
            refreshHostState()
        default: break
        }
    }

    func commit(_ text: String, at point: Point?) {
        let output = lang == .en && shift.mode != .off ? text.uppercased() : text
        shift.letterTyped()
        insert(output)
        onTap?(Tap(output, at: point))
        // SPEC 5.2: an apostrophe on the 123 page returns to letters.
        if page == "numbers", output == "'" { showLetters() }
    }

    func backspaceRepeated(_ count: Int) {
        let word = BackspaceRepeat.deletesWord(repeat: count)
        deleteBackward(word ? BackspaceRepeat.wordLength(before: textDocumentProxy.documentContextBeforeInput ?? "") : 1)
        feedback.play(.delete)
    }

    func moveCursor(by offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    // MARK: Editing

    private func typeSpace() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if settings.doubleSpacePeriod, lastKeyWasSpace, doubleSpaceBecomesPeriod(before: before) {
            textDocumentProxy.deleteBackward()
            insert(". ")
        } else {
            insert(" ")
            lastKeyWasSpace = true
        }
        if page == "numbers" { showLetters() }
    }

    private func insert(_ text: String) {
        textDocumentProxy.insertText(text)
        lastKeyWasSpace = false
        refreshAutoShift()
        refreshReturnKey()
    }

    private func deleteBackward(_ count: Int) {
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        lastKeyWasSpace = false
        refreshAutoShift()
        refreshReturnKey()
    }

    private func showLetters() {
        page = "letters"
        reloadLayout()
    }
}
