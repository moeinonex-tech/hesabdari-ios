import SwiftUI
import UIKit
import WebKit
import HesabCore

// PDF reports — the web app's .pdf-report (buildPdfReportEl) rebuilt as HTML with the same structure and the
// same icons, styled by App/Report/report.css (neutral-blue paper, rows sized to their content, frosted glass
// rows), and printed by iOS WebKit into A4 pages. Text stays real (vector) text; page numbers «صفحه i از n».

enum ReportHTML {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // web ICON_* (same SVGs as the web PDF)
    static let icons: [String: String] = [
        "check": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 15.5h4M14.5 15.5h2.5"/><path d="m7.5 10.5 1.7 1.7L12 9"/></svg>"#,
        "card": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2.75" y="6" width="18.5" height="13" rx="2.3"/><path d="M2.75 10h18.5"/><path d="M6 15h4"/></svg>"#,
        "cash": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="6.5" width="19" height="11.5" rx="2"/><circle cx="12" cy="12.25" r="2.4"/><path d="M6 9v0M18 15.5v0"/></svg>"#,
        "swap": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h13.5M14 4.3 17.8 8l-3.8 3.7"/><path d="M20 16H6.5M10 12.3 6.2 16l3.8 3.7"/></svg>"#,
        "bank": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="3" width="9" height="18"/><path d="M13.5 8H19v13h-5.5"/><path d="M7.5 7h.01M7.5 11h.01M7.5 15h.01M10.5 7h.01M10.5 11h.01M10.5 15h.01"/></svg>"#,
        "nasiyeh": #"<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4h10M7 20h10"/><path d="M8 4c0 3.5 2 5.5 4 8-2 2.5-4 4.5-4 8M16 4c0 3.5-2 5.5-4 8 2 2.5 4 4.5 4 8"/></svg>"#
    ]

    /// report.css with the bundled Vazirmatn fonts inlined (no file access needed by WebKit)
    static var css: String {
        guard let url = Bundle.main.url(forResource: "report", withExtension: "css"), var c = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        for f in ["Vazirmatn-Regular", "Vazirmatn-Medium", "Vazirmatn-Bold", "Vazirmatn-ExtraBold"] {
            if let u = Bundle.main.url(forResource: f, withExtension: "ttf"), let d = try? Data(contentsOf: u) {
                c = c.replacingOccurrences(of: "url('" + f + ".ttf')", with: "url(data:font/ttf;base64," + d.base64EncodedString() + ")")
            }
        }
        return c
    }

    struct Column { let cls: String; let title: String }
    struct Cell { var html: String }
    struct Card { let title: String; let values: [(String, String, Bool)]; var progress: Double? = nil }

    static func page(title: String, subtitle: String, legend: [(String, String)], columns: [Column], rows: [(cells: [String], cls: String)],
                     empty: String, totalLabel: String, total: Int, cards: [Card]) -> String {
        var h = "<!doctype html><html lang=\"fa\" dir=\"rtl\"><head><meta charset=\"utf-8\"><style>" + css + "</style></head><body>"
        h += "<div class=\"hdr\"><div><div class=\"title\">" + esc(title) + "</div><div class=\"sub\">" + esc(subtitle) + "</div></div>"
        if !legend.isEmpty {
            h += "<div class=\"legend\"><div class=\"legend-title\">راهنمای آیکون روش پرداخت</div><div class=\"legend-items\">"
            for (icon, label) in legend {
                h += "<span class=\"legend-item\"><span class=\"ic\">" + (icons[icon] ?? "") + "</span>" + esc(label) + "</span>"
            }
            h += "</div></div>"
        }
        h += "</div><div class=\"head\">"
        for c in columns { h += "<div class=\"" + c.cls + "\">" + c.title + "</div>" }
        h += "</div>"
        if rows.isEmpty { h += "<div class=\"empty\">" + esc(empty) + "</div>" }
        for r in rows {
            h += "<div class=\"row" + r.cls + "\">"
            for (i, c) in r.cells.enumerated() where i < columns.count { h += "<div class=\"" + columns[i].cls + "\">" + c + "</div>" }
            h += "</div>"
        }
        h += "<div class=\"total\"><div class=\"lbl\">" + esc(totalLabel) + "</div><div class=\"amt\">" + Money.persianDigits(Money.format(total)) + "</div></div>"
        for c in cards {
            h += "<div class=\"card\"><div class=\"lbl\">" + esc(c.title) + "</div><div class=\"vals\">"
            for (l, v, neg) in c.values { h += "<span>" + esc(l) + ": <b" + (neg ? " class=\"neg\"" : "") + ">" + esc(v) + "</b></span>" }
            h += "</div>"
            if let p = c.progress {
                let cls = p >= 1 ? " over" : (p >= 0.8 ? " warn" : "")
                h += "<div class=\"bar\"><div class=\"" + cls + "\" style=\"width:" + String(Int(min(1, max(0.02, p)) * 100)) + "%\"></div></div>"
            }
            h += "</div>"
        }
        return h + "</body></html>"
    }
}

