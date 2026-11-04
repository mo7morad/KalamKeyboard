import KalamEngine
import UIKit

/// The keyboard's typing state on the main thread (SPEC 4, 8): the current word's taps, the
/// auto-space and autocorrect-undo slots, and the commits, autocorrects and learner events that
/// follow from each key. It edits through the text proxy and never waits on the engine, except for
/// the commit path's bounded wait in EngineClient.
final class InputController {
    /// An autocorrect that the very next backspace can undo (SPEC 8.5).
    private struct Undo {
        let literal: String
        let taps: [Tap]
        let replacement: String
    }

    private let proxy: UITextDocumentProxy
    private let client: EngineClient

    var lang = Lang.en
    var settings = Settings()
    var traits = FieldTraits()
    /// Whether shift is on now, for SPEC 8.6 display casing.
    var isShifted: () -> Bool = { false }
    /// After every edit the controller makes (the view controller refreshes shift and return).
    var onEdit: (() -> Void)?
    /// New bar slots, visual left to right.
    var onSlots: (([BarSlot?]) -> Void)?

    private var taps: [Tap] = []
    private var literal: String { taps.map(\.char).joined() }
    private var autoSpace = false
    private var lastKeyWasSpace = false
    private var undo: Undo?
    /// A literal restored by undo; committing it unchanged neither corrects nor learns it again.
    private var restoredLiteral: String?
    /// The word a paste ended on; committing it unchanged neither corrects nor learns it (SPEC 5.5).
    private var pastedWord: String?
    /// The text before the cursor after our last edit, to tell our edits from the host's.
    private var expectedBefore: String?
    private var shown: EngineClient.Result?

    init(proxy: UITextDocumentProxy, client: EngineClient) {
        self.proxy = proxy
        self.client = client
        client.onResult = { [weak self] in self?.show($0) }
    }

    private var before: String { proxy.documentContextBeforeInput ?? "" }

    /// Whether a word is being typed (the clip chip shows only between words).
    var hasWord: Bool { !taps.isEmpty }

    // MARK: Keys

    /// A char key's output. `point` is in key units of the letters page, nil otherwise.
    func type(_ text: String, at point: Point?) {
        undo = nil
        if continuesWord(text, word: literal) {
            insert(text)
            taps.append(Tap(text, at: point))
        } else {
            if !taps.isEmpty { commitWord() }
            undo = nil  // undo is for the space after an autocorrect only
            let edit = punctuationEdit(text, afterAutoSpace: autoSpace)
            delete(edit.delete)
            insert(edit.insert)
            autoSpace = edit.insert.hasSuffix(" ")
            // An apostrophe that took an auto-space's place joins the word before it (Moe + 's).
            taps = resyncedTaps([], to: currentWord(before: before))
            if endsSentence(text) { client.sentenceEnded() }
        }
        refresh()
    }

    func typeSpace() {
        undo = nil
        let corrected = taps.isEmpty ? nil : commitWord()
        if settings.doubleSpacePeriod, lastKeyWasSpace, doubleSpaceBecomesPeriod(before: before) {
            delete(1)
            insert(". ")
            client.sentenceEnded()
        } else {
            insert(" ")
            lastKeyWasSpace = true
            autoSpace = corrected != nil
        }
        refresh()
    }

    func typeReturn() {
        if !taps.isEmpty { commitWord() }
        undo = nil
        insert("\n")
        client.sentenceEnded()
        refresh()
    }

    /// Backspace (count 1) or a whole-word repeat step. The first backspace right after an
    /// autocorrect restores the literal and drops the auto-space in one go.
    func backspace(_ count: Int) {
        if count == 1, let undo, before.hasSuffix(undo.replacement + " ") {
            self.undo = nil
            delete(undo.replacement.count + 1)
            insert(undo.literal)
            taps = undo.taps
            restoredLiteral = undo.literal
            client.undoAutocorrect()
            refresh()
            return
        }
        undo = nil
        let after = String(before.dropLast(count))
        let wasInWord = !taps.isEmpty
        delete(count)
        taps = resyncedTaps(taps, to: currentWord(before: after))
        if let restored = restoredLiteral {
            client.backspaced(into: restored, lang: lang)  // the learner already has it as committed
            restoredLiteral = nil
        } else if !wasInWord, !taps.isEmpty {
            client.backspaced(into: literal, lang: lang)
        }
        refresh()
    }

