import Foundation

/// Row counts of the store, for the host app's Data screen.
public struct StoreStats: Equatable, Sendable {
    public struct Words: Equatable, Sendable {
        public var known: Int
        public var pending: Int
        public var blocked: Int

        public init(known: Int = 0, pending: Int = 0, blocked: Int = 0) {
            (self.known, self.pending, self.blocked) = (known, pending, blocked)
        }
    }

    public var words: [String: Words] = [:]  // by store lang: en, ar, tok
    public var ngrams = 0
    public var corrections = 0

    public init() {}
}

/// One learned word, as the host app lists it.
public struct LearnedWord: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable { case pending, known, blocked }

    public let lang: String
    public let ident: String
    public let display: String
    public let state: State
    public let count: Double  // decayed to its last use, so a word seen twice reads about 2
    public var id: String { lang + "/" + ident }
}

public enum StoreError: Error, Equatable {
    case notAKalamStore
}

/// Store management for the host app (SPEC 10). Each call is one short statement or transaction,
/// since the keyboard may be writing at the same time.
extension PersonalStore {
    /// The one store both the keyboard and the host app open; nil without App Group access.
    public static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.appGroup)?
            .appendingPathComponent("personal.sqlite")
    }

    public func stats() throws -> StoreStats {
        var stats = StoreStats()
        try db.query("SELECT lang, state, count(*) FROM words GROUP BY lang, state") { row in
            let n = row.int(2)
            switch WordRow.State(rawValue: row.text(1)) {
            case .known: stats.words[row.text(0), default: .init()].known = n
            case .pending: stats.words[row.text(0), default: .init()].pending = n
            case .blocked: stats.words[row.text(0), default: .init()].blocked = n
            case nil: break
            }
        }
        try db.query("SELECT count(*) FROM ngrams") { stats.ngrams = $0.int(0) }
        try db.query("SELECT count(*) FROM corrections") { stats.corrections = $0.int(0) }
        return stats
    }

    /// The most frequent words of a lang whose spelling or normalized form contains `search`.
    /// ponytail: capped at `limit`, searching reaches the rest.
    public func learnedWords(lang: String, search: String = "", limit: Int = 500) throws -> [LearnedWord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let norm = Self.norm(query, lang: lang)
        var words: [LearnedWord] = []
        try db.query("""
            SELECT ident, display, state, count FROM words
            WHERE lang = ? AND (? = '' OR instr(ident, ?) > 0 OR instr(norm, ?) > 0 OR instr(display, ?) > 0)
            ORDER BY count DESC LIMIT ?
            """, [lang, query, query.lowercased(), norm, query, limit]) {
            words.append(LearnedWord(lang: lang, ident: $0.text(0), display: $0.text(1),
                                     state: LearnedWord.State(rawValue: $0.text(2)) ?? .pending,
                                     count: $0.double(3)))
        }
        return words
    }

    /// Deletes a word with its n-grams and corrections, as if it had never been typed.
    public func forget(lang: String, ident: String) throws {
        try db.transaction {
            try db.query("DELETE FROM words WHERE lang = ? AND ident = ?", [lang, ident])
            try db.query("DELETE FROM ngrams WHERE lang = ? AND (w1 = ? OR w2 = ? OR w3 = ?)", [lang, ident, ident, ident])
            try db.query("DELETE FROM corrections WHERE lang = ? AND (typed = ? OR chosen = ?)", [lang, ident, ident])
        }
    }

    public func block(_ word: LearnedWord, now: Date = Date()) throws {
        try block(lang: word.lang, ident: word.ident, display: word.display, now: now.timeIntervalSince1970)
    }

    /// Adds the words of `text` as known (source manual), which also unblocks them. Returns how many.
    @discardableResult
    public func addManually(_ text: String, now: Date = Date()) throws -> Int {
        var batch = LearningBatch(halfLife: config.halfLife)
        let tokens = tokenize(text).filter { $0.kind != .sentenceEnd }
        for token in tokens {
            batch.addWord(token.surface, kind: token.kind, context: [], at: now.timeIntervalSince1970, source: .manual)
        }
        try write(batch)
        return tokens.count
    }

    public func resetLearning() throws {
        try db.transaction {
            for table in ["words", "ngrams", "corrections", "meta"] { try db.execute("DELETE FROM \(table)") }
        }
    }

    /// Writes a consistent copy of the store to `url`, which must not exist yet.
    public func backup(to url: URL) throws {
        try db.query("VACUUM INTO ?", [url.path])
    }

    /// Replaces the whole store with a backup, in one write transaction, then migrates it if it's
    /// older. Throws notAKalamStore, leaving the store untouched, unless `url` is a Kalam store.
    public func restore(from url: URL) throws {
        let source = try SQLite(url: url, readOnly: true)
        var (version, tables) = (0, 0)
        do {
            try source.query("PRAGMA user_version") { version = $0.int(0) }
            try source.query("""
                SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name IN ('words', 'ngrams', 'corrections', 'meta')
                """) { tables = $0.int(0) }
        } catch {
            throw StoreError.notAKalamStore  // not an SQLite file
        }
        guard (1...Self.schemaVersion).contains(version), tables == 4 else { throw StoreError.notAKalamStore }
        try db.replaceContent(with: source)
        try migrate()
    }
}

/// Chat senders with their message counts, most messages first.
public func senderCounts(_ messages: [ChatMessage]) -> [(sender: String, messages: Int)] {
    Dictionary(grouping: messages, by: \.sender).map { ($0.key, $0.value.count) }
        .sorted { ($0.messages, $1.sender) > ($1.messages, $0.sender) }
}

extension PersonalStore {
    /// Learns the messages of the chosen senders only (SPEC 9.3: only Moe's messages are learned).
    public func importChat(_ messages: [ChatMessage], senders: Set<String>, lexicons: [BaseLexicon],
                           settings: Settings = Settings(), now: Date = Date()) throws {
        let texts = messages.filter { senders.contains($0.sender) }.map { (text: $0.text, date: $0.date) }
        try importTexts(texts, lexicons: lexicons, settings: settings, now: now)
    }
}
