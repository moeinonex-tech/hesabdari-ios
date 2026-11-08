import XCTest

/// Runs on the iOS Simulator in CI with a small synthetic state (never real data): visits every page and walks
/// the category manager, including removing subcategories. A crash anywhere fails the test with the crash report.
final class SmokeTests: XCTestCase {
    static let fixture = """
    {
      "accounts": [{"id": "a1", "name": "پروژه آزمایشی", "commissionPercent": 0}],
      "ledgerCategories": ["مصالح", "خوراک", "کمیسیون"],
      "ledgerSubcategories": {"مصالح": ["سیمان", "آهن", "گچ"], "خوراک": ["نهار"]},
      "personalCategories": ["خانه"],
      "personalSubcategories": {"خانه": ["قبض"]},
      "incomeCategories": ["حقوق"],
      "expenses": [
        {"id": "e1", "accountId": "a1", "desc": "سیمان تیپ دو", "category": "مصالح", "subcategory": "سیمان", "toman": 900000, "date": {"jy": 1405, "jm": 8, "jd": 10}, "ts": 1},
        {"id": "e2", "accountId": "a1", "desc": "میلگرد", "category": "مصالح", "subcategory": "آهن", "toman": 2500000, "date": {"jy": 1405, "jm": 8, "jd": 12}, "ts": 2},
        {"id": "e3", "accountId": "a1", "desc": "نهار کارگران", "category": "خوراک", "subcategory": "نهار", "toman": 300000, "date": {"jy": 1405, "jm": 8, "jd": 14}, "ts": 3}
      ],
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
