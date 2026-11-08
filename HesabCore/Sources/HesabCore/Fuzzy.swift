import Foundation

/// web findFuzzyDuplicateMatches: a typed category/subcategory that is almost (not exactly) an existing one —
/// «ی/ي»، «ک/ك»، half-spaces, punctuation, small typos, a word more or less. Returns up to 3 closest existing names;
/// empty when the value already exists exactly or nothing is similar enough.
public enum Fuzzy {
    static let threshold = 0.82

    public static func normalize(_ s: String) -> String {
        var t = s
        for z in ["\u{200C}", "\u{200B}", "\u{200E}", "\u{200F}"] { t = t.replacingOccurrences(of: z, with: " ") }
        t = t.replacingOccurrences(of: "ي", with: "ی").replacingOccurrences(of: "ى", with: "ی").replacingOccurrences(of: "ك", with: "ک")
        for p in ["،", "؛", ":", ".", "-", "«", "»", "\"", "'", "(", ")"] { t = t.replacingOccurrences(of: p, with: " ") }
        return t.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")
    }

    /// web levenshteinRatioForDup (on UTF-16 units, like JavaScript)
    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a.utf16), y = Array(b.utf16)
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count), cur = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// web wordOverlapRatioForDup (Jaccard of words)
    static func wordOverlap(_ a: String, _ b: String) -> Double {
        let wa = Set(a.split(separator: " ").map(String.init)), wb = Set(b.split(separator: " ").map(String.init))
        if wa.isEmpty || wb.isEmpty { return 0 }
        let inter = wa.intersection(wb).count
        let union = wa.count + wb.count - inter
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    public static func matches(_ list: [String], _ raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !list.isEmpty else { return [] }
        if list.contains(where: { $0.trimmingCharacters(in: .whitespaces) == value }) { return [] }
        let n = normalize(value)
        guard n.count >= 3 else { return [] }
        var scored: [(String, Double)] = []
        var seen = Set<String>()
        for cand in list {
            let c = cand.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty, c != value, seen.insert(c).inserted else { continue }
            let nc = normalize(c)
            guard !nc.isEmpty else { continue }
            let score = nc == n ? 1 : max(levenshteinRatio(n, nc), wordOverlap(n, nc))
            if score >= threshold { scored.append((c, score)) }
        }
        guard let top = scored.map(\.1).max() else { return [] }
        return scored.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element)
            .filter { $0.1 >= top - 0.05 }
            .prefix(3).map(\.0)
    }
}
