import Foundation

/// Settings › «دسته‌ها و زیردسته‌ها»: see the stored categories / subcategories of each part, how many transactions
/// use each one, and remove one. A name that is still used by transactions is never removed silently: the owner must
/// pick (or type) a replacement, and every row (and every item of a multi-item row) is moved to it, together with
/// what the suggestion engine learned, so nothing is left pointing at a deleted name.
public enum CategoryScope: String, CaseIterable, Sendable, Identifiable {
    case ledger, personal, income
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ledger: return "دفتر حساب"
        case .personal: return "هزینه‌های شخصی"
        case .income: return "درآمد"
        }
    }
    var listKey: String { rawValue + "Categories" }
    var subKey: String { rawValue + "Subcategories" }
    var redirectKey: String { rawValue + "CategoryRedirects" }
    var rowArrays: [String] {
        switch self {
        case .ledger: return ["expenses", "reminderChecks"]
        case .personal: return ["personalExpenses"]
        case .income: return ["incomes"]
        }
    }
    var learn: LearnContext {
        switch self {
        case .ledger: return .ledger
        case .personal: return .personal
        case .income: return .income
        }
    }
    /// built-in names the app itself writes (commission rows) — they can't be removed
    var protected: Set<String> {
        switch self {
        case .ledger: return ["کمیسیون"]
        case .personal: return []
        case .income: return [LedgerOps.commissionIncomeCategory]
        }
    }
}

