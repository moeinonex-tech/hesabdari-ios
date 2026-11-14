import SwiftUI
import HesabCore

// PDFs that the web app had and the iOS app did not (owner's request: only PDF, a small button at the top-left
// of the card it belongs to, like the other cards). All use the same A4 table page as the other reports.

/// the same small share/PDF icon the other cards use; builds the file and opens the share sheet
struct CardPDFButton: View {
    var id = "pdf"
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
                .accessibilityIdentifier(id)
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

    /// every تنخواه of this ledger: totals and a split bar per party (one colour each, as in the ledger card), then the rows by party
    func tankhahPartyPDF(accountId: String) async -> ExportFile? {
        let rep = AccountOps.tankhahPartyReport(state, accountId: accountId)
        let name = accounts.first { $0.id == accountId }?.name ?? "حساب"
        let st = state
        let html = ReportHTML.tankhahReport(account: name, date: BackupExporter.formatJalali(Self.today), groups: rep.groups, total: rep.total,
                                            method: { TankhahPalette.method($0, state: st) }, rowDate: { Self.pdfDate(ImportAnalyzer.date($0)) })
        return await pdfRender(html, "تنخواه به تفکیک طرف حساب - " + name)
    }

    /// Commission of a ledger: where it stands, every payment (what it covered, what was due, what was paid, the balance
    /// after it), then the rows still open with what would be due if a payment covered up to each of them.
    func commissionPDF(accountId: String) async -> ExportFile? {
        guard let a = accounts.first(where: { $0.id == accountId }) else { return nil }
        let expenses = (state["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        let rowOf = Dictionary(expenses.compactMap { e in e["commissionSettlementId"]?.idString.map { ($0, e) } }) { x, _ in x }
        // payments in the order they were made; one without its ledger row no longer counts (as in the app)
        let sets = (accountRecord(accountId)?["commissionSettlements"]?.arrayValue ?? []).enumerated()
            .filter { rowOf[$0.element["id"]?.idString ?? ""] != nil }
            .sorted { x, y in
                let tx = x.element["ts"]?.intValue ?? 0, ty = y.element["ts"]?.intValue ?? 0
                return tx != ty ? tx < ty : x.offset < y.offset
            }.map(\.element)
        let open = LedgerOps.openCommissionRows(state, accountId: accountId)
        let rewards = expenses.filter { $0["reward"]?.isTruthy ?? false }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let paid = sets.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let esc = ReportHTML.esc

        var h = "<!doctype html><html lang=\"fa\" dir=\"rtl\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=595.28, initial-scale=1, maximum-scale=1, user-scalable=no\"><style>"
            + ReportHTML.css + "</style></head><body>"
        h += "<div class=\"hdr\"><div><div class=\"title\">گزارش کمیسیون — «" + esc(a.name) + "»</div><div class=\"sub\">"
            + esc(pdfSub("کمیسیون " + Fmt.percent(a.percent) + " و پرداخت‌ها")) + " — مبالغ به تومان</div></div></div>"
        func kpi(_ k: String, _ v: String, _ cls: String = "") -> String {
            "<div class=\"cx-kpi\"><div class=\"k\">" + k + "</div><div class=\"v" + cls + "\">" + v + "</div></div>"
        }
        h += "<div class=\"cx-kpis\">" + kpi(a.remaining < 0 ? "بستانکاری" : "مانده‌ی کمیسیون (قابل پرداخت)", pdfMoney(abs(a.remaining)), " main")
            + kpi("کمیسیون ردیف‌های باز (" + Fmt.percent(a.percent) + ")", pdfMoney(a.accrued))
            + kpi("پرداخت‌شده", pdfMoney(paid)) + "</div>"
        h += "<div class=\"cx-kpis cm-sub\">" + kpi("جمع هزینه‌های پروژه", pdfMoney(a.expenseTotal))
            + kpi("پاداش‌ها (بدون کمیسیون)", pdfMoney(rewards))
            + kpi(a.balance < 0 ? "بستانکاری قبلی" : "بدهی قبلی", pdfMoney(abs(a.balance))) + "</div>"

        // 1) payments
        h += "<div class=\"head sec\" data-t=\"پرداخت‌های کمیسیون\"><div class=\"c-num\">#</div><div class=\"c-date\">تاریخ</div>"
            + "<div class=\"c-desc\">ردیف‌های تسویه‌شده</div><div class=\"c-amt\">کمیسیون این مرحله</div>"
            + "<div class=\"c-amt\">پرداخت</div><div class=\"c-amt\">مانده بعد از آن</div></div>"
        if sets.isEmpty { h += "<div class=\"empty\">هنوز پرداختی برای کمیسیون ثبت نشده</div>" }
        for (i, st) in sets.enumerated() {
            let sid = st["id"]?.idString ?? ""
            let ba = st["balanceAfter"]?.intValue
            // only the rows it settled and what is left — not the whole text of the payment row
            let desc = CommissionText.short(desc: rowOf[sid]?["desc"]?.stringValue ?? "", balanceAfter: ba)
            let baText = ba.map { $0 == 0 ? "تسویه" : ($0 > 0 ? pdfMoney($0) + " بدهی" : pdfMoney(-$0) + " بستانکار") } ?? "—"
            h += "<div class=\"row" + alt(i) + "\"><div class=\"c-num\">" + Money.persianDigits(i + 1) + "</div><div class=\"c-date\">" + date(st["date"])
                + "</div><div class=\"c-desc\">" + esc(desc)
                + "</div><div class=\"c-amt\">" + pdfMoney(st["calculatedAmount"]?.intValue ?? 0) + "</div><div class=\"c-amt\">"
                + pdfMoney(ImportAnalyzer.toman(st)) + "</div><div class=\"c-amt" + ((ba ?? 0) > 0 ? " neg" : "") + "\">" + baText + "</div></div>"
        }
        if !sets.isEmpty {
            h += "<div class=\"total\"><div class=\"lbl\">جمع پرداخت‌های کمیسیون (تومان)</div><div class=\"amt\">" + pdfMoney(paid) + "</div></div>"
        }

        // 2) open rows: what a payment up to each row would be
        h += "<div class=\"head sec\" data-t=\"ردیف‌های تسویه‌نشده — قابل پرداخت اگر تا همان ردیف تسویه شود\"><div class=\"c-num wide\">ردیف</div>"
            + "<div class=\"c-date\">تاریخ</div><div class=\"c-desc\">شرح</div><div class=\"c-amt\">مبلغ هزینه</div>"
            + "<div class=\"c-amt\">جمع تا این ردیف</div><div class=\"c-amt\">قابل پرداخت تا اینجا</div></div>"
        if open.isEmpty { h += "<div class=\"empty\">همه‌ی ردیف‌ها تسویه شده‌اند</div>" }
        for (i, r) in open.enumerated() {
            h += "<div class=\"row" + alt(i) + "\"><div class=\"c-num wide\">" + Money.persianDigits(r.num) + "</div><div class=\"c-date\">"
                + Self.pdfDate(r.date) + "</div><div class=\"c-desc\">" + esc(r.desc.isEmpty ? "—" : r.desc) + "</div><div class=\"c-amt\">"
                + pdfMoney(r.toman) + "</div><div class=\"c-amt soft\">" + pdfMoney(r.cumulativeBase) + "</div><div class=\"c-amt\">"
                + pdfMoney(r.cumulativeCommission + a.balance) + "</div></div>"
        }
        if !open.isEmpty {
            let note = a.balance == 0 ? "" : (a.balance > 0 ? " (شامل بدهی قبلی " : " (با کسر بستانکاری قبلی ") + pdfMoney(abs(a.balance)) + ")"
            h += "<div class=\"total\"><div class=\"lbl\">قابل پرداخت برای همه‌ی ردیف‌های باز" + note + "</div><div class=\"amt\">"
                + pdfMoney(a.remaining) + "</div></div>"
        }
        h += "<div class=\"cm-foot\">پاداش‌ها، تنخواه‌ها و خود پرداخت‌های کمیسیون در پایه‌ی کمیسیون حساب نمی‌شوند.</div>"
        return await pdfRender(h + "</body></html>", "کمیسیون - " + a.name)
    }
}
