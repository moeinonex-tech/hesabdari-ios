import XCTest
import Foundation
@testable import HesabCore

// MARK: - audit stage 2

/// Shared files are cleaned up; nothing outside the exports folder (database, backups) can ever be removed by it.
final class TempExportsTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL { sandbox.appendingPathComponent("exports") }

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    func testWriteAndRemoveOneExport() throws {
        let a = try TempExports.write(Data("pdf".utf8), name: "دفتر حساب - کوچه وصال.pdf", root: root)
        let b = try TempExports.write(Data("pdf2".utf8), name: "دفتر حساب - کوچه وصال.pdf", root: root)   // same name
        XCTAssertNotEqual(a, b, "two exports with the same name never overwrite each other")
        XCTAssertEqual(a.lastPathComponent, "دفتر حساب - کوچه وصال.pdf", "the shared file keeps its name")
        XCTAssertTrue(TempExports.remove(a, root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.deletingLastPathComponent().path), "its folder is gone too")
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path), "the other export is untouched")
        XCTAssertEqual(TempExports.pending(root: root).map(\.lastPathComponent), ["دفتر حساب - کوچه وصال.pdf"])
    }

    func testNeverRemovesAnythingElse() throws {
        // a backup next to the exports, a file directly in the root, and the root itself
        let backups = sandbox.appendingPathComponent("Documents/پشتیبان‌ها")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let backup = backups.appendingPathComponent("پشتیبان - ۱۴۰۵-۹-۴.json")
        try Data("{}".utf8).write(to: backup)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let loose = root.appendingPathComponent("loose.json")
        try Data("{}".utf8).write(to: loose)

        XCTAssertFalse(TempExports.remove(backup, root: root))
        XCTAssertFalse(TempExports.remove(loose, root: root))
        XCTAssertFalse(TempExports.remove(root, root: root))
        XCTAssertFalse(TempExports.remove(root.appendingPathComponent("x/../../Documents/پشتیبان‌ها/پشتیبان - ۱۴۰۵-۹-۴.json"), root: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "the backup is never touched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: loose.path))
    }

    func testPurgeAllOnlyTouchesTheExportsFolder() throws {
        let backup = sandbox.appendingPathComponent("پشتیبان.json")
        try Data("{}".utf8).write(to: backup)
        for i in 0..<3 { _ = try TempExports.write(Data("\(i)".utf8), name: "f\(i).xlsx", root: root) }
        XCTAssertEqual(TempExports.pending(root: root).count, 3)
        TempExports.purgeAll(root: root)
        XCTAssertEqual(TempExports.pending(root: root).count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "files outside the exports folder stay")
    }
}