public enum CategoryOps {
    static func t(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespaces) }

    /// rows of the scope, as (array, index, row) — ledger rows that are not expenses (petty cash) have no category
    static func rows(_ st: [String: JSONValue], _ scope: CategoryScope) -> [(String, Int, [String: JSONValue])] {
        var out: [(String, Int, [String: JSONValue])] = []
        for a in scope.rowArrays {
            for (i, v) in LedgerOps.array(st, a).enumerated() {
                if let o = v.objectValue { out.append((a, i, o)) }
            }
        }
        return out
    }

    /// every (category, subcategory) pair a row uses — the row's own, or each item's for a multi-item row
    static func pairs(_ row: [String: JSONValue]) -> [(String, String)] {
        if let items = row["items"]?.arrayValue, !items.isEmpty {
            return items.map { (t($0["category"]?.stringValue), t($0["subcategory"]?.stringValue)) }
        }
        return [(t(row["category"]?.stringValue), t(row["subcategory"]?.stringValue))]
    }

    /// stored categories, then any name rows use that is missing from the list
    public static func categories(_ st: [String: JSONValue], _ scope: CategoryScope) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for v in LedgerOps.array(st, scope.listKey) {
            let c = t(v.stringValue)
            if !c.isEmpty, seen.insert(c).inserted { out.append(c) }
        }
        for (_, _, r) in rows(st, scope) {
            for (c, _) in pairs(r) where !c.isEmpty && seen.insert(c).inserted { out.append(c) }
        }
        return out
    }

    public static func subcategories(_ st: [String: JSONValue], _ scope: CategoryScope, category: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for v in st[scope.subKey]?[category]?.arrayValue ?? [] {
            let s = t(v.stringValue)
            if !s.isEmpty, seen.insert(s).inserted { out.append(s) }
        }
        for (_, _, r) in rows(st, scope) {
            for (c, s) in pairs(r) where c == category && !s.isEmpty && seen.insert(s).inserted { out.append(s) }
        }
        return out
    }

    /// how many transactions use the category (or the subcategory under it)
    public static func usage(_ st: [String: JSONValue], _ scope: CategoryScope, category: String, sub: String? = nil) -> Int {
        rows(st, scope).filter { (_, _, r) in
            pairs(r).contains { $0.0 == category && (sub == nil || $0.1 == sub) }
        }.count
    }

    public static func isProtected(_ scope: CategoryScope, _ category: String) -> Bool { scope.protected.contains(category) }

    /// Remove a category. If rows use it, `replaceWith` must name another category: the rows move to it (keeping
    /// their subcategories, which are added under the new category), and so does the learned data.
    public static func removeCategory(_ state: [String: JSONValue], _ scope: CategoryScope, _ category: String,
                                      replaceWith: String?) throws -> [String: JSONValue] {
        let old = t(category), new = t(replaceWith)
        guard !old.isEmpty else { throw LedgerError.invalid(["دسته"]) }
        if isProtected(scope, old) { throw LedgerError.invalid(["«\(old)» دسته‌ی داخلی برنامه است و حذف نمی‌شود"]) }
        if new == old { throw LedgerError.invalid(["دسته‌ی جایگزین باید با دسته‌ی حذفی فرق کند"]) }
        let used = usage(state, scope, category: old)
        if used > 0 && new.isEmpty { throw LedgerError.invalid(["دسته‌ی جایگزین (\(used) تراکنش از این دسته استفاده می‌کند)"]) }
        var st = state

        // rows
        if !new.isEmpty {
            for a in scope.rowArrays {
                var list = LedgerOps.array(st, a)
                for i in list.indices {
                    guard var row = list[i].objectValue else { continue }
                    var changed = false
                    if !MultiItem.items(of: .object(row)).isEmpty {
                        var items = MultiItem.items(of: .object(row))
                        for k in items.indices where t(items[k].category) == old { items[k].category = new; changed = true }
                        if changed {
                            let total = row["toman"]
                            MultiItem.apply(&row, items)
                            if let total { row["toman"] = total }       // the amount itself is never touched
                        }
                    } else if t(row["category"]?.stringValue) == old {
                        row["category"] = .string(new); changed = true
                    }
                    if changed { list[i] = .object(row) }
                }
                st[a] = .array(list)
            }
            LedgerOps.addCategoryIfNew(&st, list: scope.listKey, new)
        }

        // the stored list and subcategory map (subcategories move to the replacement)
        st[scope.listKey] = .array(LedgerOps.array(st, scope.listKey).filter { t($0.stringValue) != old })
        var subs = st[scope.subKey]?.objectValue ?? [:]
        if let moved = subs.removeValue(forKey: old), !new.isEmpty {
            var target = subs[new]?.arrayValue ?? []
            for s in moved.arrayValue ?? [] where !target.contains(where: { t($0.stringValue) == t(s.stringValue) }) { target.append(s) }
            subs[new] = .array(target)
        }
        st[scope.subKey] = .object(subs)

        // learned data
        let ctx = scope.learn
        var dm = st[ctx.descMap]?.objectValue ?? [:]
        for (k, v) in dm where t(v.stringValue) == old { if new.isEmpty { dm.removeValue(forKey: k) } else { dm[k] = .string(new) } }
        st[ctx.descMap] = .object(dm)
        var km = st[ctx.keywordMap]?.objectValue ?? [:]
        if let words = km.removeValue(forKey: old), !new.isEmpty {
            var target = km[new]?.arrayValue ?? []
            for w in words.arrayValue ?? [] where !target.contains(w) { target.append(w) }
            km[new] = .array(target)
        }
        st[ctx.keywordMap] = .object(km)
        var sdm = st[ctx.subDescMap]?.objectValue ?? [:]
        for (k, v) in sdm where k.hasPrefix(old + "|||") {
            sdm.removeValue(forKey: k)
            if !new.isEmpty { sdm[new + k.dropFirst(old.count)] = v }
        }
        st[ctx.subDescMap] = .object(sdm)
        var skm = st[ctx.subKeywordMap]?.objectValue ?? [:]
        if let m = skm.removeValue(forKey: old)?.objectValue, !new.isEmpty {
            var target = skm[new]?.objectValue ?? [:]
            for (s, words) in m {
                var w = target[s]?.arrayValue ?? []
                for x in words.arrayValue ?? [] where !w.contains(x) { w.append(x) }
                target[s] = .array(w)
            }
            skm[new] = .object(target)
        }
        st[ctx.subKeywordMap] = .object(skm)

        // colour: the replacement keeps its own, or inherits the removed one's
        if var colors = st["categoryColors"]?.objectValue, let c = colors.removeValue(forKey: old) {
            if !new.isEmpty && colors[new] == nil { colors[new] = c }
            st["categoryColors"] = .object(colors)
        }

        // built-in suggestions (fixed keyword table) must not bring the removed name back
        var red = st[scope.redirectKey]?.objectValue ?? [:]
        red[old] = .string(new)
        for (k, v) in red where t(v.stringValue) == old { red[k] = .string(new) }
        st[scope.redirectKey] = .object(red)
        return st
    }

    /// Remove a subcategory of a category. If rows use it, `replaceWith` must name another subcategory (of the same
    /// category); the rows and the learned data move to it.
    public static func removeSubcategory(_ state: [String: JSONValue], _ scope: CategoryScope, category: String, _ sub: String,
                                         replaceWith: String?) throws -> [String: JSONValue] {
        let cat = t(category), old = t(sub), new = t(replaceWith)
        guard !cat.isEmpty, !old.isEmpty else { throw LedgerError.invalid(["زیردسته"]) }
        if new == old { throw LedgerError.invalid(["زیردسته‌ی جایگزین باید با زیردسته‌ی حذفی فرق کند"]) }
        let used = usage(state, scope, category: cat, sub: old)
        if used > 0 && new.isEmpty { throw LedgerError.invalid(["زیردسته‌ی جایگزین (\(used) تراکنش از این زیردسته استفاده می‌کند)"]) }
        var st = state
        if !new.isEmpty {
            for a in scope.rowArrays {
                var list = LedgerOps.array(st, a)
                for i in list.indices {
                    guard var row = list[i].objectValue else { continue }
                    var changed = false
                    if !MultiItem.items(of: .object(row)).isEmpty {
                        var items = MultiItem.items(of: .object(row))
                        for k in items.indices where t(items[k].category) == cat && t(items[k].subcategory) == old {
                            items[k].subcategory = new; changed = true
                        }
                        if changed {
                            let total = row["toman"]
                            MultiItem.apply(&row, items)
                            if let total { row["toman"] = total }
                        }
                    } else if t(row["category"]?.stringValue) == cat && t(row["subcategory"]?.stringValue) == old {
                        row["subcategory"] = .string(new); changed = true
                    }
                    if changed { list[i] = .object(row) }
                }
                st[a] = .array(list)
            }
            LedgerOps.addSubcategoryIfNew(&st, map: scope.subKey, category: cat, new)
        }
        var subs = st[scope.subKey]?.objectValue ?? [:]
        subs[cat] = .array((subs[cat]?.arrayValue ?? []).filter { t($0.stringValue) != old })
        st[scope.subKey] = .object(subs)

        let ctx = scope.learn
        var sdm = st[ctx.subDescMap]?.objectValue ?? [:]
        for (k, v) in sdm where k.hasPrefix(cat + "|||") && t(v.stringValue) == old {
            if new.isEmpty { sdm.removeValue(forKey: k) } else { sdm[k] = .string(new) }
        }
        st[ctx.subDescMap] = .object(sdm)
        var skm = st[ctx.subKeywordMap]?.objectValue ?? [:]
        if var m = skm[cat]?.objectValue, let words = m.removeValue(forKey: old) {
            if !new.isEmpty {
                var w = m[new]?.arrayValue ?? []
                for x in words.arrayValue ?? [] where !w.contains(x) { w.append(x) }
                m[new] = .array(w)
            }
            skm[cat] = .object(m)
            st[ctx.subKeywordMap] = .object(skm)
        }
        return st
    }

    /// suggestion filter: a removed category is replaced by its replacement (or dropped)
    static func redirect(_ st: [String: JSONValue], _ ctx: LearnContext, _ names: [String]) -> [String] {
        let key: String
        switch ctx {
        case .ledger: key = CategoryScope.ledger.redirectKey
        case .personal: key = CategoryScope.personal.redirectKey
        case .income: key = CategoryScope.income.redirectKey
        }
        guard let red = st[key]?.objectValue, !red.isEmpty else { return names }
        var out: [String] = []
        for n in names {
            let m = red[n].map { t($0.stringValue) } ?? n
            if !m.isEmpty && !out.contains(m) { out.append(m) }
        }
        return out
    }
}
