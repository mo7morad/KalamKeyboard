import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var description: String { "SQLite \(code): \(message)" }
}

protocol SQLValue {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension String: SQLValue {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 { sqlite3_bind_text(statement, index, self, -1, transient) }
}

extension Int: SQLValue {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 { sqlite3_bind_int64(statement, index, Int64(self)) }
}

extension Double: SQLValue {
    func bind(to statement: OpaquePointer, at index: Int32) -> Int32 { sqlite3_bind_double(statement, index, self) }
}

struct Row {
    fileprivate let statement: OpaquePointer
    func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
}

/// Thin wrapper over the system SQLite3 C API (D4). One connection, confined to one queue.
final class SQLite {
    private var db: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]

    init(url: URL) throws {
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK else {
            let error = SQLiteError(code: rc, message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
            sqlite3_close(db)
            throw error
        }
    }

    deinit {
        statements.values.forEach { sqlite3_finalize($0) }
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }

    /// Runs one statement and calls `row` per result row. The statement is reset before returning,
    /// so no read lock outlives the call.
    func query(_ sql: String, _ args: [SQLValue] = [], row: (Row) throws -> Void = { _ in }) throws {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (i, arg) in args.enumerated() { try check(arg.bind(to: statement, at: Int32(i + 1))) }
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { return }
            try check(rc == SQLITE_ROW ? SQLITE_OK : rc)
            try row(Row(statement: statement))
        }
    }

    /// One short write transaction. BEGIN IMMEDIATE takes the write lock up front (waiting up to
    /// busy_timeout), so a read-modify-write inside is safe against the other process's writer.
    /// Any error rolls back. Never hold a transaction across calls (0xdead10cc).
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
        guard let statement else { throw SQLiteError(code: SQLITE_MISUSE, message: "empty statement") }
        statements[sql] = statement
        return statement
    }

    private func check(_ rc: Int32) throws {
        guard rc == SQLITE_OK else { throw SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(db))) }
    }
}
