import XCTest
@testable import HesabCore

final class ReportChartsTests: XCTestCase {
    private func j(_ y: Int, _ m: Int, _ d: Int) -> JalaliDate { JalaliDate(jy: y, jm: m, jd: d) }

    func testTrendBuckets() {
        let list: [ReportCharts.Item] = [(j(1405, 2, 3), 10), (j(1404, 12, 29), 5), (j(1405, 2, 30), 7), (j(1405, 1, 1), 1)]
        XCTAssertEqual(ReportCharts.monthly(list).map(\.value), [5, 1, 17])
        XCTAssertEqual(ReportCharts.monthly(list).map(\.label), ["اسف", "فرو", "ارد"])
        XCTAssertEqual(ReportCharts.yearly(list).map(\.value), [5, 18])
        let d = ReportCharts.daily(list, jy: 1405, jm: 2)
        XCTAssertEqual(d.count, 31)
        XCTAssertEqual(d[2].value, 10)
        XCTAssertEqual(d[29].value, 7)
        XCTAssertEqual(ReportCharts.daily(list, jy: 1404, jm: 12).count, Jalali.monthLength(1404, 12))
    }

    func testCashFlowAndComparison() {
        let inc: [ReportCharts.Item] = [(j(1405, 3, 1), 100)]
        let exp: [ReportCharts.Item] = [(j(1405, 2, 1), 40), (j(1405, 3, 9), 60)]
        let f = ReportCharts.cashFlow(income: inc, expense: exp, yearly: false)
        XCTAssertEqual(f.map(\.income), [0, 100])
        XCTAssertEqual(f.map(\.expense), [40, 60])
        XCTAssertEqual(ReportCharts.cashFlow(income: inc, expense: exp, yearly: true).first?.expense, 100)
        let c = Comparison(income: 300, expense: 200)
        XCTAssertEqual(c.net, 100)
        XCTAssertEqual(c.pct, 67)
        XCTAssertEqual(Comparison(income: 0, expense: 5).pct, 0)
    }

    func testPersonalIncomeScope() {
        let st: [String: JSONValue] = ["incomes": .array([
            .object(["toman": .int(1), "accountId": .string("personal"), "date": .null]),
            .object(["toman": .int(2), "date": .null]),
            .object(["toman": .int(4), "accountId": .string("a1"), "date": .null])])]
        XCTAssertEqual(ReportCharts.personalIncomes(st).reduce(0) { $0 + $1.toman }, 3)
        XCTAssertEqual(ReportCharts.ledgerIncomes(st, accountId: "a1").reduce(0) { $0 + $1.toman }, 4)
    }

    func testCardCopyText() {
        let c: JSONValue = .object(["bankName": .string("بانک ملت"), "cardNumber": .string("6104330000000000"),
                                    "iban": .string("IR12"), "holderName": .string("معین")])
        XCTAssertEqual(SettingsOps.cardCopyText(c), "بانک ملت\n\nشماره کارت ملت :\n6104330000000000\nشماره شبا ملت :\nIR12\nبه نام معین")
        XCTAssertNil(SettingsOps.cardCopyText(.object(["bankName": .string("x")])))
        XCTAssertEqual(SettingsOps.cardCopyText(.object(["last4": .string("1234")])), "شماره کارت  :\n****1234")
    }
}
