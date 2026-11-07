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
        app.launchArguments += ["-lock.enabled", "NO", "-notify.enabled", "NO"]
        app.launchEnvironment["UITEST_STATE"] = Self.fixture
        app.launch()
    }

    /// any element whose label contains the text (rows merge their texts into one label)
    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func alive(_ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "app is not running after: \(step)")
    }

    private func tap(_ e: XCUIElement, _ step: String, timeout: TimeInterval = 6) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "missing: \(step)")
        e.tap()
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
        tap(app.buttons["settings"].firstMatch, "settings")
        let row = labelled("دسته‌ها و زیردسته‌ها")
        for _ in 0..<4 where !(row.exists && row.isHittable) { app.swipeUp() }
        if !row.exists { print("UITREE-BEGIN\n" + app.debugDescription + "\nUITREE-END") }
        tap(row, "categories")
        tap(labelled("مصالح"), "open مصالح")

        // used subcategory → must pick a replacement
        let ahan = labelled("آهن")
        XCTAssertTrue(ahan.waitForExistence(timeout: 5))
        ahan.swipeLeft()
        tap(app.buttons["حذف"].firstMatch, "swipe delete آهن")
        tap(app.buttons["سیمان"].firstMatch, "pick replacement")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm replace آهن")
        sleep(2)
        alive("after removing آهن")
        XCTAssertFalse(labelled("آهن").exists)

        // unused subcategory → plain delete
        let gach = labelled("گچ")
        XCTAssertTrue(gach.waitForExistence(timeout: 5))
        gach.swipeLeft()
        tap(app.buttons["حذف"].firstMatch, "swipe delete گچ")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm delete گچ")
        sleep(2)
        alive("after removing گچ")

        // whole category with a replacement, from inside its page
        tap(app.buttons["حذف خود دسته‌ی «مصالح»"].firstMatch, "delete category button")
        tap(app.buttons["خوراک"].firstMatch, "pick category replacement")
        tap(app.buttons["remove.confirm"].firstMatch, "confirm category")
        sleep(2)
        alive("after removing مصالح")
    }
}
