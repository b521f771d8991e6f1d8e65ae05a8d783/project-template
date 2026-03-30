import XCTest
import SQLite

final class SQLiteTests: XCTestCase {
    func testSQLiteInMemory() throws {
        let db = try Connection(.inMemory)

        try db.run("CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL)")
        try db.run("INSERT INTO users (name) VALUES (?)", "Alice")

        let count = try db.scalar("SELECT COUNT(*) FROM users") as! Int64
        XCTAssertEqual(count, 1)

        for row in try db.prepare("SELECT name FROM users") {
            XCTAssertEqual(row[0] as! String, "Alice")
        }
    }
}
