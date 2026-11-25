import XCTest
import Foundation
@testable import HesabCore
@testable import HesabStore

// Audit stage 1 (2026-11): one test class per critical fix.

/// #1 — a database that cannot be read is never replaced by an "empty" state.
final class SafeStoreReadOnlyTests: XCTestCase {
    private func sampleState() -> [String: JSONValue] {
        ["accounts": .array([.object(["id": .string("a"), "name": .string("پروژه")])]),
         "expenses": .array([
            .object(["id": .string("e1"), "accountId": .string("a"), "desc": .string("سیمان"), "toman": .int(1_000_000)]),
            .object(["id": .string("e2"), "accountId": .string("a"), "desc": .string("آهن"), "toman": .int(2_000_000)]),
         ]),
         "commissionPercent": .int(10)]
    }

    func testHealthyStoreLoadsAndSaves() throws {
        let base = try HesabStore()
        try base.save(sampleState())
        let s = SafeStore(base)
        let loaded = try XCTUnwrap(s.load())
        XCTAssertEqual(loaded["expenses"]?.arrayValue?.count, 2)
        XCTAssertFalse(s.isReadOnly)
        var next = loaded
        next["expenses"] = .array(Array(loaded["expenses"]!.arrayValue!.prefix(1)))
        XCTAssertNoThrow(try s.save(next))
        XCTAssertEqual(try base.recordCountForTesting(), 2)            // 1 account + 1 expense
    }

    func testUnreadableStoreBecomesReadOnlyAndKeepsItsData() throws {
        let base = try HesabStore()
        try base.save(sampleState())
        let before = try base.recordCountForTesting()
        try base.corruptOneRecordForTesting()

        let s = SafeStore(base)
        XCTAssertNil(s.load(), "a damaged record must not read as an empty state")
        XCTAssertTrue(s.isReadOnly)
        XCTAssertFalse(s.isEmpty, "the data is still there")

        // what the app would have done before the fix: save a state built on "nothing"
        XCTAssertThrowsError(try s.save(["expenses": .array([])])) { e in
            guard case SafeStoreError.readOnly = e else { return XCTFail("wrong error: \(e)") }
        }
        XCTAssertThrowsError(try s.exportBackup(today: JalaliDate(jy: 1405, jm: 9, jd: 4)))
        XCTAssertEqual(try base.recordCountForTesting(), before, "nothing was overwritten")

        // the raw database can still be copied aside before a restore
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("safe-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try s.copyDatabase(to: url)
        XCTAssertEqual(try HesabStore(path: url.path).recordCountForTesting(), before)

        // recovery on purpose (restore a backup) is allowed, and a good read lifts the lock
        try s.replaceAll(with: sampleState(), sourceExportedAtJalali: nil, reportLines: [])
        XCTAssertNotNil(s.load())
        XCTAssertFalse(s.isReadOnly)
        XCTAssertNoThrow(try s.save(sampleState()))
    }
}

/// #2 — undo never removes a change made after the one it undoes.
final class UndoTrackerTests: XCTestCase {
    func testUndoRightAfterTheChange() {
        var u = UndoTracker<String>()
        u.didChange(previous: "A", message: "حذف شد")               // A → B (delete)
        XCTAssertEqual(u.offer?.message, "حذف شد")
        XCTAssertEqual(u.takeUndo(), "A")
        XCTAssertNil(u.offer)
        XCTAssertNil(u.takeUndo(), "an undo is used once")
    }

    func testANewerChangeBlocksTheOlderUndo() {
        var u = UndoTracker<String>()
        let offer = u.didChange(previous: "A", message: "حذف شد")   // A → B (delete, undo offered)
        XCTAssertNotNil(offer)
        u.didChange(previous: "B", message: nil)                     // B → C (a new row, no undo of its own)
        XCTAssertNil(u.offer, "the old undo bar is gone")
        XCTAssertNil(u.takeUndo(), "putting back A would erase the new row")
    }

    func testANewerUndoableChangeReplacesTheOffer() {
        var u = UndoTracker<String>()
        u.didChange(previous: "A", message: "حذف شد")
        u.didChange(previous: "B", message: "حذف شد")
        XCTAssertEqual(u.takeUndo(), "B", "only the latest change can be undone")
    }

    func testExpiryAndReload() {
        var u = UndoTracker<String>()
        let first = u.didChange(previous: "A", message: "حذف شد")!
        let second = u.didChange(previous: "B", message: "حذف شد")!
        u.expire(first.id)                                           // the old timer must not remove the new offer
        XCTAssertEqual(u.offer?.id, second.id)
        u.expire(second.id)
        XCTAssertNil(u.takeUndo())
        u.didChange(previous: "C", message: "حذف شد")
        u.invalidate()                                               // import / reload
        XCTAssertNil(u.takeUndo())
    }
}

/// #3 — iCloud backup copies land in order; an older copy is never written after a newer one.
final class LatestWinsQueueTests: XCTestCase {
    func testOnlyNewestCopyLandsAndInOrder() {
        let q = LatestWinsQueue(label: "test.backup")
        let lock = NSLock()
        var written: [Int] = []
        var fileContent = -1
        let gate = DispatchSemaphore(value: 0)
        // the first job is slow (as a slow iCloud write would be); all others are queued behind it
        q.submit(key: "today.json") {
            gate.wait()
            lock.lock(); written.append(0); fileContent = 0; lock.unlock()
        }
        for i in 1...50 {
            q.submit(key: "today.json") {
                lock.lock(); written.append(i); fileContent = i; lock.unlock()
            }
        }
        gate.signal()
        q.waitUntilIdle()
        XCTAssertEqual(fileContent, 50, "the file ends with the newest data")
        XCTAssertEqual(written, written.sorted(), "writes happen in the order they were asked for")
        XCTAssertEqual(written.last, 50)
        XCTAssertLessThan(written.count, 51, "copies overtaken before they started are skipped")
    }

    func testDifferentFilesAllLand() {
        let q = LatestWinsQueue(label: "test.backup2")
        let lock = NSLock()
        var names: [String] = []
        for n in ["day1.json", "before-restore.json", "day2.json"] {
            q.submit(key: n) { lock.lock(); names.append(n); lock.unlock() }
        }
        q.waitUntilIdle()
        XCTAssertEqual(names, ["day1.json", "before-restore.json", "day2.json"])
    }

    func testRealFilesNeverGoBackToOlderData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lwq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("backup.json")
        let q = LatestWinsQueue(label: "test.backup3")
        for i in 0..<200 {
            let data = Data("{\"version\":\(i)}".utf8)
            q.submit(key: "backup.json") { try? data.write(to: url, options: .atomic) }
        }
        q.waitUntilIdle()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{\"version\":199}")
    }
}