/// WebKit → A4 PDF. Paper colour fills every whole page; a glass pill with «صفحه i از n» sits at the bottom.
@MainActor
final class HTMLPDF: NSObject, WKNavigationDelegate {
    static let paper = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private var web: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?

    static func make(_ html: String) async throws -> Data {
        let r = HTMLPDF()
        return try await r.run(html)
    }

    private func run(_ html: String) async throws -> Data {
        let printable = Self.paper.inset(by: UIEdgeInsets(top: 26, left: 24, bottom: 46, right: 24))
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: printable.width, height: printable.height))
        w.isOpaque = false
        w.backgroundColor = .clear
        w.navigationDelegate = self
        web = w
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            w.loadHTMLString(html, baseURL: nil)
        }
        _ = try? await w.callAsyncJavaScript("await document.fonts.ready; return 1", contentWorld: .page)
        // exact page breaks: nothing may straddle a page edge (the print engine slices blindly)
        if let url = Bundle.main.url(forResource: "paginate", withExtension: "js"), let js = try? String(contentsOf: url, encoding: .utf8) {
            _ = try? await w.evaluateJavaScript(js)
            _ = try? await w.callAsyncJavaScript("return window.paginate(h)", arguments: ["h": Double(printable.height)], contentWorld: .page)
        }
        let renderer = PagedRenderer()
        renderer.addPrintFormatter(w.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: Self.paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        let pages = renderer.numberOfPages
        renderer.total = pages
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, Self.paper, nil)
        for i in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        web = nil
        return data as Data
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded?.resume(throwing: error); loaded = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error); loaded = nil
    }

    final class PagedRenderer: UIPrintPageRenderer {
        var total = 1
        override var footerHeight: CGFloat { get { 40 } set {} }

        override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
            // neutral-blue paper over the whole page, with a faint light at the top
            if let ctx = UIGraphicsGetCurrentContext() {
                let page = HTMLPDF.paper
                let cs = CGColorSpaceCreateDeviceRGB()
                let top = UIColor(red: 0.925, green: 0.945, blue: 0.97, alpha: 1), bottom = UIColor(red: 0.905, green: 0.925, blue: 0.955, alpha: 1)
                if let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: page.height), options: [])
                }
            }
            super.drawPage(at: pageIndex, in: printableRect)
        }

        override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
            let text = "صفحه " + Money.persianDigits(pageIndex + 1) + " از " + Money.persianDigits(total)
            let p = NSMutableParagraphStyle(); p.alignment = .center; p.baseWritingDirection = .rightToLeft
            let a = NSAttributedString(string: text, attributes: [
                .font: UIFont(name: "Vazirmatn-Bold", size: 9) ?? .systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: UIColor(red: 0.35, green: 0.36, blue: 0.41, alpha: 1), .paragraphStyle: p])
            let pill = CGRect(x: HTMLPDF.paper.midX - 58, y: HTMLPDF.paper.height - 34, width: 116, height: 22)
            let path = UIBezierPath(roundedRect: pill, cornerRadius: 11)
            UIColor.white.withAlphaComponent(0.9).setFill(); path.fill()
            UIColor(red: 0.08, green: 0.16, blue: 0.31, alpha: 0.10).setStroke(); path.lineWidth = 0.8; path.stroke()
            a.draw(in: CGRect(x: pill.minX, y: pill.minY + 4, width: pill.width, height: 14))
        }
    }
}

// MARK: - report data (web buildPdfReportEl inputs)

extension AppModel {
    static func pdfDate(_ d: JalaliDate) -> String {
        Money.persianDigits(String(d.jy) + "/" + String(format: "%02d", d.jm) + "/" + String(format: "%02d", d.jd))
    }

