import KalamEngine
import UIKit

/// The keyboard's typing state on the main thread (SPEC 4, 8): the current word's taps, the
/// auto-space and autocorrect-undo slots, and the commits, autocorrects and learner events that
/// follow from each key. It edits through the text proxy and never waits on the engine, except for
/// the commit path's bounded wait in EngineClient.
final class InputController {
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
    /// An autocorrect the next backspaces can undo (SPEC 8.5).
    private var undo: AutocorrectUndo?
    /// A literal restored by undo (or put back by a bar tap); committing it unchanged neither corrects nor learns it again.
    private var restoredLiteral: String?
    /// This controller's recent autocorrects (SPEC 8.5 revert memory), and the one the bar offers to
    /// revert while the cursor is in or right after its replacement (SPEC 5.4).
    private var recent = RecentAutocorrects()
    private var revertOffer: RecentAutocorrects.Entry?
    /// The word a paste ended on; committing it unchanged neither corrects nor learns it (SPEC 5.5).
    private var pastedWord: String?
    /// The text before the cursor after our last edit, to tell our edits from the host's.
    private var expectedBefore: String?
    private var shown: EngineClient.Result?
    /// SPEC 5.2 backspace swipe: the character the touch-down deleted, until a swipe puts it back
    /// or a repeat follows, and the words the swipe deleted, most recent last.
    private var swipeRestore: String?
    private var swipeDeleted: [String] = []

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
        let pending = undo
        dropUndo()
        if continuesWord(text, word: literal) {
            insert(text)
            taps.append(Tap(text, at: point))
        } else {
            if !taps.isEmpty { commitWord() }
            let edit = punctuationEdit(text, afterAutoSpace: autoSpace)
            delete(edit.delete)
            insert(edit.insert)
            // SPEC 8.5: the slot covers the punctuation that committed the word, or that took its auto-space's place.
            undo = (undo ?? (edit.delete > 0 ? pending : nil))?.typed(edit.insert, deleting: edit.delete)
            autoSpace = edit.insert.hasSuffix(" ")
            // An apostrophe that took an auto-space's place joins the word before it (Moe + 's).
            taps = resyncedTaps([], to: currentWord(before: before))
            if endsSentence(text) { client.sentenceEnded() }
        }
        refresh()
    }

    func typeSpace() {
        dropUndo()
        let corrected = taps.isEmpty ? nil : commitWord()
        if settings.doubleSpacePeriod, lastKeyWasSpace, doubleSpaceBecomesPeriod(before: before) {
            delete(1)
            insert(". ")
            client.sentenceEnded()
        } else {
            insert(" ")
            lastKeyWasSpace = true
            autoSpace = corrected != nil
            undo = undo?.typed(" ")
        }
        refresh()
    }

    func typeReturn() {
        dropUndo()
        if !taps.isEmpty { commitWord() }
        insert("\n")
        undo = undo?.typed("\n")
        client.sentenceEnded()
        refresh()
    }

    /// Backspace, or a repeat step (`repeated`, possibly a whole word). Right after an autocorrect,
    /// backspace first deletes the punctuation or newline that committed it, keeping the slot; the
    /// backspace that reaches the word restores the literal, an auto-space going with it (SPEC 8.5).
    func backspace(_ count: Int, repeated: Bool = false) {
        swipeRestore = nil
        if !repeated, var slot = undo {
            switch slot.backspace(before: before) {
            case .revert(let length, let text):
                undo = nil
                delete(length)
                insert(text)
                taps = slot.taps
                restoredLiteral = text
                client.undoAutocorrect()
                refresh()
                return
            case .delete:
                delete(1)
                taps = resyncedTaps(taps, to: currentWord(before: before))
                undo = slot  // the learner hears of the reopened word when the slot ends (dropUndo)
                refresh()
                return
            case .gone: break
            }
        }
        dropUndo()
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

    /// Backspace touch-down: one character, which a swipe that follows puts back (not an autocorrect undo).
    func backspaceDown() {
        let old = before
        backspace(1)
        swipeRestore = before == String(old.dropLast()) ? old.last.map(String.init) : nil
        swipeDeleted = []
    }

    /// SPEC 5.2 backspace swipe, live: deletes or puts back whole words until `words` are gone.
    /// Returns how many words this step deleted, for the delete sound.
    func swipeBackspace(toWords words: Int) -> Int {
        dropUndo()
        if let restore = swipeRestore {  // the swipe works in whole words
            swipeRestore = nil
            insert(restore)
        }
        var deleted = 0
        while swipeDeleted.count < words, !before.isEmpty {
            let word = String(before.suffix(BackspaceRepeat.wordLength(before: before)))
            delete(word.count)
            swipeDeleted.append(word)
            deleted += 1
        }
        while swipeDeleted.count > words, let word = swipeDeleted.popLast() { insert(word) }
        // Like a paste: a word put back is neither autocorrected nor learned again.
        taps = resyncedTaps([], to: currentWord(before: before))
        pastedWord = taps.isEmpty ? nil : literal
        refresh()
        return deleted
    }

    // MARK: Suggestion bar

    /// A tap replaces the whole word around the cursor (or inserts the prediction) and adds an
    /// auto-space, unless text follows the word. A revert slot puts back an autocorrect's literal
    /// and rejects the autocorrect (SPEC 5.4).
    func accept(_ slot: BarSlot) {
        let offer = revertOffer
        dropUndo()
        let context = contextWords(before: before)
        let after = proxy.documentContextAfterInput ?? ""
        let tail = literal.isEmpty ? "" : currentWordTail(after: after)
        // Hosts are expected to count this offset in Characters (device-only, unverified).
        if !tail.isEmpty { proxy.adjustTextPosition(byCharacterOffset: tail.count) }
        delete(literal.count + tail.count)
        let followed = !literal.isEmpty && !after.dropFirst(tail.count).isEmpty
        insert(followed ? slot.word : slot.word + " ")
        if slot.isRevert, let offer {
            recent.remove(offer)
            client.revertAutocorrect(offer.literal, replacement: offer.replacement, lang: lang, context: context)
        } else {
            // An emoji has no letter: not learned. A rescued word is learned in its own script's language (Learner).
            learn(slot.word, context: context, how: slot.isLiteral ? .literal : .suggestion, taps: taps)
        }
        // Followed by text, the cursor stays at the word's end: it is the current word, already learned.
        taps = followed ? resyncedTaps([], to: currentWord(before: slot.word)) : []
        restoredLiteral = taps.isEmpty ? nil : literal
        pastedWord = nil
        autoSpace = !followed
        lastKeyWasSpace = !followed
        refresh()
    }

    func block(_ slot: BarSlot) {
        client.block(slot.ident, display: slot.word, lang: slot.rescueLang ?? lang)
        refresh()
    }

    // MARK: Clipboard

    /// SPEC 5.5, 5.6: inserts a clip or a panel emoji as is; it is never learned.
    func paste(_ text: String) {
        dropUndo()
        insert(text)
        taps = resyncedTaps([], to: currentWord(before: before))
        pastedWord = taps.isEmpty ? nil : literal
        refresh()
    }

    // MARK: Host changes

    /// textDidChange / selectionDidChange: if the text before the cursor isn't what our last edit
    /// left (the cursor moved, the host edited), the current word is rebuilt from it.
    func hostTextChanged() {
        let match = before == expectedBefore
        trace("host \(match ? "match" : "MISMATCH") before \(String(before.suffix(16)).debugDescription) expected \(expectedBefore.map { String($0.suffix(16)).debugDescription } ?? "nil")")
        guard !match else { return }
        resync()
        trace("resync literal \(literal.debugDescription)")
    }

    /// Rebuilds the current word from the text before the cursor (also on appear).
    func resync() {
        dropUndo()
        autoSpace = false
        lastKeyWasSpace = false
        restoredLiteral = nil
        pastedWord = nil
        taps = resyncedTaps(taps, to: currentWord(before: before))
        revertOffer = recent.corrected(before: before, after: proxy.documentContextAfterInput ?? "")
        refresh()
    }

    /// Asks for suggestions for the current state (also on appear and language switches).
    func refresh() {
        expectedBefore = before
        client.request(EngineClient.Request(lang: lang, context: contextWords(before: before), taps: taps, traits: traits,
                                            settings: settings, inToken: insideNonWordToken(before: before)))
    }

    /// Re-renders the bar from the latest result, e.g. after shift changes the casing.
    func redrawBar() {
        if let shown { show(shown) }
    }

    private func show(_ result: EngineClient.Result) {
        shown = result
        let capitalized = isShifted() || literal.first?.isUppercase == true
        // A literal retyped where it was autocorrected commits as typed, so it shows no pending autocorrect.
        let retyping = recent.retyped(literal, before: String(before.dropLast(literal.count))) != nil
        onSlots?(barSlots(result.candidates, autocorrect: retyping ? nil : result.autocorrect, literal: literal, lang: lang,
                          capitalized: capitalized, emoji: result.emoji, revert: revertOffer?.literal, rescue: result.rescue))
    }

    // MARK: Commit

    /// Commits the current word before a space, punctuation or return: autocorrects it when the
    /// current result says so (SPEC 8.5) and tells the learner. A literal retyped where it was
    /// autocorrected is kept, and the autocorrect rejected. Returns the replacement, if any.
    @discardableResult
    private func commitWord() -> String? {
        let literal = literal, taps = taps
        let context = contextWords(before: before)
        let prefix = String(before.dropLast(literal.count))
        self.taps = []
        defer { (restoredLiteral, pastedWord) = (nil, nil) }
        guard literal != restoredLiteral, literal != pastedWord else {  // already learned, or pasted
            trace("commitWord \(literal.debugDescription) restored or pasted, delete 0")
            return nil
        }
        if let retyped = recent.retyped(literal, before: prefix) {
            trace("commitWord \(literal.debugDescription) retyped, delete 0")
            recent.remove(retyped)
            client.revertAutocorrect(literal, replacement: retyped.replacement, lang: lang, context: context)
            return nil
        }
        guard let target = client.resultForCommit()?.autocorrect else {
            trace("commitWord \(literal.debugDescription) delete 0")
            learn(literal, context: context, how: .typed, taps: taps)
            return nil
        }
        let replacement = cased(target.text, capitalized: literal.first?.isUppercase == true)
        trace("commitWord \(literal.debugDescription) -> \(replacement.debugDescription) delete \(literal.count)")
        delete(literal.count)
        insert(replacement)
        learn(replacement, context: context, how: .autocorrect(from: literal), taps: taps)
        undo = AutocorrectUndo(literal: literal, taps: taps, replacement: replacement)
        recent.add(literal: literal, replacement: replacement, before: prefix)
        return replacement
    }

    /// Ends the undo slot and the revert offer. Once backspace took its punctuation the cursor is back
    /// in the corrected word, so the learner now hears what a plain backspace there would have told it.
    private func dropUndo() {
        if let undo, undo.tail.isEmpty { client.backspaced(into: undo.replacement, lang: lang) }
        undo = nil
        revertOffer = nil
    }

    /// Numbers and stray marks aren't words (SPEC 6.2), so the learner only sees words with a letter.
    /// The taps go along for the key offsets (SPEC 9.2).
    private func learn(_ word: String, context: [String], how: Learner.Commit, taps: [Tap]) {
        guard word.contains(where: \.isLetter) else { return }
        client.commit(word, lang: lang, context: context, how: how, taps: taps)
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
