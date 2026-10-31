// Ports of formatMoney / toPersianDigits / Math.round from the web app.

public enum Money {
    /// JS `Math.round`: halves round toward +infinity (Math.round(-2.5) == -2).
    public static func jsRound(_ x: Double) -> Int {
        Int((x + 0.5).rounded(.down))
    }

    /// Web `formatMoney`: clamps to 0, rounds, groups thousands with ".".
    public static func format(_ n: Int) -> String {
        let v = max(0, n)
        let digits = Array(String(v))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return out
    }

    public static func format(_ n: Double) -> String { format(jsRound(n)) }

    static let persian: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

    /// Web `toPersianDigits`: only ASCII 0–9 are replaced.
    public static func persianDigits(_ s: String) -> String {
        String(s.map { ch -> Character in
            if let a = ch.asciiValue, a >= 48, a <= 57 { return persian[Int(a - 48)] }
            return ch
        })
    }

    public static func persianDigits(_ n: Int) -> String { persianDigits(String(n)) }

    /// Web prints a percent with String(number): 10 → "10", 2.5 → "2.5".
    public static func jsNumberString(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    }
}


// web numberToPersianWords (amounts in words under the amount fields)
public enum PersianWords {
    static let yekan = ["", "یک", "دو", "سه", "چهار", "پنج", "شش", "هفت", "هشت", "نه"]
    static let dahgan = ["", "ده", "بیست", "سی", "چهل", "پنجاه", "شصت", "هفتاد", "هشتاد", "نود"]
    static let dahyek = ["ده", "یازده", "دوازده", "سیزده", "چهارده", "پانزده", "شانزده", "هفده", "هجده", "نوزده"]
    static let sadgan = ["", "صد", "دویست", "سیصد", "چهارصد", "پانصد", "ششصد", "هفتصد", "هشتصد", "نهصد"]
    static let scales = ["", "هزار", "میلیون", "میلیارد", "بیلیون", "بیلیارد", "تریلیون"]

    static func three(_ n: Int) -> String {
        var parts: [String] = []
        let sad = n / 100, rem = n % 100
        if sad > 0 { parts.append(sadgan[sad]) }
        if rem >= 10 && rem <= 19 { parts.append(dahyek[rem - 10]) } else {
            if rem / 10 > 0 { parts.append(dahgan[rem / 10]) }
            if rem % 10 > 0 { parts.append(yekan[rem % 10]) }
        }
        return parts.joined(separator: " و ")
    }

    public static func of(_ num: Int) -> String {
        if num == 0 { return "صفر" }
        if num < 0 { return "منفی " + of(-num) }
        var groups: [Int] = []
        var n = num
        while n > 0 { groups.append(n % 1000); n /= 1000 }
        var parts: [String] = []
        for i in stride(from: groups.count - 1, through: 0, by: -1) where groups[i] != 0 {
            var w = three(groups[i])
            if i > 0 { w += " " + (i < scales.count ? scales[i] : "") }
            parts.append(w)
        }
        return parts.joined(separator: " و ")
    }
}
