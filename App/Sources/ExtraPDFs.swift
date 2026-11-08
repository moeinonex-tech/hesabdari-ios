import SwiftUI
import HesabCore

// PDFs that the web app had and the iOS app did not (owner's request: only PDF, a small button at the top-left
// of the card it belongs to, like the other cards). All use the same A4 table page as the other reports.

/// the same small share/PDF icon the other cards use; builds the file and opens the share sheet
struct CardPDFButton: View {
    let make: () async -> ExportFile?
    @State private var building = false
    @State private var share: ExportFile?
    @Environment(\.theme) private var t

    var body: some View {
        Group {
            if building {
                ProgressView().controlSize(.small).frame(width: 32, height: 28)
            } else {
                Button {
                    Haptics.tap()
                    building = true
                    Task { @MainActor in
                        share = await make()
                        building = false
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(t.accent)
                        .frame(width: 32, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("خروجی PDF")
            }
        }
        .sheet(item: $share) { f in ActivityView(items: [f.url]) }
    }
}

extension AppModel {
    private func pdfMoney(_ n: Int) -> String { (n < 0 ? "−" : "") + Money.persianDigits(Money.format(abs(n))) }
    private func pdfSub(_ kind: String) -> String { kind + " — تا تاریخ " + BackupExporter.formatJalali(Self.today) }
    private func pdfRender(_ html: String, _ name: String) async -> ExportFile? {
        do { return exportFile(name: name + " - " + Self.todayTag() + ".pdf", data: try await HTMLPDF.make(html)) }
        catch { errorMessage = "PDF ساخته نشد: " + error.localizedDescription; return nil }
    }
    private func alt(_ i: Int) -> String { i % 2 == 0 ? " alt" : "" }
    private func date(_ v: JSONValue?) -> String { Self.pdfDate(ImportAnalyzer.date(v)) }
    private static let checkStatus = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]

    /// web exportTankhahPartyPdf: every تنخواه of this ledger, grouped by who paid it
    func tankhahPartyPDF(accountId: String) async -> ExportFile? {
        let rep = AccountOps.tankhahPartyReport(state, accountId: accountId)
        let name = accounts.first { $0.id == accountId }?.name ?? "حساب"
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-date", title: "تاریخ"),
                                         .init(cls: "c-cat", title: "طرف حساب"), .init(cls: "c-sub", title: "روش دریافت"),
                                         .init(cls: "c-desc", title: "توضیحات"), .init(cls: "c-amt", title: "مبلغ (تومان)")]
        var rows: [(cells: [String], cls: String)] = []
        var i = 0
        for g in rep.groups {
            for r in g.rows {
                let how: String
                switch r["payMethod"]?.stringValue {
                case "transfer": how = "حواله"
                case "check": how = "چک"
                default: how = "نقدی"
                }
                rows.append(([Money.persianDigits(i + 1), date(r["date"]), ReportHTML.esc(g.name), how,
                              ReportHTML.esc(r["desc"]?.stringValue ?? ""), pdfMoney(ImportAnalyzer.toman(.object(r)))], alt(i)))
                i += 1
            }
        }
        let card = ReportHTML.Card(title: "جمع هر طرف حساب — مبالغ به تومان",
                                   values: rep.groups.map { ($0.name, pdfMoney($0.total), false) })
        let html = ReportHTML.page(title: "گزارش تنخواه به تفکیک طرف حساب — «" + name + "»", subtitle: pdfSub("تنخواه دریافتی"),
                                   legend: [], columns: cols, rows: rows, empty: "هنوز تنخواهی برای این پروژه ثبت نشده",
                                   totalLabel: "جمع کل تنخواه دریافتی (تومان)", total: rep.total, cards: rep.groups.isEmpty ? [] : [card])
        return await pdfRender(html, "تنخواه به تفکیک طرف حساب - " + name)
    }

    /// web exportCommissionLedgerReportPdf: the commission of a ledger and every payment of it
    func commissionPDF(accountId: String) async -> ExportFile? {
        guard let a = accounts.first(where: { $0.id == accountId }) else { return nil }
        let sets = (accountRecord(accountId)?["commissionSettlements"]?.arrayValue ?? []).enumerated().sorted { x, y in
            let dx = ImportAnalyzer.date(x.element["date"]), dy = ImportAnalyzer.date(y.element["date"])
            return dx != dy ? dx < dy : x.offset < y.offset
        }.map(\.element)
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-date", title: "تاریخ"),
                                         .init(cls: "c-desc", title: "شرح"), .init(cls: "c-amt", title: "مبلغ پرداخت (تومان)")]
        let rows = sets.enumerated().map { i, s -> (cells: [String], cls: String) in
            let desc = s["desc"]?.stringValue ?? s["description"]?.stringValue ?? "پرداخت کمیسیون"
            return ([Money.persianDigits(i + 1), date(s["date"]), ReportHTML.esc(desc), pdfMoney(ImportAnalyzer.toman(s))], alt(i))
        }
        var values: [(String, String, Bool)] = [("جمع هزینه‌های پروژه", pdfMoney(a.expenseTotal), false),
                                                ("کمیسیون (" + Fmt.percent(a.percent) + ")", pdfMoney(a.accrued), false),
                                                ("پرداخت‌شده", pdfMoney(a.settled), false)]
        if a.balance != 0 { values.append((a.balance > 0 ? "بدهی قبلی" : "بستانکاری قبلی", pdfMoney(abs(a.balance)), false)) }
        values.append((a.remaining < 0 ? "بستانکاری" : "مانده‌ی کمیسیون", pdfMoney(abs(a.remaining)), a.remaining > 0))
        let html = ReportHTML.page(title: "گزارش کمیسیون — «" + a.name + "»", subtitle: pdfSub("کمیسیون و پرداخت‌ها"), legend: [],
                                   columns: cols, rows: rows, empty: "هنوز پرداختی برای کمیسیون ثبت نشده",
                                   totalLabel: "جمع پرداخت‌های کمیسیون (تومان)", total: sets.reduce(0) { $0 + ImportAnalyzer.toman($1) },
                                   cards: [.init(title: "وضعیت کمیسیون — مبالغ به تومان", values: values)])
        return await pdfRender(html, "کمیسیون - " + a.name)
    }

