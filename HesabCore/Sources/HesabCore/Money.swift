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
