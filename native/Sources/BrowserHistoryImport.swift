// SPDX-License-Identifier: MPL-2.0
import Foundation
import SQLite3

enum HistoryImportError: Error {
    case source, busy, format, destination, noVisits
    func message(english: Bool) -> String {
        switch self {
        case .busy: return english ? "Quit the source browser, then try again." : "Quittez le navigateur d’origine, puis réessayez."
        case .source: return english ? "Choose the history file in the source profile and allow access to it." : "Choisissez le fichier d’historique dans le profil d’origine et autorisez sa lecture."
        case .format: return english ? "This file does not contain history from the selected browser." : "Ce fichier ne contient pas l’historique du navigateur sélectionné."
        case .destination: return english ? "The destination profile’s history is unavailable. Open a page in that profile and try again." : "L’historique du profil de destination est indisponible. Ouvrez une page dans ce profil, puis réessayez."
        case .noVisits: return english ? "No web visits were found in this history." : "Aucune visite web trouvée dans cet historique."
        }
    }
}

private final class HistoryDatabase {
    let db: OpaquePointer
    private let failure: HistoryImportError
    init(_ url: URL, flags: Int32, failure: HistoryImportError) throws {
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard code == SQLITE_OK, let handle else { sqlite3_close(handle); throw failure }
        self.db = handle
        self.failure = failure
        sqlite3_busy_timeout(db, 1500)
        try execute("PRAGMA trusted_schema=OFF")
    }
    deinit { sqlite3_close(db) }
    func check(_ code: Int32) throws {
        if code == SQLITE_BUSY || code == SQLITE_LOCKED { throw HistoryImportError.busy }
        guard code == SQLITE_OK else { throw failure }
    }
    func execute(_ sql: String) throws { try check(sqlite3_exec(db, sql, nil, nil, nil)) }
    func statement(_ sql: String) throws -> HistoryStatement { try HistoryStatement(database:self, sql:sql) }
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
}

private final class HistoryStatement {
    private let database: HistoryDatabase
    private let stmt: OpaquePointer
    init(database: HistoryDatabase, sql:String) throws {
        self.database = database
        var ptr: OpaquePointer?
        try database.check(sqlite3_prepare_v2(database.db,sql,-1,&ptr,nil))
        guard let ptr else { throw HistoryImportError.format }; stmt = ptr
    }
    deinit { sqlite3_finalize(stmt) }
    func bind(_ value: String, _ index: Int32) throws {
        try database.check(sqlite3_bind_text(stmt,index,value,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)))
    }
    func bind(_ value: Int64, _ index: Int32) throws { try database.check(sqlite3_bind_int64(stmt,index,value)) }
    func next() throws -> Bool {
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        try database.check(result)
        return false
    }
    func run() throws { _ = try next(); try database.check(sqlite3_reset(stmt)) }
    func text(_ index: Int32) -> String {
        guard let bytes = sqlite3_column_text(stmt, index) else { return "" }
        let value = UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(stmt, index)))
        guard !value.contains(0) else { return "" }
        return String(decoding: value, as: UTF8.self)
    }
    func number(_ index: Int32) -> Int64 { sqlite3_column_int64(stmt,index) }
}

