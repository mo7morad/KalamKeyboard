import Foundation

/// A row of the words table.
struct WordRow {
    enum State: String { case pending, known, blocked }

    let ident: String
    let norm: String
    let display: String
    let hits: Hits
    let state: State
}

/// Moe's personal data (SPEC 9.1) in SQLite: the App Group container on device, a temp dir in tests.
/// The keyboard and the host app each open their own instance on the same file. Every write is one
/// short BEGIN IMMEDIATE transaction, so the two processes' writers serialize under WAL.
public final class PersonalStore {
    private let db: SQLite
    let config: EngineConfig

    public init(url: URL, config: EngineConfig = EngineConfig()) throws {
        db = try SQLite(url: url)
        self.config = config
        try db.query("PRAGMA busy_timeout = \(config.storeBusyTimeoutMs)")
        try db.query("PRAGMA journal_mode = WAL")
        try migrate()
    }

    /// Schema versions, applied in order and tracked in PRAGMA user_version.
    /// words.uses / imports are raw (undecayed) counts for the pending -> known rules, since a decayed
    /// count of 2 uses is already below 2. display_votes runs a majority vote over display forms.
    /// Bigrams are ngrams rows with w1 = ''. Context totals are the sums of the loaded continuations,
    /// which decay the same way, so there's no ctx_totals table.
    private static let migrations = [
        """
        CREATE TABLE words(
            lang TEXT NOT NULL, ident TEXT NOT NULL, norm TEXT NOT NULL, display TEXT NOT NULL,
            display_votes INTEGER NOT NULL DEFAULT 0, count REAL NOT NULL, t_last REAL NOT NULL,
            state TEXT NOT NULL, sessions_seen INTEGER NOT NULL DEFAULT 0, last_session INTEGER NOT NULL DEFAULT 0,
            uses INTEGER NOT NULL DEFAULT 0, imports INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL, accepted_explicitly INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(lang, ident)) WITHOUT ROWID;
        CREATE TABLE ngrams(
            lang TEXT NOT NULL, w1 TEXT NOT NULL, w2 TEXT NOT NULL, w3 TEXT NOT NULL,
            count REAL NOT NULL, t_last REAL NOT NULL,
            PRIMARY KEY(lang, w1, w2, w3)) WITHOUT ROWID;
        CREATE TABLE corrections(
            lang TEXT NOT NULL, typed TEXT NOT NULL, chosen TEXT NOT NULL, rejected INTEGER NOT NULL,
            count REAL NOT NULL, t_last REAL NOT NULL,
            PRIMARY KEY(lang, typed, chosen, rejected)) WITHOUT ROWID;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT) WITHOUT ROWID;
        """,
    ]

    static var schemaVersion: Int { migrations.count }

    private func migrate() throws {
        try db.transaction {
            var version = 0
            try db.query("PRAGMA user_version") { version = $0.int(0) }
            guard version <= Self.migrations.count else {
                throw SQLiteError(code: 0, message: "schema \(version) is newer than this build")
            }
            for sql in Self.migrations.dropFirst(version) { try db.execute(sql) }
            try db.execute("PRAGMA user_version = \(Self.migrations.count)")
        }
    }

    // MARK: Reads (each is one autocommit statement)

    /// Every word of a lang (en, ar or tok). The primary key's lang prefix serves the scan.
    func words(lang: String) throws -> [WordRow] {
        var rows: [WordRow] = []
        try db.query("SELECT ident, norm, display, count, t_last, state FROM words WHERE lang = ?", [lang]) {
            rows.append(Self.wordRow($0))
        }
        return rows
    }

    func word(lang: String, ident: String) throws -> WordRow? {
        var row: WordRow?
        try db.query("SELECT ident, norm, display, count, t_last, state FROM words WHERE lang = ? AND ident = ?", [lang, ident]) {
            row = Self.wordRow($0)
        }
        return row
    }

    /// Raw typed uses of a word: how often Moe kept it (SPEC 8.5 variant fix).
    func uses(lang: String, ident: String) throws -> Int {
        var uses = 0
        try db.query("SELECT uses FROM words WHERE lang = ? AND ident = ?", [lang, ident]) { uses = $0.int(0) }
        return uses
    }

    /// Continuations of a context: w1 = "" for the bigram context (b), w1 = a for (a, b).
    func continuations(lang: String, w1: String, w2: String) throws -> [String: Hits] {
        var result: [String: Hits] = [:]
        try db.query("SELECT w3, count, t_last FROM ngrams WHERE lang = ? AND w1 = ? AND w2 = ?", [lang, w1, w2]) {
            result[$0.text(0)] = Hits(count: $0.double(1), time: $0.double(2))
        }
        return result
    }

    func corrections() throws -> [LearningBatch.CorrectionKey] {
        var result: [LearningBatch.CorrectionKey] = []
        try db.query("SELECT lang, typed, chosen, rejected FROM corrections") {
            result.append(LearningBatch.CorrectionKey(lang: $0.text(0), typed: $0.text(1), chosen: $0.text(2), rejected: $0.int(3) != 0))
        }
        return result
    }

    // MARK: Writes

    /// Blocks a word (SPEC 5.4 "Forget"): it's never suggested again and learning can't revive it.
    func block(lang: String, ident: String, display: String, now: Double) throws {
        try db.transaction {
            try db.query("""
                INSERT INTO words(lang, ident, norm, display, count, t_last, state, source)
                VALUES(?, ?, ?, ?, 0, ?, 'blocked', 'manual')
                ON CONFLICT(lang, ident) DO UPDATE SET state = 'blocked'
                """, [lang, ident, Self.norm(ident, lang: lang), display, now])
        }
    }

