import XCTest
import Foundation
@testable import HesabCore
@testable import HesabStore

// Backup retention (owner-approved 2026-11-25): names, Jalali edge cases, safety rules, a 400-day simulation,
// the SHA-256 sidecar, soft delete / trash, and the health check with a real restore test.
// Every test works in its own temporary folder; no real backup is touched.

private func J(_ y: Int, _ m: Int, _ d: Int) -> JalaliDate { JalaliDate(jy: y, jm: m, jd: d) }
private func addDays(_ d: JalaliDate, _ n: Int) -> JalaliDate { Jalali.d2j(Jalali.j2d(d.jy, d.jm, d.jd) + n) }

final class BackupNameTests: XCTestCase {
    func testFormatsAndParsesBothDigitStyles() {
        XCTAssertEqual(BackupNames.endOfDay(J(1405, 9, 4)), "پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.json")
        XCTAssertEqual(BackupNames.parse("پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.json")?.kind, .endOfDay)
        XCTAssertEqual(BackupNames.parse("پشتیبان-کامل-اپ - 1405-9-4.json")?.date, J(1405, 9, 4))
        XCTAssertEqual(BackupNames.parse(BackupNames.startOfDay(J(1405, 9, 4)))?.kind, .startOfDay)
        let r = BackupNames.parse(BackupNames.beforeRestore(J(1405, 9, 4), hhmmss: 143005))
        XCTAssertEqual(r?.kind, .beforeRestore); XCTAssertEqual(r?.time, 143005)
        XCTAssertEqual(BackupNames.parse(BackupNames.beforeRestore(J(1405, 9, 4), hhmmss: 90000, ext: "sqlite"))?.kind, .rawDatabase)
    }

    func testOtherFilesAreNeverBackups() {
        for n in ["پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴ (کپی).json", "پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.json.sha256", "خروجی دستی.json",
                  "backup.json", ".پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.json.icloud", "پشتیبان-کامل-اپ - ۱۴۰۵-۹-۴.JSON",
                  "قبل-از-بازگردانی - ۱۴۰۵-۹-۴.json"] {
            XCTAssertNil(BackupNames.parse(n), n)
        }
    }

    func testInvalidJalaliDatesAreRejected() {
        XCTAssertNotNil(BackupNames.parse("پشتیبان-کامل-اپ - 1403-12-30.json"), "1403 is a leap year: Esfand 30 exists")
        XCTAssertNil(BackupNames.parse("پشتیبان-کامل-اپ - 1404-12-30.json"), "1404 is not leap: Esfand has 29 days")
        XCTAssertNotNil(BackupNames.parse("پشتیبان-کامل-اپ - 1404-6-31.json"), "the first six months have 31 days")
        XCTAssertNil(BackupNames.parse("پشتیبان-کامل-اپ - 1404-7-31.json"), "months 7–11 have 30 days")
        XCTAssertNil(BackupNames.parse("پشتیبان-کامل-اپ - 1404-13-1.json"))
        XCTAssertNil(BackupNames.parse("پشتیبان-کامل-اپ - 1404-0-1.json"))
    }
}

final class BackupRetentionPlanTests: XCTestCase {
    private let all: (String) -> Bool = { _ in true }

    private func ends(from start: JalaliDate, days: Int) -> [String] {
        (0..<days).map { BackupNames.endOfDay(addDays(start, $0)) }
    }

    func testJalaliDayArithmeticAcrossYearEnds() {
        XCTAssertEqual(BackupRetention.dayNumber(J(1404, 1, 1)) - BackupRetention.dayNumber(J(1403, 12, 30)), 1, "leap Esfand → Nowruz")
        XCTAssertEqual(BackupRetention.dayNumber(J(1405, 1, 1)) - BackupRetention.dayNumber(J(1404, 12, 29)), 1, "29-day Esfand → Nowruz")
        XCTAssertEqual(BackupRetention.dayNumber(J(1404, 8, 1)) - BackupRetention.dayNumber(J(1404, 7, 30)), 1, "30-day month")
        XCTAssertEqual(BackupRetention.dayNumber(J(1404, 7, 1)) - BackupRetention.dayNumber(J(1404, 6, 31)), 1, "31-day month")
        // a week runs Saturday–Friday; Nowruz 1404 (21 March 2025) was a Friday
        XCTAssertEqual(BackupRetention.weekStart(J(1404, 1, 1)), BackupRetention.weekStart(J(1403, 12, 25)))
        XCTAssertEqual(BackupRetention.weekStart(J(1404, 1, 2)), BackupRetention.dayNumber(J(1404, 1, 2)), "Saturday starts a week")
    }