    /// web pdfPayMethodIconSvg (+ a short label under the icon)
    static func payMethod(_ e: JSONValue) -> (icon: String, label: String)? {
        let tankhah = e["type"]?.stringValue == "tankhah"
        let pm = e["payMethod"]?.stringValue
        let checkLinked = e["linked"]?["kind"]?.stringValue == "check"
            || (tankhah && (e["checkId"]?.idString != nil || !(e["checkIds"]?.arrayValue ?? []).isEmpty))
        if tankhah {
            if pm == "transfer" { return ("swap", "حواله") }
            if pm == "check" || checkLinked { return ("check", "چک") }
            if pm == "cash" { return ("cash", "نقدی") }
            return nil
        }
        switch pm {
        case "hamrahbank": return ("swap", "همراه‌بانک")
        case "pos": return ("card", "پوز")
        case "card": return ("card", "کارت")
        case "branch": return ("bank", "شعبه بانک")
        case "cash": return ("cash", "نقدی")
        case "nasiyeh": return ("nasiyeh", "نسیه")
        case "check": return ("check", "چک")
        default: return checkLinked ? ("check", "چک") : nil
        }
    }

    /// web pdfCatColumnHtml: invoice rows list their distinct categories one per line
    private func catText(_ e: JSONValue, _ field: String) -> String {
        let own = (e[field]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard let items = e["items"]?.arrayValue, !items.isEmpty else { return own.isEmpty ? "—" : own }
        var seen = Set<String>()
        let names = items.compactMap { $0[field]?.stringValue?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        if names.isEmpty { return own.isEmpty ? "—" : own }
        return names.joined(separator: "\n")
    }

    /// web pdfInvoiceItemsHtml + pdfChecksHtml
    private func descLines(_ e: JSONValue) -> [String] {
        var lines: [String] = []
        if let items = e["items"]?.arrayValue, items.count >= 2 {
            for it in items {
                let label = [it["desc"]?.stringValue, it["subcategory"]?.stringValue, it["category"]?.stringValue]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "قلم"
                lines.append(label + ": " + Money.persianDigits(Money.format(ImportAnalyzer.toman(it))))
            }
        }
        var ids: [String] = []
        if e["type"]?.stringValue == "tankhah" {
            ids = (e["checkIds"]?.arrayValue ?? []).compactMap(\.idString)
            if ids.isEmpty, let c = e["checkId"]?.idString { ids = [c] }
        } else if e["linked"]?["kind"]?.stringValue == "check", let c = e["linked"]?["checkId"]?.idString {
            ids = [c]
        }
        let status = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
        for id in ids {
            guard let c = record("reminderChecks", id) else { continue }
            var bits = ["چک", Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0)), Self.pdfDate(ImportAnalyzer.date(c["dueDate"]))]
            if let n = c["checkNumber"]?.idString, !n.isEmpty { bits.append("#" + Money.persianDigits(n)) }
            if let s = c["status"]?.stringValue { bits.append(status[s] ?? s) }
            lines.append(bits.joined(separator: " · "))
        }
        return lines
    }

