//
//  SQLiteDatabaseTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class SQLiteDatabaseTests: XCTestCase {
    func testOpenCloseAndCRUDWithInMemoryDatabase() throws {
        let db = iTermSqliteDatabaseImpl.inMemoryDatabase()
        XCTAssertTrue(db.open())
        defer { _ = db.close() }

        XCTAssertTrue(db.executeUpdate(
            "CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, flag INTEGER, big INTEGER, payload BLOB, created REAL)",
            withArgumentsIn: []
        ))

        let created = Date(timeIntervalSince1970: 1_700_000_123.5)
        let payload = Data([0x01, 0x02, 0x03, 0xFE])
        XCTAssertTrue(db.executeUpdate(
            "INSERT INTO items (name, flag, big, payload, created) VALUES (?, ?, ?, ?, ?)",
            withArgumentsIn: ["alpha", true, Int64(9_000_000_012), payload, created]
        ))
        let firstRowID = db.lastInsertRowId()?.int64Value
        XCTAssertEqual(firstRowID, 1)

        XCTAssertTrue(db.executeUpdate(
            "INSERT INTO items (name, flag, big, payload, created) VALUES (?, ?, ?, ?, ?)",
            withArgumentsIn: ["beta", false, Int64(42), Data(), nil]
        ))
        XCTAssertEqual(db.lastInsertRowId()?.int64Value, 2)

        guard let rs = db.executeQuery(
            "SELECT name, flag, big, payload, created FROM items ORDER BY id ASC",
            withArgumentsIn: []
        ) else {
            XCTFail("Expected result set")
            return
        }
        defer { rs.close() }

        XCTAssertTrue(rs.next())
        XCTAssertEqual(rs.string(forColumn: "name"), "alpha")
        XCTAssertEqual(rs.string(forColumn: "NAME"), "alpha")
        XCTAssertTrue(rs.bool(forColumn: "flag"))
        XCTAssertEqual(rs.int(forColumn: "flag"), 1)
        XCTAssertEqual(rs.longLongInt(forColumn: "big"), 9_000_000_012)
        XCTAssertEqual(rs.data(forColumn: "payload"), payload)
        let roundTrippedDate = try XCTUnwrap(rs.date(forColumn: "created"))
        XCTAssertEqual(roundTrippedDate.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertTrue(rs.next())
        XCTAssertEqual(rs.string(forColumn: "name"), "beta")
        XCTAssertFalse(rs.bool(forColumn: "flag"))
        XCTAssertEqual(rs.int(forColumn: "flag"), 0)
        XCTAssertEqual(rs.longLongInt(forColumn: "big"), 42)
        XCTAssertEqual(rs.data(forColumn: "payload"), Data())
        XCTAssertNil(rs.date(forColumn: "created"))

        XCTAssertFalse(rs.next())
    }

    func testInvalidSQLPopulatesLastErrorAndThrows() {
        let db = iTermSqliteDatabaseImpl.inMemoryDatabase()
        XCTAssertTrue(db.open())
        defer { _ = db.close() }

        XCTAssertThrowsError(try (db as iTermDatabase).executeUpdate("THIS IS NOT SQL", withArguments: []))
        let err = db.lastError() as NSError
        XCTAssertEqual(err.domain, "iTermSqliteDatabase")
        XCTAssertFalse(err.localizedDescription.isEmpty)
    }

    func testTransactionCommitAndRollback() {
        let db = iTermSqliteDatabaseImpl.inMemoryDatabase()
        XCTAssertTrue(db.open())
        defer { _ = db.close() }

        XCTAssertTrue(db.executeUpdate("CREATE TABLE kv (k TEXT PRIMARY KEY)", withArgumentsIn: []))

        let committed = db.transaction {
            db.executeUpdate("INSERT INTO kv (k) VALUES (?)", withArgumentsIn: ["kept"])
        }
        XCTAssertTrue(committed)

        let rolledBack = db.transaction {
            _ = db.executeUpdate("INSERT INTO kv (k) VALUES (?)", withArgumentsIn: ["discarded"])
            return false
        }
        XCTAssertFalse(rolledBack)

        guard let rs = db.executeQuery("SELECT k FROM kv ORDER BY k", withArgumentsIn: []) else {
            XCTFail("Expected query result")
            return
        }
        defer { rs.close() }

        var keys: [String] = []
        while rs.next() {
            if let key = rs.string(forColumn: "k") {
                keys.append(key)
            }
        }
        XCTAssertEqual(keys, ["kept"])
    }
}