    func testNowruzAndYearEndKeepTheRightFiles() {
        // 40 days of end-of-day backups crossing Nowruz 1404, today = 1404-1-10
        let today = J(1404, 1, 10)
        let names = ends(from: addDays(today, -39), days: 40)
        let plan = BackupRetention.plan(names: names, today: today, policy: .local, isHealthy: all)
        XCTAssertNil(plan.skipped)
        let kept = Set(names).subtracting(plan.remove)
        for k in 0..<14 { XCTAssertTrue(kept.contains(BackupNames.endOfDay(addDays(today, -k))), "day -\(k) kept") }
        // the last day of the old year is the monthly copy of Esfand 1403 (a 30-day month: it was leap)
        XCTAssertTrue(kept.contains(BackupNames.endOfDay(J(1403, 12, 30))), "Esfand 30 (monthly)")
        XCTAssertFalse(plan.remove.isEmpty)
        XCTAssertLessThanOrEqual(plan.remove.count, 5)
    }

    func testMonthEndsOf29And30Days() {
        // non-leap year end: Esfand 1404 has 29 days → its monthly copy is Esfand 29
        let today = J(1405, 2, 20)
        let names = ends(from: J(1404, 12, 1), days: 70)          // 1404-12-1 … 1405-2-10
        let plan = BackupRetention.plan(names: names, today: today, policy: BackupRetentionPolicy(endOfDayDays: 14, weeks: 0, months: 12,
                                        startOfDayDays: 14, beforeRestoreKeep: 10, maxRemovalsPerRun: 100), isHealthy: all)
        let kept = Set(names).subtracting(plan.remove)
        XCTAssertTrue(kept.contains(BackupNames.endOfDay(J(1404, 12, 29))))
        XCTAssertFalse(kept.contains(BackupNames.endOfDay(J(1404, 12, 28))))
        // Farvardin (31 days) keeps its last day
        XCTAssertTrue(kept.contains(BackupNames.endOfDay(J(1405, 1, 31))))
        XCTAssertFalse(kept.contains(BackupNames.endOfDay(J(1405, 1, 30))))
    }

    func testWrongClockStopsEverything() {
        let today = J(1405, 9, 4)
        var names = ends(from: addDays(today, -60), days: 60)
        names.append(BackupNames.endOfDay(addDays(today, 3)))         // a file "from the future"
        let plan = BackupRetention.plan(names: names, today: today, policy: .local, isHealthy: all)
        XCTAssertEqual(plan.remove, [])
        XCTAssertNotNil(plan.skipped)
    }

    func testNothingRemovedWhenTheNewestBackupIsNotHealthy() {
        let today = J(1405, 9, 4)
        let names = ends(from: addDays(today, -60), days: 61)
        let newest = BackupNames.endOfDay(today)
        let plan = BackupRetention.plan(names: names, today: today, policy: .local, isHealthy: { $0 != newest })
        XCTAssertEqual(plan.remove, [])
        XCTAssertEqual(plan.skipped, "newest backup is not healthy")
    }