    private func sortedRecords(_ list: [JSONValue]) -> [JSONValue] {
        list.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["date"]), db = ImportAnalyzer.date(b.element["date"])
            if da != db { return da < db }
            let ta = a.element["ts"]?.intValue ?? 0, tb = b.element["ts"]?.intValue ?? 0
            return ta != tb ? ta < tb : a.offset < b.offset
        }.map(\.element)
    }

    private func catHTML(_ e: JSONValue, _ field: String) -> String {
        let t = catText(e, field)
        let parts = t.components(separatedBy: "\n")
        if parts.count <= 1 { return ReportHTML.esc(t) }
        return "<div class=\"multi\">" + parts.map { "<div>" + ReportHTML.esc($0) + "</div>" }.joined() + "</div>"
    }

    /// web pdfInvoiceItemsHtml + pdfChecksHtml under the description
    private func descHTML(_ e: JSONValue) -> String {
        var h = ReportHTML.esc(e["desc"]?.stringValue ?? "")
        if let items = e["items"]?.arrayValue, items.count >= 2 {
            h += "<div class=\"items\">"
            for it in items {
                let label = [it["desc"]?.stringValue, it["subcategory"]?.stringValue, it["category"]?.stringValue]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "قلم"
                h += "<div class=\"item\"><span class=\"lbl\">" + ReportHTML.esc(label) + ":</span><span class=\"amt\">"
                    + Money.persianDigits(Money.format(ImportAnalyzer.toman(it))) + "</span></div>"
            }
            h += "</div>"
        }
        var ids: [String] = []
        if e["type"]?.stringValue == "tankhah" {
            ids = (e["checkIds"]?.arrayValue ?? []).compactMap(\.idString)
            if ids.isEmpty, let c = e["checkId"]?.idString { ids = [c] }
        } else if e["linked"]?["kind"]?.stringValue == "check", let c = e["linked"]?["checkId"]?.idString {
            ids = [c]
        }
        let checks = ids.compactMap { record("reminderChecks", $0) }
        if !checks.isEmpty {
            let label = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
            h += "<div class=\"checks\">"
            for (i, c) in checks.enumerated() {
                let st = c["status"]?.stringValue ?? ""
                let tag = checks.count > 1 ? "چک " + Money.persianDigits(i + 1) : "چک"
                var line = "<span class=\"tag\">" + tag + "</span> <b>" + Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0)) + "</b> · "
                    + Self.pdfDate(ImportAnalyzer.date(c["dueDate"]))
                if let n = c["checkNumber"]?.idString, !n.isEmpty { line += " · #" + Money.persianDigits(n) }
                line += " · <span class=\"" + (st == "cashed" ? "ok" : (st == "bounced" ? "bad" : "")) + "\">" + (label[st] ?? st) + "</span>"
                h += "<div class=\"chk\">" + line + "</div>"
            }
            h += "</div>"
        }
        return h
    }

    /// web pdfBuildColumns + pdfRowHtml
    private func expenseTable(_ records: [JSONValue], showPay: Bool)
        -> (cols: [ReportHTML.Column], rows: [(cells: [String], cls: String)], legend: [(String, String)]) {
        let hasSub = records.contains { e in
            !(e["subcategory"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                || (e["items"]?.arrayValue ?? []).contains { !($0["subcategory"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }
        var cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-date", title: "تاریخ"), .init(cls: "c-cat", title: "دسته")]
        if hasSub { cols.append(.init(cls: "c-sub", title: "زیردسته")) }
        if showPay { cols.append(.init(cls: "c-pay", title: "روش<br>پرداخت")) }
        cols.append(.init(cls: "c-desc", title: "توضیحات"))
        cols.append(.init(cls: "c-amt", title: "مبلغ (تومان)"))
        var used: [(String, String)] = []
        let rows = records.enumerated().map { i, e -> (cells: [String], cls: String) in
            let tankhah = e["type"]?.stringValue == "tankhah"
            var cells = [Money.persianDigits(i + 1), Self.pdfDate(ImportAnalyzer.date(e["date"])), tankhah ? "تنخواه" : catHTML(e, "category")]
            if hasSub { cells.append(catHTML(e, "subcategory")) }
            if showPay {
                if let p = Self.payMethod(e) {
                    if !used.contains(where: { $0.1 == p.label }) { used.append((p.icon, p.label)) }
                    cells.append("<span class=\"ic\">" + (ReportHTML.icons[p.icon] ?? "") + "</span><span class=\"pay-label\">" + p.label + "</span>")
                } else { cells.append("") }
            }
            cells.append(descHTML(e))
            cells.append(Money.persianDigits(Money.format(ImportAnalyzer.toman(e))))
            return (cells, tankhah ? " tk" : (i % 2 == 0 ? " alt" : ""))
        }
        // legend in a fixed order, only what this report uses
        let order = ["پوز", "کارت", "نقدی", "همراه‌بانک", "حواله", "شعبه بانک", "چک", "نسیه"]
        return (cols, rows, used.sorted { (order.firstIndex(of: $0.1) ?? 99) < (order.firstIndex(of: $1.1) ?? 99) })
    }

    private func renderPDF(_ html: String, name: String) async -> ExportFile? {
        do { return exportFile(name: name, data: try await HTMLPDF.make(html)) }
        catch { errorMessage = "PDF ساخته نشد: " + error.localizedDescription; return nil }
    }

    private func money(_ n: Int) -> String { (n < 0 ? "−" : "") + Money.persianDigits(Money.format(abs(n))) }

    private func budgetCard(budget: Int, spent: Int) -> ReportHTML.Card {
        let pct = budget > 0 ? Money.jsRound(Double(spent) / Double(budget) * 100) : 0
        return .init(title: "وضعیت بودجه — مبالغ به تومان",
                     values: [("کل بودجه", money(budget), false), ("هزینه‌شده", money(spent), false),
                              ("باقی‌مانده", money(budget - spent), budget - spent < 0), ("درصد مصرف", Money.persianDigits(pct) + "٪", false)],
                     progress: Double(pct) / 100)
    }

    private func subtitle(_ kind: String, _ range: DateRange?) -> String {
        kind + " — تا تاریخ " + BackupExporter.formatJalali(Self.today) + (range != nil ? " · " + rangeText(range) : "")
    }

    func ledgerPDF(accountId: String, range: DateRange?) async -> ExportFile? {
        guard let a = accounts.first(where: { $0.id == accountId }) else { return nil }
        let all = (state["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let total = list.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let t = expenseTable(list, showPay: true)
        var cards: [ReportHTML.Card] = []
        // web tankhahRemainingInfo: the whole ledger
        if all.contains(where: { $0["type"]?.stringValue == "tankhah" }) {
            let tk = all.filter { $0["type"]?.stringValue == "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            let spent = all.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            cards.append(.init(title: "تنخواه (کل دفتر) — مبالغ به تومان",
                               values: [("جمع تنخواه", money(tk), false), ("جمع هزینه‌ها", money(spent), false),
                                        ("باقی‌مانده تنخواه", money(tk - spent), tk - spent < 0)]))
        }
        let pct = commissionPercent(accountId)
        if pct > 0 {
            let settled = (accountRecord(accountId)?["commissionSettlements"]?.arrayValue ?? [])
                .filter { s in range.map { $0.contains(ImportAnalyzer.date(s["date"])) } ?? true }
                .reduce(0) { $0 + ImportAnalyzer.toman($1) }
            cards.append(.init(title: "کمیسیون (" + Money.persianDigits(pct) + "٪) — مبالغ به تومان",
                               values: [("کمیسیون", money(a.accrued), false), ("پرداخت‌شده", money(settled), false),
                                        ("باقی‌مانده", money(a.remaining), a.remaining < 0)]))
        }
        let b = budget(accountId: accountId)
        if b > 0 { cards.append(budgetCard(budget: b, spent: a.expenseTotal)) }
        let html = ReportHTML.page(title: "گزارش هزینه‌های «" + a.name + "»", subtitle: subtitle("گزارش هزینه‌ها", range), legend: t.legend,
                                   columns: t.cols, rows: t.rows, empty: "هیچ هزینه‌ای ثبت نشده",
                                   totalLabel: "جمع کل هزینه‌ها تا امروز (تومان)", total: total, cards: cards)
        return await renderPDF(html, name: "دفتر حساب - " + a.name + " - " + Self.todayTag() + ".pdf")
    }

    func personalPDF(range: DateRange?) async -> ExportFile? {
        let all = state["personalExpenses"]?.arrayValue ?? []
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let t = expenseTable(list, showPay: true)
        var cards: [ReportHTML.Card] = []
        if personalBudget > 0 { cards.append(budgetCard(budget: personalBudget, spent: all.reduce(0) { $0 + ImportAnalyzer.toman($1) })) }
        let html = ReportHTML.page(title: "گزارش هزینه‌های شخصی", subtitle: subtitle("گزارش هزینه‌ها", range), legend: t.legend,
                                   columns: t.cols, rows: t.rows, empty: "هیچ هزینه‌ای ثبت نشده",
                                   totalLabel: "جمع کل هزینه‌ها تا امروز (تومان)", total: list.reduce(0) { $0 + ImportAnalyzer.toman($1) }, cards: cards)
        return await renderPDF(html, name: "هزینه‌های شخصی - " + Self.todayTag() + ".pdf")
    }

    func incomePDF(range: DateRange?) async -> ExportFile? {
        let all = state["incomes"]?.arrayValue ?? []
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let t = expenseTable(list, showPay: false)
        let html = ReportHTML.page(title: "گزارش درآمد", subtitle: subtitle("گزارش درآمد", range), legend: [],
                                   columns: t.cols, rows: t.rows, empty: "هیچ درآمدی ثبت نشده",
                                   totalLabel: "جمع کل درآمدها (تومان)", total: list.reduce(0) { $0 + ImportAnalyzer.toman($1) }, cards: [])
        return await renderPDF(html, name: "درآمد - " + Self.todayTag() + ".pdf")
    }

    func remindersPDF(range: DateRange?) async -> ExportFile? {
        let all = state["reminderChecks"]?.arrayValue ?? []
        let filtered = range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["dueDate"])) } } ?? all
        let list = filtered.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["dueDate"]), db = ImportAnalyzer.date(b.element["dueDate"])
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        let label = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
        let cols: [ReportHTML.Column] = [.init(cls: "c-num", title: "#"), .init(cls: "c-date", title: "سررسید"),
                                         .init(cls: "c-cat", title: "طرف حساب"), .init(cls: "c-sub", title: "بانک / شماره"),
                                         .init(cls: "c-sub", title: "وضعیت"), .init(cls: "c-desc", title: "توضیحات"),
                                         .init(cls: "c-amt", title: "مبلغ (تومان)")]
        let rows = list.enumerated().map { i, c -> (cells: [String], cls: String) in
            let st = c["status"]?.stringValue ?? ""
            let bank = [c["bankName"]?.stringValue ?? "", (c["checkNumber"]?.idString).map { "#" + Money.persianDigits($0) } ?? ""]
                .filter { !$0.isEmpty }.map(ReportHTML.esc).joined(separator: "<br>")
            let desc = [c["description"]?.stringValue ?? "", c["category"]?.stringValue ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
            let stHTML = "<span class=\"" + (st == "cashed" ? "ok" : (st == "bounced" ? "bad" : "")) + "\">" + (label[st] ?? st) + "</span>"
            return ([Money.persianDigits(i + 1), Self.pdfDate(ImportAnalyzer.date(c["dueDate"])), ReportHTML.esc(c["party"]?.stringValue ?? "—"),
                     bank.isEmpty ? "—" : bank, stHTML, ReportHTML.esc(desc), Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0))],
                    i % 2 == 0 ? " alt" : "")
        }
        let html = ReportHTML.page(title: "گزارش چک‌ها", subtitle: subtitle("گزارش چک‌ها", range), legend: [], columns: cols, rows: rows,
                                   empty: "هیچ چکی ثبت نشده", totalLabel: "جمع مبلغ چک‌ها (تومان)",
                                   total: list.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) }, cards: [])
        return await renderPDF(html, name: "چک‌ها - " + Self.todayTag() + ".pdf")
    }
}

