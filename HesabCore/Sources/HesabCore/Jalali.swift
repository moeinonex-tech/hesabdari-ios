// Port of the web app's Jalali functions (app.html, "Jalali (Shamsi) calendar math").
// JS `~~(a/b)` is truncating division; Swift Int `/` and `%` truncate the same way,
// so div/mod below behave identically for negative values too.

public struct JalaliDate: Codable, Hashable, Comparable, Sendable {
    public var jy: Int
    public var jm: Int
    public var jd: Int

    public init(jy: Int, jm: Int, jd: Int) {
        self.jy = jy; self.jm = jm; self.jd = jd
    }

    /// Same ordering as the web `jalaliCompareAsc`.
    public static func < (a: JalaliDate, b: JalaliDate) -> Bool {
        if a.jy != b.jy { return a.jy < b.jy }
        if a.jm != b.jm { return a.jm < b.jm }
        return a.jd < b.jd
    }
}

public struct GregorianDate: Hashable, Sendable {
    public var gy: Int
    public var gm: Int
    public var gd: Int

    public init(gy: Int, gm: Int, gd: Int) {
        self.gy = gy; self.gm = gm; self.gd = gd
    }
}

public enum Jalali {
    @inline(__always) static func div(_ a: Int, _ b: Int) -> Int { a / b }
    @inline(__always) static func mod(_ a: Int, _ b: Int) -> Int { a - (a / b) * b }

    static let breaks = [-61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178]

    struct CalInfo { let leap: Int; let gy: Int; let march: Int }

    static func jalCal(_ jy: Int) -> CalInfo {
        let bl = breaks.count
        let gy = jy + 621
        var leapJ = -14
        var jp = breaks[0]
        var jump = 0
        var i = 1
        while i < bl {
            let jm = breaks[i]
            jump = jm - jp
            if jy < jm { break }
            leapJ = leapJ + div(jump, 33) * 8 + div(mod(jump, 33), 4)
            jp = jm
            i += 1
        }
        var n = jy - jp
        leapJ = leapJ + div(n, 33) * 8 + div(mod(n, 33) + 3, 4)
        if mod(jump, 33) == 4 && jump - n == 4 { leapJ += 1 }
        let leapG = div(gy, 4) - div((div(gy, 100) + 1) * 3, 4) - 150
        let march = 20 + leapJ - leapG
        if jump - n < 6 { n = n - jump + div(jump, 33) * 33 }
        var leap = mod(mod(n + 1, 33) - 1, 4)
        if leap == -1 { leap = 4 }
        return CalInfo(leap: leap, gy: gy, march: march)
    }

    /// Julian day number of a Gregorian date.
    public static func g2d(_ gy: Int, _ gm: Int, _ gd: Int) -> Int {
        var d = div((gy + div(gm - 8, 6) + 100100) * 1461, 4) + div(153 * mod(gm + 9, 12) + 2, 5) + gd - 34840408
        d = d - div(div(gy + 100100 + div(gm - 8, 6), 100) * 3, 4) + 752
        return d
    }

    public static func d2g(_ jdn: Int) -> GregorianDate {
        var j = 4 * jdn + 139361631
        j = j + div(div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908
        let i = div(mod(j, 1461), 4) * 5 + 308
        let gd = div(mod(i, 153), 5) + 1
        let gm = mod(div(i, 153), 12) + 1
        let gy = div(j, 1461) - 100100 + div(8 - gm, 6)
        return GregorianDate(gy: gy, gm: gm, gd: gd)
    }

    public static func j2d(_ jy: Int, _ jm: Int, _ jd: Int) -> Int {
        let r = jalCal(jy)
        return g2d(r.gy, 3, r.march) + (jm - 1) * 31 - div(jm, 7) * (jm - 7) + jd - 1
    }

    public static func d2j(_ jdn: Int) -> JalaliDate {
        let gy = d2g(jdn).gy
        var jy = gy - 621
        let r = jalCal(jy)
        let jdn1f = g2d(gy, 3, r.march)
        var k = jdn - jdn1f
        if k >= 0 {
            if k <= 185 {
                return JalaliDate(jy: jy, jm: 1 + div(k, 31), jd: mod(k, 31) + 1)
            } else {
                k -= 186
            }
        } else {
            jy -= 1
            k += 179
            if r.leap == 1 { k += 1 }
        }
        return JalaliDate(jy: jy, jm: 7 + div(k, 30), jd: mod(k, 30) + 1)
    }

    public static func toJalali(_ gy: Int, _ gm: Int, _ gd: Int) -> JalaliDate { d2j(g2d(gy, gm, gd)) }
    public static func toGregorian(_ d: JalaliDate) -> GregorianDate { d2g(j2d(d.jy, d.jm, d.jd)) }
    public static func isLeapYear(_ jy: Int) -> Bool { jalCal(jy).leap == 0 }

    public static func monthLength(_ jy: Int, _ jm: Int) -> Int {
        if jm <= 6 { return 31 }
        if jm <= 11 { return 30 }
        return isLeapYear(jy) ? 30 : 29
    }

    /// 0 = Saturday … 6 = Friday (column weekday_sat0 of the golden CSV).
    public static func weekdaySat0(_ gy: Int, _ gm: Int, _ gd: Int) -> Int {
        (g2d(gy, gm, gd) + 2) % 7
    }
}
