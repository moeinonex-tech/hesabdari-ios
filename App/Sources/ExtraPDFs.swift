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
                .accessibilityIdentifier("pdf")
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
}