// MARK: - category / subcategory breakdown PDF (ring + ranked bars, same colours as in the app)

extension ReportHTML {
    struct Slice { let name: String; let total: Int; let hex: String }

    /// ring drawn with stroked circle arcs (exact, vector, prints cleanly)
    static func donut(_ s: [Slice]) -> String {
        let total = max(1, s.reduce(0) { $0 + $1.total })
        let r = 52.0, c = 2 * Double.pi * r, gap = s.count > 1 ? 1.6 : 0
        var off = 0.0
        var arcs = ""
        for x in s {
            let len = Double(x.total) / Double(total) * c
            let draw = max(0.6, len - gap)
            arcs += "<circle r=\"\(r)\" cx=\"75\" cy=\"75\" fill=\"none\" stroke=\"\(x.hex)\" stroke-width=\"22\" stroke-dasharray=\"\(draw) \(c - draw)\" stroke-dashoffset=\"\(-off)\" transform=\"rotate(-90 75 75)\"/>"
            off += len
        }
        return "<svg class=\"bd-donut\" viewBox=\"0 0 150 150\">" + arcs
            + "<text x=\"75\" y=\"73\" text-anchor=\"middle\" font-size=\"22\" font-weight=\"800\" fill=\"#161822\">" + Money.persianDigits(s.count) + "</text>"
            + "<text x=\"75\" y=\"91\" text-anchor=\"middle\" font-size=\"10\" fill=\"#585C68\">مورد</text></svg>"
    }