    func testOthersRawAndBeforeRestoreAreProtected() {
        let today = J(1405, 9, 4)
        var names = ends(from: addDays(today, -400), days: 401)
        let others = ["خروجی دستی.json", "backup-web.json", "یادداشت.txt"]
        let raws = (0..<4).map { BackupNames.beforeRestore(addDays(today, -300 + $0), hhmmss: 100000, ext: "sqlite") }
        let restores = (0..<15).map { BackupNames.beforeRestore(addDays(today, -200 + $0 * 10), hhmmss: 120000 + $0) }
        names += others + raws + restores
        var removed = Set<String>()
        for _ in 0..<200 {                                            // run until nothing more goes
            let plan = BackupRetention.plan(names: names.filter { !removed.contains($0) }, today: today, policy: .local, isHealthy: all)
            if plan.remove.isEmpty { break }
            removed.formUnion(plan.remove)
        }
        for n in others + raws { XCTAssertFalse(removed.contains(n), n) }
        let keptRestores = restores.filter { !removed.contains($0) }
        XCTAssertEqual(keptRestores.count, 10, "a pool of 10 before-restore copies")
        XCTAssertEqual(Set(keptRestores), Set(restores.suffix(10)), "the newest 10")
    }

    func testUnhealthyFilesAreNeverRemovedAndWeeksKeepAHealthyOne() {
        let today = J(1405, 9, 4)
        let names = ends(from: addDays(today, -40), days: 41)
        let old = names.filter { BackupRetention.dayNumber(BackupNames.parse($0)!.date) < BackupRetention.dayNumber(addDays(today, -13)) }
        let bad = Set(old.prefix(3))
        var removed = Set<String>()
        for _ in 0..<50 {
            let plan = BackupRetention.plan(names: names.filter { !removed.contains($0) }, today: today, policy: .local,
                                            isHealthy: { !bad.contains($0) })
            if plan.remove.isEmpty { break }
            removed.formUnion(plan.remove)
        }
        XCTAssertTrue(bad.isDisjoint(with: removed), "a file that cannot be verified is never removed")
        // every one of the last 8 weeks still has a healthy copy
        let kept = names.filter { !removed.contains($0) }.compactMap(BackupNames.parse)
        let thisWeek = BackupRetention.weekStart(today)
        let original = names.compactMap(BackupNames.parse)
        for k in 0..<8 {
            let ws = thisWeek - 7 * k
            let had = original.filter { BackupRetention.weekStart($0.date) == ws }
            guard had.contains(where: { !bad.contains($0.fileName) }) else { continue }
            let inWeek = kept.filter { BackupRetention.weekStart($0.date) == ws }
            XCTAssertTrue(inWeek.contains { !bad.contains($0.fileName) }, "week -\(k)")
        }
    }

    func testAtMostFiveRemovalsPerRunOldestFirst() {
        let today = J(1405, 9, 4)
        let names = ends(from: addDays(today, -40), days: 41)
        let noLayers = BackupRetentionPolicy(endOfDayDays: 14, weeks: 0, months: 0, startOfDayDays: 14,
                                             beforeRestoreKeep: 10, maxRemovalsPerRun: 5)
        let plan = BackupRetention.plan(names: names, today: today, policy: noLayers, isHealthy: all)
        XCTAssertEqual(plan.remove.count, 5)
        let dates = plan.remove.compactMap { BackupNames.parse($0)?.date }
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(dates.first, addDays(today, -40))
    }

    func testFourHundredDaySimulation() {
        for (policy, recent) in [(BackupRetentionPolicy.local, 14), (.iCloud, 60)] {
            var files = Set<String>()
            var day = J(1404, 6, 1)
            for _ in 0..<400 {
                files.insert(BackupNames.endOfDay(day))
                files.insert(BackupNames.startOfDay(day))
                let plan = BackupRetention.plan(names: Array(files), today: day, policy: policy, isHealthy: { _ in true })
                XCTAssertNil(plan.skipped)
                files.subtract(plan.remove)
                XCTAssertTrue(files.contains(BackupNames.endOfDay(day)), "today is never removed")
                XCTAssertTrue(files.contains(BackupNames.endOfDay(addDays(day, -1))) || day == J(1404, 6, 1), "yesterday is never removed")
                day = addDays(day, 1)
            }
            let today = addDays(day, -1)
            let ends = files.compactMap(BackupNames.parse).filter { $0.kind == .endOfDay }
            for k in 0..<recent { XCTAssertTrue(files.contains(BackupNames.endOfDay(addDays(today, -k))), "recent day -\(k)") }
            let thisWeek = BackupRetention.weekStart(today)
            for k in 0..<8 { XCTAssertTrue(ends.contains { BackupRetention.weekStart($0.date) == thisWeek - 7 * k }, "week -\(k)") }
            var (y, m) = (today.jy, today.jm)
            for k in 0..<12 {
                XCTAssertTrue(ends.contains { $0.date.jy == y && $0.date.jm == m }, "month -\(k)")
                m -= 1; if m == 0 { m = 12; y -= 1 }
            }
            XCTAssertLessThanOrEqual(ends.count, recent + 8 + 12)
            XCTAssertEqual(files.compactMap(BackupNames.parse).filter { $0.kind == .startOfDay }.count, 14)
        }
    }
}