enum BrowserHistoryImport {
    enum Source {
        case chromium, firefox, safari
        var filename: String {
            switch self { case .chromium: return "History"; case .firefox: return "places.sqlite"; case .safari: return "History.db" }
        }
        var query: String {
            // Chromium counts microseconds since 1601, Firefox since 1970,
            // and Safari counts seconds since 2001.
            switch self {
            case .chromium:
                return "SELECT u.url,u.title,v.visit_time FROM visits v JOIN urls u ON u.id=v.url WHERE u.hidden=0 AND (v.transition & 255) NOT IN (3,4)"
            case .firefox:
                return "SELECT p.url,p.title,v.visit_date+11644473600000000 FROM moz_historyvisits v JOIN moz_places p ON p.id=v.place_id WHERE p.hidden=0 AND v.visit_type NOT IN (4,7,8)"
            case .safari:
                return "SELECT i.url,v.title,CAST(ROUND(v.visit_time*1000000) AS INTEGER)+12622780800000000 FROM history_visits v JOIN history_items i ON i.id=v.history_item WHERE v.visit_time IS NOT NULL"
            }
        }
        var code: Int64 { switch self { case .firefox: return 3; case .safari: return 5; case .chromium: return 7 } }
    }
    private static let pendingFile = "Arc Reborn Pending Visits.sqlite"
    static func hasPending(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath:directory.appendingPathComponent(pendingFile).path)
    }

    // Only the selected source and our private queue are opened during browsing.
    static func stage(from file: URL, source: Source, into directory: URL) throws -> Int {
        let fm = FileManager.default
        let input = try HistoryDatabase(file, flags:SQLITE_OPEN_READONLY, failure:.source)
        let visits: HistoryStatement
        do { visits = try input.statement(source.query) }
        catch HistoryImportError.busy { throw HistoryImportError.busy }
        catch { throw HistoryImportError.format }
        let latest = Int64((Date().timeIntervalSince1970 + 11644473600 + 86400) * 1000000)
        func nextVisit() throws -> (url: String, time: Int64, title: String)? {
            while try visits.next() {
                let time = visits.number(2)
                guard time > 11644473600000000, time < latest,
                      let address = BrowserImportReader.cleanURL(visits.text(0)) else { continue }
                return (address, time, String(visits.text(1).prefix(2048)))
            }
            return nil
        }
        guard var row = try nextVisit() else { throw HistoryImportError.noVisits }

        // Creating a new named CEF context is asynchronous. Wait here on the
        // import worker, never on the window thread or with a live History handle.
        let history = directory.appendingPathComponent("History")
        for _ in 0..<30 {
            if fm.fileExists(atPath: history.path) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard fm.fileExists(atPath: history.path) else { throw HistoryImportError.destination }
        let pending = directory.appendingPathComponent(pendingFile)
        let queue = try HistoryDatabase(pending, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, failure: .destination)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pending.path)
        try queue.execute("CREATE TABLE IF NOT EXISTS pending(url TEXT NOT NULL,time INTEGER NOT NULL,title TEXT NOT NULL,source INTEGER NOT NULL,PRIMARY KEY(url,time)) WITHOUT ROWID")
        let append = try queue.statement("INSERT OR IGNORE INTO pending VALUES(?,?,?,?)")
        var count = 0
        try queue.transaction {
            while true {
                try append.bind(row.url, 1)
                try append.bind(row.time, 2)
                try append.bind(row.title, 3)
                try append.bind(source.code, 4)
                try append.run()
                count += Int(sqlite3_changes(queue.db))
                guard let next = try nextVisit() else { break }
                row = next
            }
        }
        return count
    }

    /// Called before any named Chromium profile is opened on startup, after
    /// CEF has acquired its process lock. A failed merge retains the queue.
    static func applyPending(in directory: URL) throws {
        guard hasPending(in:directory) else { return }
        let pending = directory.appendingPathComponent(pendingFile)
        let destination = try HistoryDatabase(directory.appendingPathComponent("History"), flags:SQLITE_OPEN_READWRITE, failure:.destination)
        let version = try destination.statement("SELECT value FROM meta WHERE key='version'")
        // The statements below target the schema of the pinned Chromium build.
        guard try version.next(), version.number(0) == 70 else { throw HistoryImportError.destination }
        let queue = try HistoryDatabase(pending,flags:SQLITE_OPEN_READONLY,failure:.destination)
        let rows = try queue.statement("SELECT url,time,title,source FROM pending ORDER BY url,time")
        let url = try destination.statement("INSERT INTO urls(url,title,last_visit_time) SELECT ?1,?2,0 WHERE NOT EXISTS(SELECT 1 FROM urls WHERE url=?1)")
        // CHAIN_START | CHAIN_END marks a top-level navigation in chrome://history.
        let visit = try destination.statement("""
            INSERT INTO visits(url,visit_time,transition,from_visit) SELECT id,?2,805306368,0 FROM urls
            WHERE id=(SELECT id FROM urls WHERE url=?1 LIMIT 1)
            AND NOT EXISTS(SELECT 1 FROM visits WHERE visit_time=?2 AND url=urls.id)
            """)
        let mark = try destination.statement("INSERT INTO visit_source(id,source) VALUES(?,?)")
        let update = try destination.statement("""
            UPDATE urls SET visit_count=visit_count+1,
            title=CASE WHEN ?2<>'' AND (title IS NULL OR title='' OR last_visit_time<=?3) THEN ?2 ELSE title END,
            last_visit_time=MAX(last_visit_time,?3) WHERE id=(SELECT url FROM visits WHERE id=?1)
            """)
        try destination.transaction {
            while try rows.next() {
                let address = rows.text(0), time = rows.number(1), title = rows.text(2)
                try url.bind(address,1); try url.bind(title,2); try url.run()
                try visit.bind(address,1); try visit.bind(time,2); try visit.run()
                guard sqlite3_changes(destination.db) > 0 else { continue }
                let id = sqlite3_last_insert_rowid(destination.db)
                try mark.bind(id,1); try mark.bind(rows.number(3),2); try mark.run()
                try update.bind(id,1); try update.bind(title,2); try update.bind(time,3); try update.run()
            }
        }
        try FileManager.default.removeItem(at:pending)
    }
}