    static func breakdownSection(title: String, unit: String, slices: [Slice]) -> String {
        let total = slices.reduce(0) { $0 + $1.total }
        let mx = max(1, slices.map(\.total).max() ?? 1)
        func pct(_ v: Int) -> String {
            let p = total > 0 ? Double(v) / Double(total) * 100 : 0
            return p > 0 && p < 0.5 ? "زیر ۱٪" : Money.persianDigits(Money.jsRound(p)) + "٪"
        }
        var h = "<div class=\"bd-sec\"><div class=\"bd-title\">" + esc(title)
            + "<small>" + Money.persianDigits(slices.count) + " " + esc(unit) + "</small></div>"
        // ring + total + the biggest one + colour legend
        h += "<div class=\"bd-top\">" + donut(slices) + "<div class=\"bd-sum\"><div><div class=\"k\">جمع (تومان)</div><div class=\"v\">"
            + Money.persianDigits(Money.format(total)) + "</div></div>"
        if let top = slices.first {
            h += "<div><div class=\"k\">بیشترین</div><div class=\"best\"><span class=\"sw\" style=\"background:" + top.hex
                + "\"></span>" + esc(top.name) + " — " + pct(top.total) + "</div></div>"
        }
        h += "<div class=\"bd-leg\">"
        for s in slices.prefix(9) { h += "<span><span class=\"sw\" style=\"background:" + s.hex + "\"></span>" + esc(s.name) + "</span>" }
        if slices.count > 9 { h += "<span style=\"color:#585C68\">و " + Money.persianDigits(slices.count - 9) + " مورد دیگر</span>" }
        h += "</div></div></div>"
        // ranked list; paginate.js puts it in 1–3 columns, numbered top-to-bottom then the next column
        h += "<div class=\"bd-flow\">"
        for (i, s) in slices.enumerated() {
            let w = max(2, Int((Double(s.total) / Double(mx) * 100).rounded()))
            h += "<div class=\"bd-row\"><div class=\"l1\"><span class=\"rk\">" + Money.persianDigits(i + 1) + "</span><span class=\"sw\" style=\"background:" + s.hex
                + "\"></span><span class=\"nm\">" + esc(s.name) + "</span></div><div class=\"l2\"><span class=\"am\">" + Money.persianDigits(Money.format(s.total))
                + "</span><span class=\"pc\">" + pct(s.total) + "</span></div><div class=\"bar\"><div style=\"width:" + String(w)
                + "%;background:linear-gradient(270deg," + s.hex + "," + s.hex + "aa)\"></div></div></div>"
        }
        return h + "</div></div>"
    }