final class BackupFolderTests: XCTestCase {
    private var dir: URL!
    private var folder: BackupFolder { BackupFolder(url: dir) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testSidecarAfterTheBackupAndHealth() throws {
        let data = Data("{\"state\":{}}".utf8)
        let name = BackupNames.endOfDay(J(1405, 9, 4))
        let url = try folder.write(data, name: name)
        XCTAssertEqual(try Data(contentsOf: url), data, "the backup's bytes are exactly what was given (format unchanged)")
        XCTAssertEqual(folder.health(name), .healthy)
        // cut short after the sidecar was written
        try data.prefix(5).write(to: url)
        XCTAssertEqual(folder.health(name), .mismatch)
        // sidecar missing
        _ = try folder.write(data, name: name)
        try FileManager.default.removeItem(at: dir.appendingPathComponent(BackupFolder.sidecarName(name)))
        XCTAssertEqual(folder.health(name), .noSidecar)
        XCTAssertFalse(folder.isHealthy(name))
    }

    func testNoSidecarWhenTheBackupCouldNotBeWritten() throws {
        let name = BackupNames.endOfDay(J(1405, 9, 4))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)   // blocks the write
        XCTAssertThrowsError(try folder.write(Data("x".utf8), name: name))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(BackupFolder.sidecarName(name)).path))
    }

    func testSoftDeleteAndThirtyDayTrash() throws {
        let today = J(1405, 9, 4)
        for k in 0..<20 { try folder.write(Data("\(k)".utf8), name: BackupNames.endOfDay(addDays(today, -k - 40))) }
        try folder.write(Data("new".utf8), name: BackupNames.endOfDay(today))
        try Data("mine".utf8).write(to: dir.appendingPathComponent("خروجی دستی.json"))
        let r = folder.applyRetention(today: today, policy: .local)
        XCTAssertEqual(r.moved.count, 5)
        for n in r.moved {
            XCTAssertFalse(folder.exists(n)); XCTAssertFalse(folder.exists(BackupFolder.sidecarName(n)))
        }
        let trash = try FileManager.default.contentsOfDirectory(atPath: folder.trashURL.path)
        XCTAssertEqual(trash.count, 10, "each moved backup with its sidecar")
        XCTAssertTrue(trash.allSatisfy { $0.hasPrefix("حذف ۱۴۰۵-۹-۴ - ") })
        XCTAssertTrue(folder.exists("خروجی دستی.json"))
        // a file the person put in the trash themselves is never touched; nothing is purged before 30 days
        try Data("x".utf8).write(to: folder.trashURL.appendingPathComponent("یادداشت.txt"))
        XCTAssertEqual(folder.purgeTrash(today: addDays(today, 29)), [])
        XCTAssertEqual(folder.purgeTrash(today: addDays(today, 30)).count, 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.trashURL.path), ["یادداشت.txt"])
    }

    func testTrashWithAWrongClockIsNotPurged() throws {
        try folder.write(Data("a".utf8), name: BackupNames.endOfDay(J(1405, 1, 1)))
        try folder.moveToTrash(BackupNames.endOfDay(J(1405, 1, 1)), today: J(1405, 9, 4))
        XCTAssertEqual(folder.purgeTrash(today: J(1405, 9, 1)), [], "an entry dated after today: clock is wrong")
        XCTAssertEqual(folder.purgeTrash(today: J(1405, 10, 10)).count, 2)
    }

    func testRetentionTwiceIsIdempotent() throws {
        let today = J(1405, 9, 4)
        for k in 0..<17 { try folder.write(Data("\(k)".utf8), name: BackupNames.endOfDay(addDays(today, -k))) }
        let first = folder.applyRetention(today: today, policy: BackupRetentionPolicy(endOfDayDays: 14, weeks: 0, months: 0,
                                          startOfDayDays: 14, beforeRestoreKeep: 10, maxRemovalsPerRun: 5))
        XCTAssertEqual(first.moved.count, 3)
        let second = folder.applyRetention(today: today, policy: BackupRetentionPolicy(endOfDayDays: 14, weeks: 0, months: 0,
                                           startOfDayDays: 14, beforeRestoreKeep: 10, maxRemovalsPerRun: 5))
        XCTAssertEqual(second.moved, [])
    }
}

