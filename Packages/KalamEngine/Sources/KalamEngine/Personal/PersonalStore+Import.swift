import Foundation

extension PersonalStore {
    /// Learns texts as imports (SPEC 9.3): WhatsApp messages (dated) or pasted text (undated, so
    /// t_last = now - undatedImportAgeDays). Words imported twice become known, except lazy spellings
    /// and likely typos, which only typed use in the keyboard can make known.
    /// `settings` decides whether a lazy spelling's n-grams count for the variant the fix produces.
    public func importTexts(_ texts: [(text: String, date: Date?)], lexicons: [BaseLexicon], settings: Settings = Settings(),
                            now: Date = Date()) throws {
        var batch = LearningBatch(halfLife: config.halfLife)
        let undated = now.timeIntervalSince1970 - config.undatedImportAgeDays * 86_400
        for (text, date) in texts { batch.addText(text, at: date?.timeIntervalSince1970 ?? undated, source: .import) }
        for lang in [Lang.en, .ar] {
            let engine = Engine(lang: lang, lexicon: lexicons.first { $0.lang == lang }, layout: nil, config: config)
            engine.keepLazySpellingsPending(in: &batch, settings: settings)
            engine.markLikelyTypos(in: &batch)
        }
        try write(batch)
    }
}

extension Engine {
    /// Moe leaves some typos unfixed, and importing them twice would make them known (never
    /// corrected). An imported word that isn't a valid base word, with a neighbour within the search's
    /// edit limits that he imported typoNeighbourRatio times as often, is a likely typo instead: it
    /// stays pending and its count goes to corrections(typo -> neighbour).
    func markLikelyTypos(in batch: inout LearningBatch) {
        let lang = self.lang.rawValue
        let imported = batch.words.filter { $0.key.lang == lang && $0.value.imports > 0 }
        var trie = PersonalTrie(cap: Int.max, halfLife: config.halfLife)
        for (key, update) in imported {
            trie.set(key.ident, norm: normalize(key.ident, lang: self.lang), display: key.ident, hits: Hits(count: Double(update.imports), time: 0))
        }
        func imports(_ ident: String) -> Int { imported[LearningBatch.WordKey(lang: lang, ident: ident)]?.imports ?? 0 }

        for (key, update) in imported where !isValidBaseWord(key.ident) {
            let taps = normalize(key.ident, lang: self.lang).utf16.map { SearchTap(unit: $0, point: nil) }
            let neighbour = search(taps, literalLength: key.ident.count, in: trie)
                .filter { $0.completion == 0 }  // a completion is a longer word, not an edit
                .flatMap { trie.idents(ofKey: $0.key) }
                .filter { $0 != key.ident }
                .max { imports($0) < imports($1) }
            guard let neighbour, Double(imports(neighbour)) >= config.typoNeighbourRatio * Double(update.imports) else { continue }
            batch.words[key]?.imports = 0
            batch.addCorrection(lang: lang, typed: key.ident, chosen: neighbour, rejected: false, count: Double(update.imports), at: update.hits.time)
        }
    }

    /// A known literal is never corrected, so an import must not make known a spelling that shares
    /// its key with another valid variant (dont / don't, انا / أنا) or that the base lexicon marks
    /// invalid. Its counts stay. When the variant fix is on, its n-grams count for the more probable
    /// valid variant the fix will produce, so the LM learns "don't" and the 5x ratio still holds.
    func keepLazySpellingsPending(in batch: inout LearningBatch, settings: Settings) {
        guard let lexicon else { return }
        var fixes: [String: String] = [:]
        for key in batch.words.keys where key.lang == lang.rawValue {
            guard let lexKey = lexicon.key(for: normalize(key.ident, lang: lang)) else { continue }
            let variants = lexicon.variants(ofKey: lexKey)
            let invalidItself = variants.contains { lexicon.surface($0) == key.ident && !lexicon.isValid($0) }
            let hasValidSibling = variants.contains { lexicon.surface($0) != key.ident && lexicon.isValid($0) }
            guard invalidItself || hasValidSibling else { continue }
            batch.words[key]?.imports = 0
            // Variants are most probable first, so the first valid one is what the fix turns this into.
            if settings.variantFix(lang), let fixed = variants.first(where: lexicon.isValid).map(lexicon.surface), fixed != key.ident {
                fixes[key.ident] = fixed
            }
        }
        batch.respell(fixes, lang: lang.rawValue)
    }

    func isValidBaseWord(_ ident: String) -> Bool {
        guard let lexicon, let word = lexicon.wordID(ident: ident) else { return false }
        return lexicon.isValid(word)
    }
}
