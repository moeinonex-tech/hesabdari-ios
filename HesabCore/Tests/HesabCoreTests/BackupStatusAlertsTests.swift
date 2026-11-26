import XCTest
@testable import HesabCore

/// «نیازمند توجه»: backup warnings only when something is really wrong.
final class BackupStatusAlertsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
    func ids(_ a: [BackupStatusAlerts.Alert]) -> [String] { a.map(\.id) }

    func testFreshHealthyBackupGivesNoWarning() {
        for h in [0.0, 0.01, 5, 23, 47.9] {
            XCTAssertEqual(BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: h), now: now,
                                                       latestHealth: .healthy, iCloud: .ok), [], "\(h) h")
        }
        // iCloud never tried / build without iCloud: no warning either
        XCTAssertEqual(BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 1), now: now,
                                                   latestHealth: .healthy, iCloud: .unknown), [])
    }

    func testNoDataNoWarning() {
        XCTAssertEqual(BackupStatusAlerts.evaluate(hasData: false, lastBackupAt: nil, now: now,
                                                   latestHealth: nil, iCloud: .failed), [])
    }

    func testOldBackup() {
        let two = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 48), now: now, latestHealth: .healthy, iCloud: .ok)
        XCTAssertEqual(ids(two), ["stale"])
        XCTAssertEqual(two[0].level, .warning)
        XCTAssertEqual(two[0].text, "۲ روز است پشتیبان تازه‌ای گرفته نشده")
        let week = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 24 * 7), now: now, latestHealth: .healthy, iCloud: .ok)
        XCTAssertEqual(week[0].level, .danger)
        XCTAssertEqual(week[0].text, "۷ روز است پشتیبان تازه‌ای گرفته نشده")
    }

    func testNeverBackedUp() {
        let a = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: nil, now: now, latestHealth: nil, iCloud: .unknown)
        XCTAssertEqual(ids(a), ["never"])
        XCTAssertEqual(a[0].level, .danger)
    }

    func testUnhealthyOrMissingNewestBackup() {
        for h in [BackupFolder.Health.mismatch, .unreadable, .noSidecar] {
            let a = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 1), now: now, latestHealth: h, iCloud: .ok)
            XCTAssertEqual(ids(a), ["unhealthy"], "\(h)")
            XCTAssertEqual(a[0].level, .danger)
        }
        let missing = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 1), now: now, latestHealth: nil, iCloud: .ok)
        XCTAssertEqual(ids(missing), ["missing"])
    }

    func testICloud() {
        func one(_ c: BackupStatusAlerts.ICloud) -> [BackupStatusAlerts.Alert] {
            BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 1), now: now, latestHealth: .healthy, iCloud: c)
        }
        XCTAssertEqual(ids(one(.notSignedIn)), ["icloud-off"])
        XCTAssertEqual(ids(one(.notReady)), ["icloud-not-ready"])
        XCTAssertEqual(ids(one(.failed)), ["icloud-failed"])
        XCTAssertEqual(one(.failed)[0].level, .danger)
        XCTAssertEqual(one(.notSignedIn)[0].level, .warning)
    }

    func testSeveralProblemsTogether() {
        let a = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 24 * 3), now: now, latestHealth: .mismatch, iCloud: .failed)
        XCTAssertEqual(ids(a), ["stale", "unhealthy", "icloud-failed"])
    }

    func testNewestEndOfDayPicksTheLatestDailyFile() {
        let names = [
            BackupNames.endOfDay(JalaliDate(jy: 1405, jm: 9, jd: 3)),
            BackupNames.endOfDay(JalaliDate(jy: 1405, jm: 9, jd: 5)),
            BackupNames.startOfDay(JalaliDate(jy: 1405, jm: 9, jd: 6)),        // not an end-of-day file
            BackupNames.endOfDay(JalaliDate(jy: 1404, jm: 12, jd: 29)),
            "یادداشت.txt",
        ]
        XCTAssertEqual(BackupStatusAlerts.newestEndOfDay(names), BackupNames.endOfDay(JalaliDate(jy: 1405, jm: 9, jd: 5)))
        XCTAssertNil(BackupStatusAlerts.newestEndOfDay(["x.json"]))
    }

    /// the real files: a backup written with its sidecar is healthy; cut short it is not
    func testHealthOfARealNewestFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = BackupFolder(url: dir)
        let name = BackupNames.endOfDay(JalaliDate(jy: 1405, jm: 9, jd: 5))
        try folder.write(Data("{\"a\":1}".utf8), name: name)
        let newest = try XCTUnwrap(BackupStatusAlerts.newestEndOfDay(folder.names()))
        XCTAssertEqual(folder.health(newest), .healthy)
        try Data("{\"a\"".utf8).write(to: dir.appendingPathComponent(name))
        let a = BackupStatusAlerts.evaluate(hasData: true, lastBackupAt: ago(hours: 1), now: now,
                                            latestHealth: folder.health(newest), iCloud: .ok)
        XCTAssertEqual(ids(a), ["unhealthy"])
    }
}