    /// Writes a batch in transactions of at most `chunk` rows each, so a big import never holds the
    /// write lock for long. A failed chunk rolls back and throws; the chunks before it stay written
    /// (a learner batch is far under one chunk, so its retry never double-counts).
    func write(_ batch: LearningBatch, chunk: Int = 2000) throws {
        let rows: [() throws -> Void] = batch.words.map { key, update in { try self.writeWord(key, update) } }
            + batch.ngrams.map { key, hits in { try self.writeNgram(key, hits) } }
            + batch.corrections.map { key, hits in { try self.writeCorrection(key, hits) } }
        for start in stride(from: 0, to: rows.count, by: chunk) {
            try db.transaction {
                for row in rows[start..<min(start + chunk, rows.count)] { try row() }
            }
        }
    }

    /// The columns of a words row that a write merges into.
    private struct StoredWord {
        var display: String
        var votes = 0
        var hits = Hits()
        var state = WordRow.State.pending
        var sessions = 0
        var lastSession = 0
        var uses = 0
        var imports = 0
        var source: String
        var explicit = false
    }

    private func writeWord(_ key: LearningBatch.WordKey, _ update: LearningBatch.WordUpdate) throws {
        var word = try storedWord(key) ?? StoredWord(display: update.display, source: update.source.rawValue)
        word.hits.add(update.hits.count, at: update.hits.time, halfLife: config.halfLife)
        for (form, n) in update.votes.sorted(by: { $0.key < $1.key }) {  // weighted majority vote
            if form == word.display { word.votes += n } else if word.votes >= n { word.votes -= n } else { (word.display, word.votes) = (form, n - word.votes) }
        }
        if let session = update.session, session != word.lastSession { (word.sessions, word.lastSession) = (word.sessions + 1, session) }
        word.uses += update.uses
        word.imports += update.imports
        word.explicit = word.explicit || update.explicit
        word.state = nextState(word, source: update.source)
        try db.query("""
            INSERT OR REPLACE INTO words(lang, ident, norm, display, display_votes, count, t_last, state, sessions_seen,
                last_session, uses, imports, source, accepted_explicitly)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [key.lang, key.ident, Self.norm(key.ident, lang: key.lang), word.display, word.votes, word.hits.count, word.hits.time,
                  word.state.rawValue, word.sessions, word.lastSession, word.uses, word.imports, word.source, word.explicit ? 1 : 0])
    }

    private func storedWord(_ key: LearningBatch.WordKey) throws -> StoredWord? {
        var word: StoredWord?
        try db.query("""
            SELECT display, display_votes, count, t_last, state, sessions_seen, last_session, uses, imports, source, accepted_explicitly
            FROM words WHERE lang = ? AND ident = ?
            """, [key.lang, key.ident]) {
            word = StoredWord(display: $0.text(0), votes: $0.int(1), hits: Hits(count: $0.double(2), time: $0.double(3)),
                              state: WordRow.State(rawValue: $0.text(4)) ?? .pending, sessions: $0.int(5), lastSession: $0.int(6),
                              uses: $0.int(7), imports: $0.int(8), source: $0.text(9), explicit: $0.int(10) != 0)
        }
        return word
    }

    /// pending -> known rules (SPEC 9.2). Known stays known; only a manual add unblocks.
    private func nextState(_ word: StoredWord, source: WordSource) -> WordRow.State {
        switch word.state {
        case .blocked: return source == .manual ? .known : .blocked
        case .known: return .known
        case .pending:
            let known = word.explicit || source == .manual || source == .lexicon || word.imports >= config.knownMinImports
                || (word.uses >= config.knownMinUses && word.sessions >= config.knownMinSessions)
            return known ? .known : .pending
        }
    }

    private func writeNgram(_ key: LearningBatch.NgramKey, _ hits: Hits) throws {
        var merged = Hits()
        try db.query("SELECT count, t_last FROM ngrams WHERE lang = ? AND w1 = ? AND w2 = ? AND w3 = ?", [key.lang, key.w1, key.w2, key.w3]) {
            merged = Hits(count: $0.double(0), time: $0.double(1))
        }
        merged.add(hits.count, at: hits.time, halfLife: config.halfLife)
        try db.query("INSERT OR REPLACE INTO ngrams VALUES(?, ?, ?, ?, ?, ?)", [key.lang, key.w1, key.w2, key.w3, merged.count, merged.time])
    }

    private func writeCorrection(_ key: LearningBatch.CorrectionKey, _ hits: Hits) throws {
        let args: [SQLValue] = [key.lang, key.typed, key.chosen, key.rejected ? 1 : 0]
        var merged = Hits()
        try db.query("SELECT count, t_last FROM corrections WHERE lang = ? AND typed = ? AND chosen = ? AND rejected = ?", args) {
            merged = Hits(count: $0.double(0), time: $0.double(1))
        }
        merged.add(hits.count, at: hits.time, halfLife: config.halfLife)
        try db.query("INSERT OR REPLACE INTO corrections VALUES(?, ?, ?, ?, ?, ?)", args + [merged.count, merged.time])
    }

    // MARK: Helpers

    private static func wordRow(_ row: Row) -> WordRow {
        WordRow(ident: row.text(0), norm: row.text(1), display: row.text(2), hits: Hits(count: row.double(3), time: row.double(4)),
                state: WordRow.State(rawValue: row.text(5)) ?? .pending)
    }

    /// Trie key of an ident: normalized for en / ar, lowercased for special tokens.
    static func norm(_ ident: String, lang: String) -> String {
        Lang(rawValue: lang).map { normalize(ident, lang: $0) } ?? ident.lowercased()
    }
}
