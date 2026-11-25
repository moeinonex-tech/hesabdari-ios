import XCTest
import Foundation
@testable import HesabCore
@testable import HesabStore

/// Stage 3 — the speed-ups must give exactly the same results / bytes as before.
extension SearchEngine {
    /// the search exactly as it was before stage 3 (copied unchanged), the reference for SearchIndex
    static func referenceFind(_ st: [String: JSONValue], query: String, scope: SearchScope, limit: Int = 300) -> [SearchResult] {
        let words = norm(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let number = digits(query)
        func s(_ v: JSONValue?) -> String { v?.stringValue ?? v?.idString ?? "" }
        func hit(_ fields: [String], amount: Int?) -> Bool {
            if let n = number, let a = amount, String(a).contains(n) { return true }
            let hay = norm(fields.joined(separator: " "))
            return words.allSatisfy { hay.contains($0) }
        }
        func items(_ e: JSONValue) -> [String] {
            (e["items"]?.arrayValue ?? []).flatMap { [s($0["desc"]), s($0["category"]), s($0["subcategory"])] }
        }
        func cat(_ e: JSONValue) -> String {
            [s(e["category"]), s(e["subcategory"])].filter { !$0.isEmpty }.joined(separator: " / ")
        }
        func dateText(_ d: JalaliDate) -> String { Money.persianDigits("\(d.jy)/\(d.jm)/\(d.jd)") }
        var out: [SearchResult] = []

        if scope.ledger {
            let accounts = (st["accounts"]?.arrayValue ?? []).filter { scope.accountId == nil || $0["id"]?.idString == scope.accountId }
            let tkParties = st["tankhahParties"]?.arrayValue ?? []
            for (ai, acc) in accounts.enumerated() {
                let aid = acc["id"]?.idString
                let name = s(acc["name"])
                for e in st["expenses"]?.arrayValue ?? [] where e["accountId"]?.idString == aid {
                    let tankhah = e["type"]?.stringValue == "tankhah"
                    let party = tkParties.first { $0["id"]?.idString == e["partyId"]?.idString && e["partyId"]?.idString != nil }.map { s($0["name"]) } ?? ""
                    let amount = ImportAnalyzer.toman(e)
                    guard hit([s(e["desc"]), s(e["category"]), s(e["subcategory"]), party, tankhah ? "تنخواه" : ""] + items(e), amount: amount) else { continue }
                    let d = ImportAnalyzer.date(e["date"])
                    let title = nonEmpty(e["desc"]) ?? (tankhah && !party.isEmpty ? "تنخواه از " + party : nil) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)"
                    let sub = [dateText(d), tankhah ? party : cat(e)].filter { !$0.isEmpty }.joined(separator: " · ")
                    out.append(SearchResult(kind: .expense, recordId: s(e["id"]), accountId: aid, tag: tankhah ? "تنخواه" : ((e["reward"]?.isTruthy ?? false) ? "پاداش" : "هزینه"),
                                            title: title, sub: sub, amount: amount, group: "دفتر «" + name + "»", groupOrder: 10 + ai,
                                            date: d, isTankhah: tankhah))
                }
            }
        }
        if scope.personal {
            for e in st["personalExpenses"]?.arrayValue ?? [] {
                let amount = ImportAnalyzer.toman(e)
                guard hit([s(e["desc"]), s(e["category"]), s(e["subcategory"])] + items(e), amount: amount) else { continue }
                let d = ImportAnalyzer.date(e["date"])
                out.append(SearchResult(kind: .personal, recordId: s(e["id"]), accountId: nil, tag: "شخصی",
                                        title: nonEmpty(e["desc"]) ?? nonEmpty(e["category"]) ?? "(بدون توضیح)",
                                        sub: [dateText(d), cat(e)].filter { !$0.isEmpty }.joined(separator: " · "), amount: amount,
                                        group: "هزینه‌های شخصی", groupOrder: 1000, date: d))
            }
        }
        if scope.income {
            for i in st["incomes"]?.arrayValue ?? [] {
                let amount = ImportAnalyzer.toman(i)
                guard hit([s(i["desc"]), s(i["category"]), s(i["subcategory"]), s(i["accountName"])], amount: amount) else { continue }
                let d = ImportAnalyzer.date(i["date"])
                out.append(SearchResult(kind: .income, recordId: s(i["id"]), accountId: nil, tag: "درآمد",
                                        title: nonEmpty(i["desc"]) ?? nonEmpty(i["category"]) ?? "(بدون توضیح)",
                                        sub: [dateText(d), cat(i)].filter { !$0.isEmpty }.joined(separator: " · "), amount: amount,
                                        group: "درآمدها", groupOrder: 1001, date: d))
            }
        }
        if scope.reminders {
            let status = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
            for c in st["reminderChecks"]?.arrayValue ?? [] {
                let amount = c["amount"]?.intValue ?? 0
                guard hit([s(c["party"]), s(c["checkNumber"]), s(c["sayadId"]), s(c["bankName"]), s(c["description"]),
                           s(c["category"]), s(c["subcategory"]), "چک"], amount: amount) else { continue }
                let d = ImportAnalyzer.date(c["dueDate"])
                let num = s(c["checkNumber"])
                out.append(SearchResult(kind: .check, recordId: s(c["id"]), accountId: nil, tag: "چک",
                                        title: (nonEmpty(c["party"]) ?? "چک بدون طرف") + (num.isEmpty ? "" : " · " + Money.persianDigits(num)),
                                        sub: ["سررسید " + dateText(d), s(c["bankName"]), status[s(c["status"])] ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                        amount: amount, group: "چک‌ها", groupOrder: 1002, date: d))
            }
            for p in st["reminderPersons"]?.arrayValue ?? [] {
                let insts = p["installments"]?.arrayValue ?? []
                let remaining = insts.filter { !($0["paid"]?.isTruthy ?? false) }.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) }
                guard hit([s(p["name"])] + insts.flatMap { [s($0["description"]), s($0["category"])] }, amount: remaining) else { continue }
                let creditor = p["type"]?.stringValue == "creditor"
                out.append(SearchResult(kind: .person, recordId: s(p["id"]), accountId: nil, tag: creditor ? "طلبکار" : "بدهکار",
                                        title: s(p["name"]), sub: Money.persianDigits(insts.count) + " قسط · مانده", amount: remaining,
                                        group: "بدهکاران و طلبکاران", groupOrder: 1003))
            }
            for a in st["appointments"]?.arrayValue ?? [] {
                guard hit([s(a["title"]), s(a["note"]), s(a["location"]?["label"]), "قرار"], amount: nil) else { continue }
                let d = ImportAnalyzer.date(a["date"])
                out.append(SearchResult(kind: .appointment, recordId: s(a["id"]), accountId: nil, tag: "قرار", title: s(a["title"]),
                                        sub: [dateText(d), s(a["time"])].filter { !$0.isEmpty }.joined(separator: " · "), amount: 0,
                                        group: "قرارها", groupOrder: 1004, date: d))
            }
        }
        return Array(out.enumerated().sorted { x, y in
            let a = x.element, b = y.element
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            if let da = a.date, let db = b.date, da != db { return da > db }
            return x.offset > y.offset
        }.map(\.element).prefix(limit))
    }
}