    static func breakdownPage(title: String, subtitle: String, cats: [Slice], subs: [Slice]?, firstIsSub: Bool = false) -> String {
        var h = "<!doctype html><html lang=\"fa\" dir=\"rtl\"><head><meta charset=\"utf-8\"><style>" + css + "</style></head><body>"
        h += "<div class=\"hdr\"><div><div class=\"title\">" + esc(title) + "</div><div class=\"sub\">" + esc(subtitle) + "</div></div></div>"
        h += breakdownSection(title: firstIsSub ? "تفکیک زیردسته‌ها" : "تفکیک دسته‌ها", unit: firstIsSub ? "زیردسته" : "دسته", slices: cats)
        if let subs, !subs.isEmpty { h += breakdownSection(title: "تفکیک زیردسته‌ها", unit: "زیردسته", slices: subs) }
        return h + "</body></html>"
    }
}

extension AppModel {
    /// web-style «گزارش دسته‌ها» PDF: ring + ranked bars; optionally the subcategories in the same file.
    func breakdownPDF(scopeTitle: String, cats: [CategorySlice], subs: [CategorySlice]?, firstIsSub: Bool = false) async -> ExportFile? {
        let conv = { (s: [CategorySlice]) in s.map { ReportHTML.Slice(name: $0.name, total: $0.total, hex: $0.color.hexString) } }
        let html = ReportHTML.breakdownPage(title: (firstIsSub ? "تفکیک زیردسته‌ها — " : subs == nil ? "تفکیک دسته‌ها — " : "تفکیک دسته‌ها و زیردسته‌ها — ") + scopeTitle,
                                            subtitle: "تا تاریخ " + BackupExporter.formatJalali(Self.today) + " — مبالغ به تومان",
                                            cats: conv(cats), subs: subs.map(conv), firstIsSub: firstIsSub)
        do {
            return exportFile(name: (firstIsSub ? "تفکیک زیردسته‌ها - " : "تفکیک دسته‌ها - ") + scopeTitle + " - " + Self.todayTag() + ".pdf", data: try await HTMLPDF.make(html))
        } catch {
            errorMessage = "PDF ساخته نشد: " + error.localizedDescription
            return nil
        }
    }
}
