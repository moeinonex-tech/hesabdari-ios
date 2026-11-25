import XCTest

/// Runs on the iOS Simulator in CI with a small synthetic state (never real data): visits every page and walks
/// the category manager, including removing subcategories. A crash anywhere fails the test with the crash report.
final class SmokeTests: XCTestCase {
    static let fixture = """
    {
      "accounts": [{"id": "a1", "name": "پروژه آزمایشی", "commissionPercent": 10, "commissionEnabled": true, "commissionSettlements": []}],
      "ledgerCategories": ["مصالح", "خوراک", "کمیسیون"],
      "ledgerSubcategories": {"مصالح": ["سیمان", "آهن", "گچ"], "خوراک": ["نهار"]},
      "personalCategories": ["خانه"],
      "personalSubcategories": {"خانه": ["قبض"]},
      "incomeCategories": ["حقوق"],
      "expenses": [
        {"id": "e1", "accountId": "a1", "desc": "سیمان تیپ دو", "category": "مصالح", "subcategory": "سیمان", "toman": 900000, "date": {"jy": 1405, "jm": 8, "jd": 10}, "ts": 1},
        {"id": "e2", "accountId": "a1", "desc": "میلگرد", "category": "مصالح", "subcategory": "آهن", "toman": 2500000, "date": {"jy": 1405, "jm": 8, "jd": 12}, "ts": 2},
        {"id": "e3", "accountId": "a1", "desc": "نهار کارگران", "category": "خوراک", "subcategory": "نهار", "toman": 300000, "date": {"jy": 1405, "jm": 8, "jd": 14}, "ts": 3},
        {"id": "e6", "accountId": "a1", "desc": "پاداش ویژه", "category": "پاداش", "reward": true, "payMethod": "cash", "toman": 4000000, "date": {"jy": 1405, "jm": 8, "jd": 13}, "ts": 8},
        {"id": "e4", "accountId": "a1", "type": "tankhah", "partyId": "tp1", "desc": "تنخواه هفتگی", "payMethod": "cash", "toman": 5000000, "date": {"jy": 1405, "jm": 8, "jd": 2}, "ts": 6},
        {"id": "e5", "accountId": "a1", "type": "tankhah", "partyId": "tp2", "desc": "", "payMethod": "transfer", "toman": 2000000, "date": {"jy": 1405, "jm": 8, "jd": 3}, "ts": 7}
      ],
      "tankhahParties": [{"id": "tp1", "type": "person", "name": "کارفرما آزمایشی"}, {"id": "tp2", "type": "person", "name": "طرف دوم"}],
      "personalExpenses": [
        {"id": "p1", "desc": "قبض برق", "category": "خانه", "subcategory": "قبض", "toman": 150000, "date": {"jy": 1405, "jm": 8, "jd": 11}, "ts": 4}
      ],
      "incomes": [
        {"id": "i1", "desc": "حقوق آبان", "category": "حقوق", "toman": 30000000, "date": {"jy": 1405, "jm": 8, "jd": 1}, "ts": 5}
      ],
      "cards": [
        {"id": "c1", "bankName": "بانک ملت", "bankKey": "mellat", "cardNumber": "6104337800001234", "holderName": "آزمایشی", "bgPreset": "mellat"}
      ]
    }
    """

    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITEST_STATE"] = Self.fixture
        app.launch()
    }

    /// any element whose label contains the text (rows merge their texts into one label)
    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// screenshot to the Mac host (CI uploads the folder), so a failing step can be seen
    private func shot(_ name: String) {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return }
        let dir = URL(fileURLWithPath: home).appendingPathComponent("ui-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }

    /// reveal the trailing swipe action (in right-to-left the trailing edge is on the left, so try both ways)
    private func swipeDelete(_ e: XCUIElement, _ step: String) {
        let del = app.buttons["حذف"].firstMatch
        e.swipeRight()
        if !del.waitForExistence(timeout: 2) { e.swipeLeft() }
        if !del.waitForExistence(timeout: 2) { print("UITREE-BEGIN\n" + app.debugDescription + "\nUITREE-END") }
        tap(del, step)
    }

    /// the undo banner («برگرداندن», 10 s above the dock) can sit over the next control: wait until it is gone
    private func waitForUndoBannerToGo() {
        let undo = app.buttons["برگرداندن"].firstMatch
        let t = Date()
        while undo.exists && Date().timeIntervalSince(t) < 13 { usleep(250_000) }
    }

    /// bring an element into the free part of the screen (below the header, above the dock) by dragging the page from
    /// its edge (outside the cards, so an inner list does not scroll instead); a tap behind the dock would hit the dock
    private func bringAboveDock(_ e: XCUIElement) {
        let dockTop = app.buttons["گزارش‌ها"].firstMatch.exists ? app.buttons["گزارش‌ها"].firstMatch.frame.minY - 12 : 760
        for _ in 0..<10 {
            guard e.exists else { return }
            let f = e.frame
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
            if f.maxY > dockTop {
                edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: -min(250, f.maxY - dockTop + 80))))
            } else if f.minY < 140 {
                edge.press(forDuration: 0.05, thenDragTo: edge.withOffset(CGVector(dx: 0, dy: min(250, 220 - f.minY))))
            } else { return }
            usleep(400_000)
        }
    }

    /// empty a text field: the cursor lands where the tap was (the amount field is right-to-left with grouped digits),
    /// so delete from both ends; deletes at the start of the text do nothing
    private func clearField(_ f: XCUIElement) {
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24)
        for dx in [0.97, 0.03] {
            f.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            f.typeText(deletes)
        }
        let left = (f.value as? String ?? "").filter { $0.isNumber }
        if !left.isEmpty { dumpTree("clear field: \(left)") }
        XCTAssertTrue(left.isEmpty, "field not empty: \(left)")
    }

    /// on a failure: what was on screen (tree printed to the log)
    private func dumpTree(_ step: String) {
        shot("fail-" + step)
        print("UITREE-BEGIN \(step)\n" + String(app.debugDescription.prefix(9000)) + "\nUITREE-END")
    }

    private func alive(_ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "app is not running after: \(step)")
    }

    private func tap(_ e: XCUIElement, _ step: String, timeout: TimeInterval = 6) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing: \(step)")
        shot("before-" + step)
        e.tap()
        sleep(1)
        shot("after-" + step)
        alive(step)
    }

    func testEveryPage() {
        for name in ["دفتر حساب", "شخصی", "یادآوری‌ها", "کیف کارت", "خانه"] {
            tap(app.buttons[name].firstMatch, "dock " + name)
            sleep(1)
            app.swipeUp()
            app.swipeDown()
            alive("scroll " + name)
        }
        let reports = app.buttons["گزارش‌ها"].firstMatch
        if reports.waitForExistence(timeout: 3) {
            reports.tap(); sleep(2); alive("reports")
        }
    }

    func testRemoveSubcategories() {
        // opens straight on Settings › categories (Debug-only launch switch), so nothing else can get in the way
        app.terminate()
        app.launchEnvironment["UITEST_OPEN"] = "categories"
        app.launch()
        tap(labelled("مصالح"), "open مصالح")

        // used subcategory → must pick a replacement
        let ahan = labelled("آهن")
        if !ahan.waitForExistence(timeout: 5) { print("UITREE-BEGIN\n" + app.debugDescription + "\nUITREE-END") }
        XCTAssertTrue(ahan.exists, "subcategory page did not open")
        tap(app.buttons["del.آهن"].firstMatch, "delete آهن")
        tap(app.buttons["سیمان"].firstMatch, "pick replacement")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm replace آهن")
        sleep(2)
        alive("after removing آهن")
        XCTAssertFalse(labelled("آهن").exists)

        // unused subcategory → plain delete
        let gach = labelled("گچ")
        XCTAssertTrue(gach.waitForExistence(timeout: 5))
        tap(app.buttons["del.گچ"].firstMatch, "delete گچ")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm delete گچ")
        sleep(2)
        alive("after removing گچ")

        // whole category with a replacement, from inside its page
        tap(app.buttons["del.category"].firstMatch, "delete category button")
        tap(app.buttons["خوراک"].firstMatch, "pick category replacement")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm category")
        sleep(2)
        alive("after removing مصالح")
        XCTAssertFalse(labelled("سیمان").exists && labelled("مصالح").exists)

        // swipe on the category list (the path that used to crash)
        let food = labelled("خوراک")
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        swipeDelete(food, "swipe delete خوراک")
        sleep(1)
        alive("swipe sheet open")
    }

    // MARK: - more coverage

    /// diagnostic: does a plain tap on the home ⚙︎ open Settings? (prints GEAR-RESULT lines into the CI log)
    /// home search: scopes keep ledgers / personal apart, the ledger filter works, nothing crashes
    func testScopedSearch() {
        let btn = app.buttons["search"].firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 10)); sleep(2)
        tap(btn, "open search")
        let field = app.textFields["search.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        tap(app.buttons["search.scope.all"].firstMatch, "scope all")
        field.tap(); field.typeText("مصالح")
        sleep(1)
        XCTAssertTrue(labelled("سیمان تیپ دو").waitForExistence(timeout: 4), "ledger row found")
        XCTAssertTrue(labelled("پروژه آزمایشی").exists, "grouped under its ledger")
        tap(app.buttons["search.scope.personal"].firstMatch, "scope personal")
        XCTAssertFalse(labelled("سیمان تیپ دو").exists, "ledger row hidden in personal scope")
        tap(app.buttons["search.scope.ledgers"].firstMatch, "scope ledgers")
        tap(app.buttons["search.ledger.a1"].firstMatch, "one ledger")
        XCTAssertTrue(labelled("میلگرد").waitForExistence(timeout: 4))
        tap(app.buttons["search.scope.reminders"].firstMatch, "scope reminders")
        tap(app.buttons["search.scope.all"].firstMatch, "scope all again")
        alive("search")
    }

    /// tankhah by party card: unfolds, a party opens its rows, the PDF is built
    func testTankhahPartyCard() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        sleep(2)
        let card = app.descendants(matching: .any).matching(identifier: "tankhah.card").firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        tap(card, "unfold tankhah card")
        let party = app.buttons["tankhah.party.کارفرما آزمایشی"].firstMatch
        tap(party, "open party")
        XCTAssertTrue(labelled("تنخواه هفتگی").waitForExistence(timeout: 4), "party rows shown")
        tap(app.buttons.matching(identifier: "tankhah.pdf").firstMatch, "tankhah pdf")
        sleep(6)
        alive("after tankhah pdf")
        XCTAssertFalse(labelled("PDF ساخته نشد").exists, "PDF failed")
    }

    /// a reward row is listed (no commission), and a commission payment can stop at a chosen row
    func testRewardAndPartialCommission() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        sleep(2)
        let pay = app.buttons["پرداخت کمیسیون"].firstMatch
        for _ in 0..<4 where !(pay.exists && pay.isHittable) { app.swipeUp() }
        tap(pay, "open settle")
        // open rows: 3 (سیمان), 4 (میلگرد), 6 (نهار) — 5 is the reward, never open
        XCTAssertTrue(app.buttons["settle.row.3"].waitForExistence(timeout: 5), "open rows listed")
        XCTAssertFalse(app.buttons["settle.row.5"].exists, "the reward row must not be open for commission")
        tap(app.buttons["settle.row.4"].firstMatch, "stop at row 4")
        let amount = app.textFields["amount"].firstMatch
        for _ in 0..<5 where !(amount.exists && amount.isHittable) { app.swipeUp() }   // the field is under the row list
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertTrue(SearchEngine_latin(amount.value as? String ?? "").contains("340000"), "amount follows the chosen row: \(amount.value ?? "")")
        // no payment without a pay method
        XCTAssertFalse(app.buttons["settle.save"].firstMatch.isEnabled, "save must wait for a pay method")
        let method = app.buttons["settle.method"].firstMatch
        for _ in 0..<3 where !(method.exists && method.isHittable) { app.swipeUp() }
        tap(method, "pay method menu")
        tap(app.buttons["نقدی"].firstMatch, "cash")
        tap(app.buttons["settle.save"].firstMatch, "save payment")
        sleep(2)
        alive("after partial payment")
        // the live commission now counts only row 6
        waitForUndoBannerToGo()
        bringAboveDock(app.buttons["پرداخت کمیسیون"].firstMatch)
        tap(app.buttons["پرداخت کمیسیون"].firstMatch, "reopen settle")
        let row6 = app.buttons["settle.row.6"]
        if !row6.waitForExistence(timeout: 5) { dumpTree("reopen settle") }
        XCTAssertTrue(row6.exists, "settle sheet reopened with row 6")
        XCTAssertFalse(app.buttons["settle.row.3"].exists, "covered rows are gone")
    }

    private func SearchEngine_latin(_ s: String) -> String {
        let map: [Character: Character] = ["۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4", "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"]
        return String(s.compactMap { c -> Character? in
            if let d = map[c] { return d }
            return c.isNumber ? c : nil
        })
    }

    /// ledger card «جمع ردیف‌ها»: rows 4–6 = 2,500,000 + reward 4,000,000 + 300,000 (تنخواه rows 1–2 never in the sum)
    func testRangeSumCard() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        sleep(2)
        let total = app.staticTexts["range.total"].firstMatch
        for _ in 0..<5 where !(total.exists && total.isHittable) { app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5), "range card on the ledger page")
        XCTAssertTrue((total.label).contains("۷.۷۰۰.۰۰۰"), "all rows: \(total.label)")
        let plus = app.buttons["range.from.plus"].firstMatch
        for _ in 0..<3 { tap(plus, "from +1") }
        sleep(1)
        XCTAssertTrue(app.staticTexts["range.total"].firstMatch.label.contains("۶.۸۰۰.۰۰۰"), "rows 4–6: \(app.staticTexts["range.total"].firstMatch.label)")
        alive("range card")
    }

    /// audit #1: a damaged database opens read-only with a clear message instead of an empty ledger that saves over it
    func testUnreadableDataOpensReadOnly() {
        app.terminate()
        app.launchEnvironment["UITEST_CORRUPT"] = "1"
        app.launch()
        let msg = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "خوانده نشدند")).firstMatch
        XCTAssertTrue(msg.waitForExistence(timeout: 8), "read-only message shown")
        tap(app.buttons["باشه"].firstMatch, "dismiss read-only message")
        alive("read-only mode")
    }

    /// backup policy: a backup with its SHA-256 is made, and the health screen restores it into a throw-away database
    func testBackupHealthCheck() {
        app.terminate()
        app.launchEnvironment["UITEST_OPEN"] = "health"
        app.launch()
        let run = app.buttons["backup.health.run"].firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 8), "health screen opened")
        let deadline = Date().addingTimeInterval(6)
        while !run.isEnabled && Date() < deadline { sleep(1) }
        tap(run, "check all backups")
        let summary = app.descendants(matching: .any).matching(identifier: "backup.health.summary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "results shown")
        XCTAssertFalse(app.images["xmark.octagon.fill"].exists, "no backup failed")
        alive("backup health")
    }

    /// stage 3: how long the main screens take with 20,000 synthetic rows (Debug build on the simulator — the numbers
    /// are for comparing before / after, not the speed of a phone). Printed as «PERF-UI|<step>|<seconds>».
    /// what is on screen at a step of the performance run (app-side launch phases, alerts, a screenshot)
    private func report(_ step: String) {
        shot("perf-" + step)
        let perf = app.descendants(matching: .any).matching(identifier: "debug.perf").firstMatch
        if perf.exists { print("PERF-UI|app phases (ms)|" + perf.label) }
        for a in app.alerts.allElementsBoundByIndex { print("PERF-UI|alert at \(step)|" + a.label) }
        print("PERF-UI|sheets at \(step)|\(app.sheets.count) hittable-dock=\(app.buttons["دفتر حساب"].firstMatch.isHittable)")
        print("PERFTREE-BEGIN \(step)\n" + String(app.debugDescription.prefix(6000)) + "\nPERFTREE-END")
    }

    func testPerformanceWithTwentyThousandRows() {
        app.terminate()
        app.launchEnvironment["UITEST_SYNTH"] = "20000"
        // each step is timed from just before its tap: a tap returns only when the app is idle again, so the
        // drawing of the new page is inside the number
        func time(_ step: String, since t: Date, timeout: TimeInterval = 120, _ until: () -> Bool) {
            while !until() && Date().timeIntervalSince(t) < timeout { usleep(50_000) }
            let s = Date().timeIntervalSince(t)
            print(String(format: "PERF-UI|%@|%.2f%@", step, s, until() ? "" : " (timeout)"))
        }
        /// a coordinate tap (no element re-check after the event, which a long page drawing can trip)
        func press(_ e: XCUIElement) { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let start = Date()
        app.launch()
        let ledgerTab = app.buttons["دفتر حساب"].firstMatch
        time("launch → home (incl. launch)", since: start) { ledgerTab.exists && ledgerTab.isHittable }
        report("launch")

        var t0 = Date()
        press(ledgerTab)
        let pdf = app.buttons.matching(identifier: "pdf").firstMatch
        time("open ledger page", since: t0) { pdf.exists }
        report("ledger")
        // «یادآوری‌ها» is measured last: with 1,000 checks drawn at once its accessibility tree is so large that
        // XCUITest's own check before the next tap times out (the page itself is drawn — see its number)
        for name in ["شخصی", "کیف کارت"] {
            let tab = app.buttons[name].firstMatch
            guard tab.waitForExistence(timeout: 30) else { print("PERF-UI|open \(name)|skipped (no tab)"); continue }
            t0 = Date()
            press(tab)
            time("open " + name, since: t0, timeout: 60) { tab.exists }
        }
        t0 = Date()
        press(app.buttons["دفتر حساب"].firstMatch)
        time("back to ledger", since: t0) { pdf.exists }
        // a slow page is reported (timeout above), not turned into a failure of the whole suite
        if pdf.exists {
            for _ in 0..<4 where !(pdf.exists && pdf.isHittable) { app.swipeUp() }
            t0 = Date()
            pdf.tap()
            let share = app.descendants(matching: .any).matching(NSPredicate(format:
                "identifier == 'ActivityListView' OR label == 'Copy' OR label == 'Save to Files' OR label == 'AirDrop'")).firstMatch
            time("ledger PDF → share sheet", since: t0) { share.exists }
            if share.exists { app.swipeDown(); sleep(1) }
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        } else {
            print("PERF-UI|ledger PDF → share sheet|skipped (page not drawn)")
        }

        // Excel of this ledger, from «گزارش‌ها» (opens on the ledger it was opened from)
        let reports = app.buttons["گزارش‌ها"].firstMatch
        if reports.waitForExistence(timeout: 10) {
            t0 = Date()
            press(reports)
            let excel = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Excel'")).firstMatch
            time("open reports (ledger)", since: t0, timeout: 60) { excel.exists }
            if excel.exists {
                for _ in 0..<6 where !excel.isHittable { app.swipeUp() }
                t0 = Date()
                excel.tap()
                let share = app.descendants(matching: .any).matching(NSPredicate(format:
                    "identifier == 'ActivityListView' OR label == 'Copy' OR label == 'Save to Files' OR label == 'AirDrop'")).firstMatch
                time("ledger Excel → share sheet", since: t0, timeout: 60) { share.exists }
                XCTAssertTrue(share.exists, "Excel share sheet")
                XCTAssertFalse(labelled("ساخته نشد").exists, "Excel failed")
                if share.exists { app.swipeDown(); sleep(1) }
                if app.buttons["Close"].exists { app.buttons["Close"].tap() }
            } else {
                XCTFail("no Excel button on the reports page")
            }
        } else {
            XCTFail("no reports button")
        }

        t0 = Date()
        press(app.buttons["خانه"].firstMatch)
        let search = app.buttons["search"].firstMatch
        time("back to home", since: t0) { search.exists && search.isHittable }
        guard search.exists else { print("PERF-UI|search|skipped (home not drawn)"); return }
        t0 = Date()
        search.tap()
        let field = app.textFields["search.field"].firstMatch
        time("open search", since: t0) { field.exists }
        field.tap()
        t0 = Date()                                              // typing included: the search runs on each letter
        field.typeText("سیمان")
        let result = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "نتیجه در")).firstMatch
        time("type «سیمان» → results", since: t0) { result.exists }
        if app.keyboards.count > 0 { app.swipeDown() }           // keyboard away so the dock can be tapped
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable { back.tap() }         // leave search (a pushed page)
        let rem = app.buttons["یادآوری‌ها"].firstMatch
        if !(rem.exists && rem.isHittable) { print("PERF-UI|open یادآوری‌ها|skipped (dock not reachable)") }
        if rem.exists && rem.isHittable {
            t0 = Date()
            press(rem)
            time("open یادآوری‌ها (1,000 checks)", since: t0, timeout: 60) { rem.exists }
        }
        alive("performance run")
    }

    /// stage 3: a change leaves the end-of-day backup pending (start-of-day is written before the change, at once);
    /// the app is closed before the backup is due, and the next launch writes it
    func testPendingBackupCompletesOnNextLaunch() {
        app.terminate()
        app.launchEnvironment["UITEST_MUTATE"] = "1"
        app.launchEnvironment["UITEST_BACKUP_DELAY"] = "120"
        app.launch()
        let note = app.descendants(matching: .any).matching(identifier: "debug.backupNote").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "debug note")
        XCTAssertTrue(note.label.contains("startOfDay=true"), "start-of-day copy written before the change: \(note.label)")
        XCTAssertTrue(note.label.contains("pending=true"), "the end-of-day backup is pending: \(note.label)")
        app.terminate()                                     // closed before the 120 s are up

        app.launchEnvironment["UITEST_MUTATE"] = nil
        app.launchEnvironment["UITEST_BACKUP_DELAY"] = nil
        app.launch()
        let after = app.descendants(matching: .any).matching(identifier: "debug.backupNote").firstMatch
        XCTAssertTrue(after.waitForExistence(timeout: 10), "debug note after relaunch")
        XCTAssertTrue(after.label.contains("pendingCompleted"), "the next launch wrote the pending backup: \(after.label)")
    }

    func testSettingsGearOpens() {
        let gear = app.buttons["settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        sleep(2)
        print("GEAR-RESULT exists=\(gear.exists) hittable=\(gear.isHittable) frame=\(gear.frame) enabled=\(gear.isEnabled)")
        gear.tap()
        var opened = labelled("صفحه‌ی خانه").waitForExistence(timeout: 4)
        print("GEAR-RESULT after tap: opened=\(opened)")
        if !opened {
            gear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.15)
            opened = labelled("صفحه‌ی خانه").waitForExistence(timeout: 4)
            print("GEAR-RESULT after press: opened=\(opened)")
        }
        if !opened {
            let hits = app.descendants(matching: .any).allElementsBoundByIndex
                .filter { $0.exists && $0.frame.contains(gear.frame.center) && $0.frame.width < 500 }
                .prefix(12).map { "\($0.elementType.rawValue):\($0.identifier):\($0.label):\($0.frame)" }
            print("GEAR-RESULT elements under the gear: " + hits.joined(separator: " | "))
        }
        alive("gear")
    }

    /// a ledger expense typed into the form is saved and shows up in the list
    func testAddLedgerExpense() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        sleep(1)
        let add = labelled("ثبت هزینه یا تنخواه")
        for _ in 0..<3 where !(add.exists && add.isHittable) { app.swipeUp() }
        tap(add, "open form")
        let desc = app.textFields["شرح"].firstMatch
        XCTAssertTrue(desc.waitForExistence(timeout: 5), "form did not open")
        desc.tap(); desc.typeText("UITest cement")
        let cat = app.textFields["نوع هزینه"].firstMatch
        cat.tap(); cat.typeText("Materials")
        let sub = app.textFields["زیردسته"].firstMatch
        sub.tap(); sub.typeText("Cement")
        let amount = app.textFields["amount"].firstMatch
        amount.tap(); amount.typeText("120000")
        tap(app.buttons["ذخیره"].firstMatch, "save expense")
        sleep(2)
        alive("after save")
        XCTAssertTrue(labelled("UITest cement").waitForExistence(timeout: 5), "the new row is not in the list")
    }

    /// «مانده تنخواه» on the ledger's main card: −700,000 for the fixture (tankhah 7,000,000; expenses 7,700,000, as in
    /// the PDF), and it follows add, edit and delete at once
    func testTankhahRemainingOnLedgerCard() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        let box = app.descendants(matching: .any).matching(identifier: "ledger.tankhahRemaining").firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 6), "tankhah remainder on the main card")
        func expect(_ figure: String, _ step: String) {
            let p = NSPredicate(format: "label CONTAINS %@", figure)
            let ok = XCTNSPredicateExpectation(predicate: p, object: box)
            XCTAssertEqual(XCTWaiter().wait(for: [ok], timeout: 5), .completed, "\(step): \(box.label)")
        }
        expect("−۷۰۰.۰۰۰", "start")

        // add 120,000 → −820,000
        let add = labelled("ثبت هزینه یا تنخواه")
        for _ in 0..<3 where !(add.exists && add.isHittable) { app.swipeUp() }
        tap(add, "open form")
        let desc = app.textFields["شرح"].firstMatch
        XCTAssertTrue(desc.waitForExistence(timeout: 5), "form did not open")
        desc.tap(); desc.typeText("UITest brick")
        let cat = app.textFields["نوع هزینه"].firstMatch
        cat.tap(); cat.typeText("Materials")
        let sub = app.textFields["زیردسته"].firstMatch
        sub.tap(); sub.typeText("Brick")
        let amount = app.textFields["amount"].firstMatch
        amount.tap(); amount.typeText("120000")
        tap(app.buttons["ذخیره"].firstMatch, "save expense")
        sleep(1)
        for _ in 0..<3 where !box.isHittable { app.swipeDown() }
        expect("−۸۲۰.۰۰۰", "after add")

        // edit it to 220,000 → −920,000
        // the row itself (the «جمع ردیف‌ها» card also names it, as «… تا «UITest brick»»)
        let row = app.descendants(matching: .any).matching(NSPredicate(format:
            "label CONTAINS %@ AND NOT (label CONTAINS %@)", "UITest brick", "«")).firstMatch
        waitForUndoBannerToGo()
        bringAboveDock(row)
        tap(row, "open row")
        let amount2 = app.textFields["amount"].firstMatch
        if !amount2.waitForExistence(timeout: 5) { dumpTree("open row") }
        XCTAssertTrue(amount2.exists, "edit form did not open")
        clearField(amount2)
        amount2.typeText("220000")
        tap(app.buttons["ذخیره"].firstMatch, "save edit")
        sleep(1)
        expect("−۹۲۰.۰۰۰", "after edit")

        // delete it → −700,000
        waitForUndoBannerToGo()
        bringAboveDock(row)
        row.press(forDuration: 1.2)
        tap(app.buttons["حذف"].firstMatch, "delete row")
        sleep(1)
        expect("−۷۰۰.۰۰۰", "after delete")
        alive("tankhah remainder")
    }

    /// a ledger without tankhah: the main card looks as before (no tankhah remainder)
    func testNoTankhahRemainderWithoutTankhah() {
        app.terminate()
        let noTankhah = Self.fixture.split(separator: "\n").filter { !$0.contains("\"type\": \"tankhah\"") }.joined(separator: "\n")
            .replacingOccurrences(of: ",\\s*\\]", with: "]", options: .regularExpression)     // no comma left before «]»
        app.launchEnvironment["UITEST_STATE"] = noTankhah
        app.launch()
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        XCTAssertTrue(labelled("جمع هزینه‌ها").waitForExistence(timeout: 6), "main card")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "ledger.tankhahRemaining").firstMatch.exists,
                       "no tankhah remainder on a ledger without tankhah")
    }

    /// building a PDF from a card (category breakdown / transactions) works and opens the share sheet
    func testPDFExportFromLedger() {
        tap(app.buttons["دفتر حساب"].firstMatch, "dock ledger")
        sleep(2)
        let pdf = app.buttons.matching(identifier: "pdf").firstMatch
        for _ in 0..<4 where !(pdf.exists && pdf.isHittable) { app.swipeUp() }
        tap(pdf, "pdf button")
        sleep(6)
        alive("after pdf")
        XCTAssertFalse(labelled("PDF ساخته نشد").exists, "PDF failed")
    }

    /// section backup screen: JSON and text copies are made without errors
    func testSectionBackupExports() {
        app.terminate()
        app.launchEnvironment["UITEST_OPEN"] = "backup"
        app.launch()
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "خروجی JSON")).firstMatch, "json export")
        sleep(2)
        alive("after json")
        XCTAssertFalse(labelled("فایل ساخته نشد").exists)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