final class Stage3EquivalenceTests: XCTestCase {
    private lazy var big = SyntheticLedger.make(rows: 6_000)

    private func fixture() throws -> [String: JSONValue] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "rich_clean", withExtension: "json", subdirectory: "Goldens/import"))
        guard case .success(let p) = BackupParser.parse(try Data(contentsOf: url)) else { throw NSError(domain: "fixture", code: 1) }
        return ImportAnalyzer.analyze(p).cleanedState
    }

    func testSearchIndexGivesTheSameResultsAsBefore() throws {
        let queries = ["سیمان", "پمپ هوایی", "۱۲۰,۰۰۰", "120000", "تنخواه", "پاداش", "طرف حساب ۳", "بانک ملت", "چک", "ك", "zzzz", " ", "۵۰۰"]
        for st in [big, try fixture()] {
            let index = SearchIndex(st)
            for q in queries {
                XCTAssertEqual(index.find(query: q), SearchEngine.referenceFind(st, query: q, scope: .all), "index: " + q)
                for scope in [SearchScope.all, .ledgers(accountId: nil), .ledgers(accountId: "acc2"), .personal, .income, .reminders] {
                    XCTAssertEqual(SearchEngine.find(st, query: q, scope: scope), SearchEngine.referenceFind(st, query: q, scope: scope), "find: \(q) \(scope)")
                }
            }
        }
    }

    func testDatabaseRoundTripIsExact() throws {
        for st in [big, try fixture()] {
            let s = try HesabStore()
            try s.save(st)
            XCTAssertEqual(try s.loadState(), st, "parallel decoding reads back exactly what was saved")
        }
    }

    func testStoredRowTextIsUnchanged() throws {
        // the rows are written with one shared encoder now: the stored JSON text must be what JSONCoding.string gives
        let st = try fixture()
        let s = try HesabStore()
        try s.save(st)
        let stored = try s.storedRowTextsForTesting()
        var expected: [String] = []
        for key in st.keys.sorted() {
            if case .array(let items) = st[key]!, !items.isEmpty, items.allSatisfy({ $0.objectValue != nil }) {
                expected += try items.map { try JSONCoding.string($0) }
            }
        }
        XCTAssertEqual(stored.sorted(), expected.sorted())
    }

    func testSnapshotBackupBytesEqualTheDatabaseExport() throws {
        let now = Date(timeIntervalSince1970: 1_764_000_000)
        let today = JalaliDate(jy: 1405, jm: 9, jd: 4)
        for st in [big, try fixture()] {
            let s = try HesabStore()
            try s.save(st)
            let fromDatabase = try s.exportBackup(now: now, today: today)
            let fromSnapshot = try BackupExporter.encode(state: st, now: now, today: today)
            XCTAssertEqual(fromSnapshot, fromDatabase, "the background backup writes exactly the same bytes")
            // and exactly what the code before stage 3 produced
            let before = try JSONCoding.encode(BackupExporter.envelope(state: try s.loadState(), now: now, today: today), pretty: true)
            XCTAssertEqual(fromDatabase, before)
        }
    }
}