    /// web exportBudgetPdf: budget, spent, remaining, and where the money went (by category, against the budget)
    func budgetPDF(accountId: String?) async -> ExportFile? {
        let isLedger = accountId != nil
        let name = accountId.flatMap { id in accounts.first { $0.id == id }?.name } ?? "هزینه‌های شخصی"
        let b = accountId.map { budget(accountId: $0) } ?? personalBudget
        let items = statItems(isLedger ? "expenses" : "personalExpenses", accountId: accountId)
        let spent = isLedger ? (accounts.first { $0.id == accountId }?.expenseTotal ?? 0) : items.reduce(0) { $0 + $1.toman }
        let groups = ReportHTML.groups(items)
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-cat", title: "دسته"),
                                         .init(cls: "c-sub", title: "سهم از بودجه"), .init(cls: "c-amt", title: "مبلغ (تومان)")]
        let rows = groups.enumerated().map { i, g -> (cells: [String], cls: String) in
            let p = b > 0 ? Double(g.total) / Double(b) * 100 : 0
            let pct = p > 0 && p < 1 ? "زیر ۱٪" : Money.persianDigits(Money.jsRound(p)) + "٪"
            return ([Money.persianDigits(i + 1), ReportHTML.esc(g.name), pct, pdfMoney(g.total)], alt(i))
        }
        let pct = b > 0 ? Money.jsRound(Double(spent) / Double(b) * 100) : 0
        let card = ReportHTML.Card(title: "وضعیت بودجه — مبالغ به تومان",
                                   values: [("کل بودجه", pdfMoney(b), false), ("هزینه‌شده", pdfMoney(spent), false),
                                            ("باقی‌مانده", pdfMoney(b - spent), b - spent < 0), ("درصد مصرف", Money.persianDigits(pct) + "٪", false)],
                                   progress: Double(pct) / 100)
        let html = ReportHTML.page(title: "گزارش بودجه — «" + name + "»", subtitle: pdfSub("بودجه و هزینه‌ها"), legend: [],
                                   columns: cols, rows: rows, empty: "هنوز هزینه‌ای ثبت نشده",
                                   totalLabel: "جمع هزینه‌ها (تومان)", total: spent, cards: [card])
        return await pdfRender(html, "بودجه - " + name)
    }

    /// web exportCardsReportPdf: the active bank cards (no CVV — it is never stored)
    func cardsPDF() async -> ExportFile? {
        let cards = walletCards.filter { !$0.archived }
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-cat", title: "بانک / صاحب کارت"),
                                         .init(cls: "c-desc", title: "شماره کارت / شبا / شماره حساب"), .init(cls: "c-sub", title: "نوع حساب")]
        func group(_ s: String, by n: Int) -> String {
            var out = ""
            for (i, ch) in s.replacingOccurrences(of: " ", with: "").enumerated() { if i > 0 && i % n == 0 { out.append(" ") }; out.append(ch) }
            return out
        }
        let rows = cards.enumerated().map { i, c -> (cells: [String], cls: String) in
            var lines = ["<b dir=\"ltr\">" + Money.persianDigits(group(c.number, by: 4)) + "</b>"]
            if !c.iban.isEmpty { lines.append("شبا: <span dir=\"ltr\">" + Money.persianDigits(group(c.iban, by: 4)) + "</span>") }
            if !c.accountNumber.isEmpty { lines.append("حساب: <span dir=\"ltr\">" + Money.persianDigits(c.accountNumber) + "</span>") }
            return ([Money.persianDigits(i + 1), "<b>" + ReportHTML.esc(c.bankName) + "</b><br>" + ReportHTML.esc(c.holder),
                     lines.joined(separator: "<br>"), ReportHTML.esc(c.accountType.isEmpty ? "—" : c.accountType)], alt(i))
        }
        var html = ReportHTML.page(title: "گزارش کیف کارت‌ها", subtitle: pdfSub("کارت‌های بانکی فعال"), legend: [], columns: cols,
                                   rows: rows, empty: "کارتی ثبت نشده", totalLabel: "تعداد کارت‌ها", total: cards.count, cards: [])
        // the «total» line here is a count, not money
        html = html.replacingOccurrences(of: "<div class=\"amt\">" + Money.persianDigits(Money.format(cards.count)) + "</div>",
                                         with: "<div class=\"amt\">" + Money.persianDigits(cards.count) + "</div>")
        return await pdfRender(html, "کیف کارت‌ها")
    }

    /// web exportPersonsTypeReportPdf: my debtors (they owe me) or my creditors (I owe them), with what is left
    func personsPDF(creditors: Bool) async -> ExportFile? {
        let list = persons.filter { $0.creditor == creditors }.sorted { $0.unpaid > $1.unpaid }
        let title = creditors ? "گزارش بدهی‌های من (طلبکاران)" : "گزارش طلب‌های من (بدهکاران)"
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-cat", title: "نام"),
                                         .init(cls: "c-sub", title: "اقساط"), .init(cls: "c-date", title: "نزدیک‌ترین سررسید"),
                                         .init(cls: "c-amt", title: "کل (تومان)"), .init(cls: "c-amt", title: "مانده (تومان)")]
        let rows = list.enumerated().map { i, p -> (cells: [String], cls: String) in
            let open = p.installments.filter { !$0.paid }
            let paidCount = p.installments.count - open.count
            let next = open.min { $0.daysLeft < $1.daysLeft }
            return ([Money.persianDigits(i + 1), ReportHTML.esc(p.name),
                     Money.persianDigits(paidCount) + " از " + Money.persianDigits(p.installments.count) + " پرداخت‌شده",
                     next.map { Self.pdfDate($0.due) } ?? "—", pdfMoney(p.total), pdfMoney(p.unpaid)], alt(i))
        }
        let html = ReportHTML.page(title: title, subtitle: pdfSub(creditors ? "بدهی‌ها" : "طلب‌ها"), legend: [], columns: cols, rows: rows,
                                   empty: creditors ? "بدهی‌ای ثبت نشده" : "طلبی ثبت نشده",
                                   totalLabel: creditors ? "جمع مانده‌ی بدهی‌های من (تومان)" : "جمع مانده‌ی طلب‌های من (تومان)",
                                   total: list.reduce(0) { $0 + $1.unpaid }, cards: [])
        return await pdfRender(html, creditors ? "بدهی‌های من" : "طلب‌های من")
    }

    /// web exportPartyReportPdf: every registered party with its checks, تنخواه and debts / claims
    func partiesPDF() async -> ExportFile? {
        let norm = AccountOps.normalizeName
        let checks = state["reminderChecks"]?.arrayValue ?? []
        let tkParties = state["tankhahParties"]?.arrayValue ?? []
        let tankhah = (state["expenses"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "tankhah" && $0["partyId"]?.idString != nil }
        let people = state["reminderPersons"]?.arrayValue ?? []
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-date", title: "تاریخ"),
                                         .init(cls: "c-cat", title: "طرف حساب"), .init(cls: "c-sub", title: "نوع"),
                                         .init(cls: "c-desc", title: "توضیحات"), .init(cls: "c-amt", title: "مبلغ (تومان)")]
        var rows: [(cells: [String], cls: String)] = []
        var sums: [(String, String, Bool)] = []
        var grand = 0
        var i = 0
        for party in parties.sorted(by: { $0.fullName < $1.fullName }) {
            let n = norm(party.fullName)
            let pc = checks.filter { norm($0["party"]?.stringValue ?? "") == n && !(($0["party"]?.stringValue ?? "").isEmpty) }
            let pt = tankhah.filter { e in tkParties.contains { $0["id"]?.idString == e["partyId"]?.idString && norm($0["name"]?.stringValue ?? "") == n } }
            let pp = people.filter { $0["partyId"]?.idString == party.id || ($0["partyId"]?.idString == nil && norm($0["name"]?.stringValue ?? "") == n) }
            guard !pc.isEmpty || !pt.isEmpty || !pp.isEmpty else { continue }
            var entries: [(JalaliDate, String, String, Int)] = []
            for c in pc {
                let st = c["status"]?.stringValue ?? ""
                entries.append((ImportAnalyzer.date(c["dueDate"]), "چک", Self.checkStatus[st] ?? st, c["amount"]?.intValue ?? 0))
            }
            for e in pt { entries.append((ImportAnalyzer.date(e["date"]), "تنخواه", e["desc"]?.stringValue ?? "", ImportAnalyzer.toman(e))) }
            var total = entries.reduce(0) { $0 + $1.3 }
            for p in pp {
                let left = (p["installments"]?.arrayValue ?? []).filter { !($0["paid"]?.isTruthy ?? false) }.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) }
                guard left > 0 else { continue }
                let creditor = p["type"]?.stringValue == "creditor"
                entries.append((Self.today, creditor ? "بدهی من" : "طلب من", "مانده‌ی اقساط", left))
                total += left
            }
            for e in entries.sorted(by: { $0.0 < $1.0 }) {
                rows.append(([Money.persianDigits(i + 1), Self.pdfDate(e.0), ReportHTML.esc(party.fullName), e.1, ReportHTML.esc(e.2), pdfMoney(e.3)], alt(i)))
                i += 1
            }
            sums.append((party.fullName, pdfMoney(total), false))
            grand += total
        }
        let html = ReportHTML.page(title: "گزارش یکپارچه‌ی طرف‌های حساب", subtitle: pdfSub("چک، تنخواه، بدهی و طلب"), legend: [],
                                   columns: cols, rows: rows, empty: "هنوز هیچ طرف‌حسابی مرتبط نشده",
                                   totalLabel: "جمع کل همه‌ی طرف‌های حساب (تومان)", total: grand,
                                   cards: sums.isEmpty ? [] : [.init(title: "جمع هر طرف حساب — مبالغ به تومان", values: sums)])
        return await pdfRender(html, "طرف‌های حساب")
    }
}
