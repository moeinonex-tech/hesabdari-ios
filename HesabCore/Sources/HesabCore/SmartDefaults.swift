import Foundation

// Smart defaults learned from the person's own rows.
public enum SmartDefaults {
    /// the card used most in this list (a ledger's rows, or the personal rows); ties → the more recently used one.
    /// Only active (not archived) cards; nil when no row has used a card yet.
    public static func mostUsedCard(_ st: [String: JSONValue], listKey: String, accountId: String?) -> String? {
        let active = Set((st["cards"]?.arrayValue ?? []).compactMap { c -> String? in
            guard let id = c["id"]?.idString, !(c["archived"]?.isTruthy ?? false) else { return nil }
            return id
        })
        var count: [String: Int] = [:]
        var lastTs: [String: Int] = [:]
        for e in st[listKey]?.arrayValue ?? [] {
            if let a = accountId, e["accountId"]?.idString != a { continue }
            guard let cid = e["cardId"]?.idString, active.contains(cid) else { continue }
            count[cid, default: 0] += 1
            lastTs[cid] = max(lastTs[cid] ?? 0, e["ts"]?.intValue ?? 0)
        }
        return count.max { a, b in a.value != b.value ? a.value < b.value : (lastTs[a.key] ?? 0) < (lastTs[b.key] ?? 0) }?.key
    }

    /// the pay methods used most in this list, most used first (only methods a plain row can carry);
    /// filled up with همراه‌بانک and پوز when there is little history
    public static func topPayMethods(_ st: [String: JSONValue], listKey: String, accountId: String?, count n: Int = 2) -> [String] {
        let personal = listKey == "personalExpenses"
        let allowed = personal ? ["hamrahbank", "card", "cash", "transfer", "branch"] : ["hamrahbank", "pos", "cash", "transfer", "branch"]
        var c: [String: Int] = [:]
        for e in st[listKey]?.arrayValue ?? [] {
            if let a = accountId, e["accountId"]?.idString != a { continue }
            if e["type"]?.stringValue == "tankhah" { continue }
            if let m = e["payMethod"]?.stringValue, allowed.contains(m) { c[m, default: 0] += 1 }
        }
        var out = c.sorted { $0.value != $1.value ? $0.value > $1.value : allowed.firstIndex(of: $0.key)! < allowed.firstIndex(of: $1.key)! }.map(\.key)
        for m in (personal ? ["hamrahbank", "card"] : ["hamrahbank", "pos"]) where !out.contains(m) { out.append(m) }
        return Array(out.prefix(n))
    }
}
