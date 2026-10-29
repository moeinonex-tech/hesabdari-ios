import Foundation
import XCTest
@testable import HesabCore

final class JalaliMoneyTests: XCTestCase {

    /// 25,933 days (1990-01-01 … 2060-12-31) produced by the web app's own functions in Phase 1
    /// and cross-checked there against ICU's Persian calendar (0 mismatches).
    func testJalaliMatchesWebForEveryDay() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "jalali_days", withExtension: "csv", subdirectory: "Goldens"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").dropFirst()
        var n = 0, bad = 0
        for line in lines {
            let c = line.split(separator: ",")
            guard c.count >= 3 else { continue }
            let g = c[0].split(separator: "-").compactMap { Int($0) }
            let j = c[1].split(separator: "/").compactMap { Int($0) }
            let w = Int(c[2])
            let expected = JalaliDate(jy: j[0], jm: j[1], jd: j[2])
            let got = Jalali.toJalali(g[0], g[1], g[2])
            let back = Jalali.toGregorian(expected)
            if got != expected || back != GregorianDate(gy: g[0], gm: g[1], gd: g[2]) || Jalali.weekdaySat0(g[0], g[1], g[2]) != w {
                bad += 1
                if bad <= 5 { XCTFail("day \(c[0]): got \(got), expected \(expected)") }
            }
            n += 1
        }
        XCTAssertEqual(n, 25_933)
        XCTAssertEqual(bad, 0)
    }

    func testMonthLength() {
        XCTAssertEqual(Jalali.monthLength(1403, 12), 30)   // 1403 is a leap year
        XCTAssertEqual(Jalali.monthLength(1404, 12), 29)
        XCTAssertEqual(Jalali.monthLength(1405, 1), 31)
        XCTAssertEqual(Jalali.monthLength(1405, 7), 30)
    }

    func testMoneyFormatMatchesWeb() {
        XCTAssertEqual(Money.format(0), "0")
        XCTAssertEqual(Money.format(999), "999")
        XCTAssertEqual(Money.format(1000), "1.000")
        XCTAssertEqual(Money.format(1_234_567), "1.234.567")
        XCTAssertEqual(Money.format(-5), "0")               // web clamps negatives to 0
        XCTAssertEqual(Money.format(2.5), "3")
        XCTAssertEqual(Money.jsRound(-2.5), -2)             // JS Math.round
        XCTAssertEqual(Money.jsRound(2.5), 3)
        XCTAssertEqual(Money.persianDigits("40.000 ریال 12"), "۴۰.۰۰۰ ریال ۱۲")
        XCTAssertEqual(Money.jsNumberString(10), "10")
        XCTAssertEqual(Money.jsNumberString(2.5), "2.5")
    }
}
