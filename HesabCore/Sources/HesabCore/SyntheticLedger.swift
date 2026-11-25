import Foundation

/// A synthetic, deterministic dataset for performance tests only (no real data): `rows` records spread like real use
/// — 80% ledger expenses over 5 project ledgers (with تنخواه, rewards, invoices with items, commission on),
/// 10% personal expenses, 5% incomes, 5% checks and debts. Used by the core performance tests and, in Debug builds
/// only, by the simulator performance test (UITEST_SYNTH).
public enum SyntheticLedger {
    public static func make(rows: Int = 20_000, seed: UInt64 = 42) -> [String: JSONValue] {
        var rng = seed
        func next() -> UInt64 { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return rng >> 33 }
        func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
        func date(_ i: Int, of n: Int) -> JSONValue {
            // spread over about two years, 1404-1-1 … 1405-9-1, in order of entry
            let d = Jalali.d2j(Jalali.j2d(1404, 1, 1) + i * 610 / max(1, n))
            return .object(["jy": .int(Int64(d.jy)), "jm": .int(Int64(d.jm)), "jd": .int(Int64(d.jd))])
        }
        let cats: [(String, [String])] = [("مصالح", ["سیمان", "آهن", "آجر", "شن و ماسه"]), ("دستمزد", ["کارگر", "بنا", "جوشکار"]),
                                         ("حمل", ["وانت", "کامیون"]), ("ابزار", ["دستکش", "فرغون"]), ("خوراک", ["نهار", "صبحانه"])]
        let descs = ["خرید سیمان تیپ ۲", "میلگرد ۱۶", "دستمزد کارگر روزمزد", "کرایه وانت", "نهار بتن ریزی", "آجر فشاری",
                     "پمپ بتن هوایی", "شن و ماسه شسته", "دستکش کار", "جوش اسکلت"]
        let methods = ["hamrahbank", "pos", "cash", "transfer"]
        let accounts: [JSONValue] = (1...5).map { i in
            .object(["id": .string("acc\(i)"), "name": .string("پروژه آزمایشی \(i)"), "commissionPercent": .int(10),
                     "commissionEnabled": .bool(true), "commissionSettlements": .array([])])
        }
        let parties: [JSONValue] = (1...6).map { .object(["id": .string("tp\($0)"), "type": .string("person"), "name": .string("طرف حساب \($0)")]) }

        let nLedger = rows * 80 / 100, nPersonal = rows / 10, nIncome = rows / 20, nChecks = rows - nLedger - nPersonal - nIncome
        var expenses: [JSONValue] = []
        expenses.reserveCapacity(nLedger)
        for i in 0..<nLedger {
            let c = pick(cats)
            var e: [String: JSONValue] = [
                "id": .string("e\(i)"), "accountId": .string("acc\(1 + Int(next() % 5))"), "desc": .string(pick(descs)),
                "category": .string(c.0), "subcategory": .string(pick(c.1)), "toman": .int(Int64(10_000 * (1 + Int(next() % 5_000)))),
                "date": date(i, of: nLedger), "ts": .int(Int64(1_700_000_000_000 + i * 1000)), "payMethod": .string(pick(methods)),
                "type": .string("expense"),
            ]
            let r = next() % 100
            if r < 5 {
                e["type"] = .string("tankhah"); e["partyId"] = .string("tp\(1 + Int(next() % 6))"); e["payMethod"] = .string("transfer")
            } else if r < 7 {
                e["reward"] = .bool(true); e["category"] = .string("پاداش")
            } else if r < 12 {
                e["items"] = .array((0..<3).map { k in
                    .object(["desc": .string(pick(descs)), "category": .string(c.0), "subcategory": .string(c.1[k % c.1.count]),
                             "toman": .int(Int64(10_000 * (1 + Int(next() % 500))))])
                })
            }
            expenses.append(.object(e))
        }
        let personal: [JSONValue] = (0..<nPersonal).map { i in
            .object(["id": .string("p\(i)"), "desc": .string(pick(descs)), "category": .string("خانه"), "subcategory": .string("خرید"),
                     "toman": .int(Int64(5_000 * (1 + Int(next() % 2_000)))), "date": date(i, of: nPersonal),
                     "ts": .int(Int64(1_700_000_000_000 + i * 1000)), "payMethod": .string(pick(methods))])
        }
        let incomes: [JSONValue] = (0..<nIncome).map { i in
            .object(["id": .string("i\(i)"), "desc": .string("دریافتی پروژه"), "category": .string("پیمانکاری"), "subcategory": .string("قسط"),
                     "toman": .int(Int64(1_000_000 * (1 + Int(next() % 50)))), "date": date(i, of: nIncome),
                     "ts": .int(Int64(1_700_000_000_000 + i * 1000)), "payMethod": .string("transfer")])
        }
        let checks: [JSONValue] = (0..<nChecks).map { i in
            .object(["id": .string("c\(i)"), "party": .string("فروشنده \(i % 40)"), "checkNumber": .string(String(100_000 + i)),
                     "bankName": .string("بانک ملت"), "amount": .int(Int64(1_000_000 * (1 + Int(next() % 30)))),
                     "dueDate": date(i, of: nChecks), "status": .string(i % 3 == 0 ? "cashed" : "pending"), "direction": .string("pay")])
        }
        return ["accounts": .array(accounts), "tankhahParties": .array(parties), "expenses": .array(expenses),
                "personalExpenses": .array(personal), "incomes": .array(incomes), "reminderChecks": .array(checks),
                "reminderPersons": .array([]), "appointments": .array([]), "cards": .array([])]
    }
}
