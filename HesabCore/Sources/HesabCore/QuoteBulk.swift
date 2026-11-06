import Foundation

// web quoteBulkParseRaw — pure parser for pasted quotes; nothing is saved until the preview is confirmed.
// Formats: «text»⏎— author  /  author:⏎«text»  /  several items separated by blank lines.

public struct BulkQuote: Equatable, Sendable {
    public var text: String
    public var author: String
    public var suspicious: Bool
}

public enum QuoteBulk {
    static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    static let leadMarks = re("^[«\"“”'‹›]+\\s*")
    static let trailMarks = re("\\s*[»\"“”'‹›]+$")
    static let dash = re("^[—–\\-−]\\s*(.+)$")
    static let colon = re("^([^:«»\"“”]{1,60}):\\s*$")
    static let quoteChars = re("[«»\"“”]")
    static let spaces = re("\\s+")

    static func replace(_ r: NSRegularExpression, _ s: String, _ with: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: with)
    }
    static func group1(_ r: NSRegularExpression, _ s: String) -> String? {
        guard let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let g = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[g])
    }
    static func count(_ p: String, _ s: String) -> Int { re(p).numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) }
    static func words(_ s: String) -> Int { s.split(whereSeparator: { $0.isWhitespace }).count }
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// JS String.length (UTF-16 units)
    static func jsLen(_ s: String) -> Int { s.utf16.count }

    static func strip(_ s: String) -> String { trim(replace(trailMarks, replace(leadMarks, s, ""), "")) }

    static func dashAuthor(_ line: String) -> String? {
        guard let g = group1(dash, line) else { return nil }
        let name = trim(g)
        if name.isEmpty || quoteChars.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil || jsLen(name) > 60 || words(name) > 7 { return nil }
        return name
    }
    static func colonAuthor(_ line: String) -> String? {
        guard let g = group1(colon, line) else { return nil }
        let name = trim(g)
        if name.isEmpty || words(name) > 7 { return nil }
        return name
    }

    public static func parse(_ raw: String) -> [BulkQuote] {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var records: [BulkQuote] = []
        var buffer: [String] = []
        var pendingAuthor: String?
        var sawBlank = false

        func flush(_ explicit: String?) {
            let author = explicit ?? pendingAuthor
            let textLines = buffer
            buffer = []; pendingAuthor = nil
            guard !textLines.isEmpty else { return }
            let joined = trim(replace(spaces, textLines.joined(separator: " "), " "))
            let text = strip(joined)
            guard !text.isEmpty else { return }
            var suspicious = count("[«\"“]", joined) != count("[»\"”]", joined)
            if textLines.count > 3 || jsLen(text) > 300 { suspicious = true }
            records.append(BulkQuote(text: text, author: trim(author ?? ""), suspicious: suspicious))
        }

        for rawLine in lines {
            let line = trim(rawLine)
            if line.isEmpty { sawBlank = !buffer.isEmpty; continue }
            if let a = dashAuthor(line), !buffer.isEmpty { flush(a); sawBlank = false; continue }
            if let a = colonAuthor(line), buffer.isEmpty {
                if let p = pendingAuthor { records.append(BulkQuote(text: "", author: p, suspicious: true)) }
                pendingAuthor = a; sawBlank = false; continue
            }
            if sawBlank && !buffer.isEmpty { flush(nil) }
            buffer.append(line)
            sawBlank = false
        }
        if !buffer.isEmpty { flush(nil) }
        else if let p = pendingAuthor { records.append(BulkQuote(text: "", author: p, suspicious: true)) }
        return records
    }

    static let numbering = re("^\\s*[0-9۰-۹٠-٩]{1,4}\\s*[\\.\\-\\)\\]:،ـ]\\s*")

    /// A whole text file of quotes. Blank-line separated quotes go through `parse`; a file with one quote per line
    /// (no blank lines between them) is read line by line: «— name» on its own line becomes the previous quote's
    /// author, leading numbers like «12.» or «۱۲-» are dropped. Nothing is dropped silently: overlong lines are flagged.
    public static func parseFile(_ raw: String) -> [BulkQuote] {
        let text = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map(trim)
        let filled = lines.filter { !$0.isEmpty }
        // «sentence» on one line and its author's name alone on the next (no dash), pairs with or without blank lines
        if let pairs = nameLinePairs(lines) { return pairs }
        let blocks = parse(text)
        guard filled.count >= 6, Double(filled.count) / Double(max(1, blocks.count)) > 3 else { return blocks }
        var out: [BulkQuote] = []
        for line in filled {
            if let a = dashAuthor(line), !out.isEmpty, out[out.count - 1].author.isEmpty {
                out[out.count - 1].author = a
                continue
            }
            let t = strip(replace(numbering, line, ""))
            guard !t.isEmpty else { continue }
            let susp = count("[«\"“]", t) != count("[»\"”]", t) || jsLen(t) > 300
            out.append(BulkQuote(text: t, author: "", suspicious: susp))
        }
        return out
    }

    /// a line that is just a name: short, no sentence punctuation, no quote marks
    static func looksLikeName(_ l: String) -> Bool {
        guard !l.isEmpty, jsLen(l) <= 40, words(l) <= 6 else { return false }
        if let last = l.last, ".!?؟…:؛,،".contains(last) { return false }
        return quoteChars.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) == nil
    }

    static func nameLinePairs(_ lines: [String]) -> [BulkQuote]? {
        // blocks split by blank lines
        var blocks: [[String]] = [[]]
        for l in lines { if l.isEmpty { if !(blocks.last!.isEmpty) { blocks.append([]) } } else { blocks[blocks.count - 1].append(l) } }
        blocks = blocks.filter { !$0.isEmpty }
        var flat: [(String, String)] = []
        if blocks.count >= 4, blocks.allSatisfy({ $0.count == 2 }) {
            flat = blocks.map { ($0[0], $0[1]) }
        } else if blocks.count == 1, blocks[0].count >= 8, blocks[0].count % 2 == 0 {
            let b = blocks[0]
            flat = stride(from: 0, to: b.count, by: 2).map { (b[$0], b[$0 + 1]) }
        } else {
            return nil
        }
        // most second lines must be names and the first lines must not all be names
        let names = flat.filter { looksLikeName($0.1) }.count
        guard Double(names) >= Double(flat.count) * 0.9, flat.contains(where: { !looksLikeName($0.0) }) else { return nil }
        return flat.map { (q, a) in
            let t = strip(replace(numbering, q, ""))
            let author = dashAuthor(a) ?? a
            return BulkQuote(text: t, author: author, suspicious: !looksLikeName(a) || count("[«\"“]", t) != count("[»\"”]", t) || jsLen(t) > 300)
        }
    }

    /// web bulkQuotesConfirmBtn: texts shorter than 4 are skipped.
    public static func add(_ state: [String: JSONValue], _ items: [BulkQuote], ids: IdSource = .system) -> (state: [String: JSONValue], added: Int, skipped: Int) {
        var st = state
        var list = LedgerOps.array(st, "customQuotes")
        var added = 0, skipped = 0
        let now = ids.nowMs()
        for (i, q) in items.enumerated() {
            let t = trim(q.text)
            if jsLen(t) < 4 { skipped += 1; continue }
            list.append(.object(["id": .string("\(now)-\(Int.random(in: 0..<1_000_000))-\(i)"), "text": .string(t), "author": .string(trim(q.author))]))
            added += 1
        }
        st["customQuotes"] = .array(list)
        return (st, added, skipped)
    }

    // MARK: web clearLearningHistory
    public static let learningKeys = ["ledgerKeywordMap", "personalKeywordMap", "incomeKeywordMap", "ledgerDescMap", "personalDescMap",
                                      "incomeDescMap", "ledgerSubDescMap", "ledgerSubKeywordMap", "incomeSubDescMap", "incomeSubKeywordMap",
                                      "personalSubDescMap", "personalSubKeywordMap"]
    public static func clearLearning(_ state: [String: JSONValue]) -> [String: JSONValue] {
        var st = state
        for k in learningKeys { st[k] = .object([:]) }
        return st
    }
}