    // MARK: Suggestion bar

    /// A tap replaces the current word (or inserts the prediction) and adds an auto-space.
    func accept(_ slot: BarSlot) {
        undo = nil
        let context = contextWords(before: before)
        delete(literal.count)
        insert(slot.word + " ")
        learn(slot.word, context: context, how: slot.isLiteral ? .literal : .suggestion)
        taps = []
        pastedWord = nil
        autoSpace = true
        lastKeyWasSpace = true
        refresh()
    }

    func block(_ slot: BarSlot) {
        client.block(slot.ident, display: slot.word, lang: lang)
        refresh()
    }

    // MARK: Clipboard

    /// SPEC 5.5: inserts a clip as is; pasted text is never learned.
    func paste(_ text: String) {
        undo = nil
        insert(text)
        taps = resyncedTaps([], to: currentWord(before: before))
        pastedWord = taps.isEmpty ? nil : literal
        refresh()
    }

    // MARK: Host changes

    /// textDidChange / selectionDidChange: if the text before the cursor isn't what our last edit
    /// left (the cursor moved, the host edited), the current word is rebuilt from it.
    func hostTextChanged() {
        if before != expectedBefore { resync() }
    }

    /// Rebuilds the current word from the text before the cursor (also on appear).
    func resync() {
        undo = nil
        autoSpace = false
        lastKeyWasSpace = false
        restoredLiteral = nil
        pastedWord = nil
        taps = resyncedTaps(taps, to: currentWord(before: before))
        refresh()
    }

    /// Asks for suggestions for the current state (also on appear and language switches).
    func refresh() {
        expectedBefore = before
        client.request(EngineClient.Request(lang: lang, context: contextWords(before: before), taps: taps, traits: traits, settings: settings))
    }

    /// Re-renders the bar from the latest result, e.g. after shift changes the casing.
    func redrawBar() {
        if let shown { show(shown) }
    }

    private func show(_ result: EngineClient.Result) {
        shown = result
        let capitalized = isShifted() || literal.first?.isUppercase == true
        onSlots?(barSlots(result.candidates, autocorrect: result.autocorrect, literal: literal, lang: lang, capitalized: capitalized))
    }

    // MARK: Commit

    /// Commits the current word before a space, punctuation or return: autocorrects it when the
    /// current result says so (SPEC 8.5) and tells the learner. Returns the replacement, if any.
    @discardableResult
    private func commitWord() -> String? {
        let literal = literal, taps = taps
        let context = contextWords(before: before)
        self.taps = []
        defer { (restoredLiteral, pastedWord) = (nil, nil) }
        guard literal != restoredLiteral, literal != pastedWord else { return nil }  // already learned, or pasted
        guard let target = client.resultForCommit()?.autocorrect else {
            learn(literal, context: context, how: .typed)
            return nil
        }
        let replacement = cased(target.text, capitalized: literal.first?.isUppercase == true)
        delete(literal.count)
        insert(replacement)
        learn(replacement, context: context, how: .autocorrect(from: literal))
        undo = Undo(literal: literal, taps: taps, replacement: replacement)
        return replacement
    }

    /// Numbers and stray marks aren't words (SPEC 6.2), so the learner only sees words with a letter.
    private func learn(_ word: String, context: [String], how: Learner.Commit) {
        guard word.contains(where: \.isLetter) else { return }
        client.commit(word, lang: lang, context: context, how: how)
    }

    // MARK: Editing

    private func insert(_ text: String) {
        proxy.insertText(text)
        lastKeyWasSpace = false
        autoSpace = false
        onEdit?()
    }

    private func delete(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count { proxy.deleteBackward() }
        lastKeyWasSpace = false
        autoSpace = false
        onEdit?()
    }
}