final class BackupDebouncerTests: XCTestCase {
    final class Marker: PendingBackupMarker { var isSet = false }

    private func st(_ n: Int) -> [String: JSONValue] { ["expenses": .array((0..<n).map { .object(["id": .string("e\($0)")]) })] }

    func testQuickChangesGiveOneBackupOfTheNewest() {
        let lock = NSLock()
        var written: [[String: JSONValue]] = []
        let marker = Marker()
        let d = BackupDebouncer(delay: 0.3, label: "t1", marker: marker) { s in lock.lock(); written.append(s); lock.unlock() }
        for i in 1...10 { d.schedule(st(i)); usleep(20_000) }
        XCTAssertTrue(marker.isSet, "a pending backup is remembered")
        usleep(700_000); d.waitUntilIdle()
        XCTAssertEqual(written.count, 1, "ten quick changes → one backup")
        XCTAssertEqual(written.first, st(10), "of the newest state")
        XCTAssertFalse(marker.isSet)
    }

    func testSnapshotIsNotChangedByLaterEdits() {
        var written: [String: JSONValue]?
        let d = BackupDebouncer(delay: 0.1, label: "t2", marker: Marker()) { written = $0 }
        var state = st(3)
        d.schedule(state)
        state["expenses"] = .array([])                      // the app goes on changing its own copy
        state["new"] = .string("x")
        usleep(400_000); d.waitUntilIdle()
        XCTAssertEqual(written, st(3))
    }

    func testFlushWritesAtOnceAndCancelDrops() {
        var count = 0
        let marker = Marker()
        let d = BackupDebouncer(delay: 30, label: "t3", marker: marker) { _ in count += 1 }
        d.schedule(st(1))
        d.flush()
        XCTAssertEqual(count, 1, "going to the background writes the pending backup now")
        XCTAssertFalse(marker.isSet)
        d.flush()
        XCTAssertEqual(count, 1, "nothing pending, nothing written")
        d.schedule(st(2)); d.cancel()
        usleep(100_000); d.waitUntilIdle()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(marker.isSet)
    }

    func testAPendingMarkSurvivesARestart() {
        let defaults = UserDefaults(suiteName: "stage3-\(UUID().uuidString)")!
        let m1 = UserDefaultsBackupMarker(key: "p", defaults: defaults)
        let d = BackupDebouncer(delay: 60, label: "t4", marker: m1) { _ in }
        d.schedule(st(1))                                   // the app is closed before the 60 s are up
        let m2 = UserDefaultsBackupMarker(key: "p", defaults: defaults)    // next launch
        XCTAssertTrue(m2.isSet, "the next launch sees the backup that was still pending")
        m2.isSet = false
        XCTAssertFalse(m1.isSet)
    }
}
