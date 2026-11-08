// SPDX-License-Identifier: MPL-2.0
import Foundation
import SQLite3

@main struct BrowserHistoryImportTests {
    static func database(_ file: URL, _ sql: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open(file.path, &db) == SQLITE_OK else { fatalError("fixture open") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        if sql.hasPrefix("SELECT") {
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { fatalError("fixture select") }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return "" }
            return String(cString: value)
        }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError(String(cString:sqlite3_errmsg(db))) }
        return ""
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let profile = root.appendingPathComponent("Destination"), other = root.appendingPathComponent("Other")
        for folder in [profile, other] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        let history = profile.appendingPathComponent("History")
        _ = try database(history, """
            CREATE TABLE meta(key TEXT PRIMARY KEY,value INTEGER); INSERT INTO meta VALUES('version',70);
            CREATE TABLE urls(id INTEGER PRIMARY KEY,url TEXT,title TEXT,visit_count INTEGER DEFAULT 0,last_visit_time INTEGER);
            CREATE INDEX urls_url ON urls(url);
            CREATE TABLE visits(id INTEGER PRIMARY KEY,url INTEGER,visit_time INTEGER,transition INTEGER,from_visit INTEGER);
            CREATE INDEX visits_time ON visits(visit_time); CREATE TABLE visit_source(id INTEGER PRIMARY KEY,source INTEGER);
            """)
        let day: Int64 = 1700000000
        let time = (day + 11644473600) * 1000000
        let safari = root.appendingPathComponent("History.db"), firefox = root.appendingPathComponent("places.sqlite")
        let chrome = root.appendingPathComponent("Chrome"), empty = root.appendingPathComponent("Empty")
        _ = try database(safari, """
            CREATE TABLE history_items(id INTEGER PRIMARY KEY,url TEXT);
            CREATE TABLE history_visits(history_item INTEGER,visit_time REAL,title TEXT);
            INSERT INTO history_items VALUES(1,'https://example.test/été');
            INSERT INTO history_visits VALUES(1,\(day-978307200),'Café'),(1,\(day-978307199),'Thé');
            """)
        _ = try database(firefox, """
            CREATE TABLE moz_places(id INTEGER PRIMARY KEY,url TEXT,title TEXT,hidden INTEGER);
            CREATE TABLE moz_historyvisits(place_id INTEGER,visit_date INTEGER,visit_type INTEGER);
            INSERT INTO moz_places VALUES(1,'https://firefox.test/','Firefox',0),(2,'https://example.test/été','Doublon',0);
            INSERT INTO moz_historyvisits VALUES(1,\(day*1000000),9),(1,\(day*1000000+500),8),(2,\(day*1000000),1);
            """)
        let chromiumSchema = """
            CREATE TABLE urls(id INTEGER PRIMARY KEY,url TEXT,title TEXT,hidden INTEGER);
            CREATE TABLE visits(url INTEGER,visit_time INTEGER,transition INTEGER);
            """
        _ = try database(chrome, chromiumSchema + """
            INSERT INTO urls VALUES(1,'https://chrome.test/','Chrome',0),(2,'https://u:p@example.test/','secret',0),
            (3,'file:///etc/hosts','local',0),(4,'https://hidden.test/','hidden',1);
            INSERT INTO visits VALUES(1,\(time),0),(1,\(time+1),3),(2,\(time),0),(3,\(time),0),(4,\(time),0);
            """)
        _ = try database(empty, chromiumSchema)
        func expect(_ value: Bool, _ label: String) { precondition(value, label); print("PASS", label) }
        do {
            _ = try BrowserHistoryImport.stage(from: empty, source:.chromium, into:profile)
            fatalError("empty input accepted")
        } catch HistoryImportError.noVisits { expect(!BrowserHistoryImport.hasPending(in:profile), "Empty source leaves no queue") }
        do {
            _ = try BrowserHistoryImport.stage(from: safari, source:.firefox, into:profile)
            fatalError("invalid source accepted")
        } catch HistoryImportError.format { expect(!BrowserHistoryImport.hasPending(in:profile), "Wrong file is recoverable") }
        func stageAll() throws -> [Int] {
            return try [(safari,BrowserHistoryImport.Source.safari),(firefox,.firefox),(chrome,.chromium)].map {
                try BrowserHistoryImport.stage(from:$0.0, source:$0.1, into:profile)
            }
        }
        expect(try stageAll() == [2,1,1], "Three source formats, correct date epochs, top-level HTTP visits only")
        expect(try stageAll() == [0,0,0], "Deduplicates between sources and repeated imports")
        expect(!BrowserHistoryImport.hasPending(in:other), "Destination profile isolated")
        expect(try database(history,"SELECT count(*) FROM visits") == "0", "Destination untouched while browser is running")
        _ = try database(history, """
            INSERT INTO urls VALUES(1,'https://example.test/été','Titre récent',1,\(time+2000000));
            INSERT INTO visits VALUES(1,1,\(time),805306368,0);
            CREATE TRIGGER fail_visit BEFORE INSERT ON visits BEGIN SELECT RAISE(ABORT,'fixture failure'); END;
            """)
        do {
            try BrowserHistoryImport.applyPending(in:profile)
            fatalError("partial merge accepted")
        } catch HistoryImportError.destination {
            expect(BrowserHistoryImport.hasPending(in:profile), "Failed merge retained for retry")
            expect(try database(history,"SELECT count(*) FROM visits") == "1", "Partial inserts rolled back")
        }
        _ = try database(history,"DROP TRIGGER fail_visit")
        try BrowserHistoryImport.applyPending(in:profile)
        expect(!BrowserHistoryImport.hasPending(in:profile), "Successful merge clears the queue")
        expect(try database(history,"SELECT count(*) FROM visits") == "4", "Existing visit preserved once")
        expect(try database(history,"SELECT visit_count||':'||title FROM urls WHERE id=1") == "2:Titre récent", "Existing title and visit count preserved")
        expect(try database(history,"SELECT count(*) FROM visit_source") == "3", "Only imported visits marked")
        expect(try database(history,"SELECT count(*) FROM visits WHERE visit_time=\(time)") == "3", "Safari, Firefox and Chromium agree on the original date")
        expect(try database(history,"SELECT COUNT(*) FROM visits WHERE (transition & 805306368)=805306368") == "4", "Native history can display the imported visits")
        _ = try stageAll()
        try BrowserHistoryImport.applyPending(in:profile)
        expect(try database(history,"SELECT count(*) FROM visits") == "4", "Re-import after restart is idempotent")
    }
}