final class BackupCheckTests: XCTestCase {
    private var dir: URL!
    private var folder: BackupFolder { BackupFolder(url: dir) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("bc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// the synthetic import fixture (no real data): a full, importable state
    private func storeWithData() throws -> HesabStore {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich_clean", withExtension: "json", subdirectory: "Goldens/import"))
        guard case .success(let parsed) = BackupParser.parse(try Data(contentsOf: url)) else { throw NSError(domain: "fixture", code: 1) }
        let s = try HesabStore()
        try s.save(ImportAnalyzer.analyze(parsed).cleanedState)
        return s
    }

    private func records(_ s: HesabStore) throws -> Int {
        try s.loadState().values.reduce(0) { $0 + ($1.arrayValue?.count ?? 0) }
    }

    func testRealRestoreTestOfAGoodBackup() throws {
        let store = try storeWithData()
        let data = try store.exportBackup(today: J(1405, 9, 4))
        let name = BackupNames.endOfDay(J(1405, 9, 4))
        try folder.write(data, name: name)
        let r = BackupCheck.run(folder, name)
        XCTAssertEqual(r.health, .healthy)
        XCTAssertTrue(r.structureOK, r.problem ?? ""); XCTAssertTrue(r.restoreOK, r.problem ?? ""); XCTAssertTrue(r.usable)
        XCTAssertEqual(r.records, try records(store))
        // the file is still a web-format backup: the import parser reads it unchanged
        guard case .success = BackupParser.parse(try Data(contentsOf: dir.appendingPathComponent(name))) else { return XCTFail() }
    }

    func testDamagedAndOlderBackups() throws {
        let data = try storeWithData().exportBackup(today: J(1405, 9, 4))
        let name = BackupNames.endOfDay(J(1405, 9, 4))
        let url = try folder.write(data, name: name)
        var bytes = [UInt8](data); bytes[bytes.count / 2] ^= 0x20       // one changed byte
        try Data(bytes).write(to: url)
        XCTAssertFalse(BackupCheck.run(folder, name).usable, "a checksum mismatch is never usable")
        // an older backup without a sidecar: checked by structure and restore test
        let old = BackupNames.endOfDay(J(1405, 8, 1))
        try data.write(to: dir.appendingPathComponent(old))
        let r = BackupCheck.run(folder, old)
        XCTAssertEqual(r.health, .noSidecar); XCTAssertTrue(r.usable, r.problem ?? "")
        // not a backup at all
        try Data("not json".utf8).write(to: dir.appendingPathComponent("x.json"))
        XCTAssertFalse(BackupCheck.run(folder, "x.json").usable)
    }

    func testRawDatabaseCopyIsCheckedWithoutBeingOpened() throws {
        let base = try storeWithData()
        let name = BackupNames.beforeRestore(J(1405, 9, 4), hhmmss: 101010, ext: "sqlite")
        try SafeStore(base).copyDatabase(to: dir.appendingPathComponent(name))
        try folder.writeSidecar(for: name)
        let before = try Data(contentsOf: dir.appendingPathComponent(name))
        let r = BackupCheck.run(folder, name)
        XCTAssertTrue(r.usable, r.problem ?? ""); XCTAssertEqual(r.records, try records(base))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(name)), before, "the raw copy itself is untouched")
    }
}
