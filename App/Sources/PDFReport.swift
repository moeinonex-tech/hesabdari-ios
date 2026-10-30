import SwiftUI
import UIKit
import HesabCore

// PDF reports — same structure as the web app's buildPdfReportEl (title + pay-method legend, columns
// # · تاریخ · دسته · زیردسته · روش پرداخت · توضیحات · مبلغ, total box, tankhah / commission / budget cards,
// «صفحه i از n»), drawn natively (vector text, nothing rasterised) with a softer, Liquid-Glass look:
// tinted paper, rounded glassy rows with a top highlight, glass cards and pills.

struct PDFCell {
    var text: String
    var lines: [String] = []          // small lines under the text (invoice items, linked checks)
    var icon: String? = nil           // SF Symbol (pay method)
}

struct PDFColumn {
    enum Kind { case index, date, category, sub, icon, text, amount }
    let title: String
    let kind: Kind
    let width: CGFloat                // relative
}

struct PDFRow {
    var cells: [PDFCell]
    var tint: UIColor? = nil          // tankhah rows are green-tinted (web pr-row-tankhah)
}

struct PDFInfoCard {
    let title: String
    let items: [(String, String, Bool)]     // label, value, negative
    var progress: Double? = nil
}

struct PDFDoc {
    var title: String
    var subtitle: String
    var legend: [(String, String)]          // icon, label — only the ones used
    var columns: [PDFColumn]
    var rows: [PDFRow]
    var emptyText = "هیچ ردیفی ثبت نشده"
    var totalLabel: String
    var total: Int
    var cards: [PDFInfoCard] = []
}

enum ModernPDF {
    static let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let margin: CGFloat = 26
    static let accent = UIColor(red: 0.04, green: 0.42, blue: 0.85, alpha: 1)
    static let accent2 = UIColor(red: 0.0, green: 0.70, blue: 0.70, alpha: 1)
    static let ink = UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1)
    static let soft = UIColor(red: 0.42, green: 0.45, blue: 0.52, alpha: 1)
    static let paperTop = UIColor(red: 0.925, green: 0.94, blue: 0.965, alpha: 1)
    static let paperBottom = UIColor(red: 0.955, green: 0.965, blue: 0.98, alpha: 1)
    static let danger = UIColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1)

    static func font(_ bold: Bool, _ size: CGFloat) -> UIFont {
        UIFont(name: bold ? "Vazirmatn-Bold" : "Vazirmatn-Regular", size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func text(_ s: String, _ size: CGFloat, bold: Bool = false, color: UIColor = ink, align: NSTextAlignment = .right,
                     ltr: Bool = false) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.baseWritingDirection = ltr ? .leftToRight : .rightToLeft
        p.lineBreakMode = .byWordWrapping
        p.lineSpacing = 1.5
        return NSAttributedString(string: s, attributes: [.font: font(bold, size), .foregroundColor: color, .paragraphStyle: p])
    }

    static func height(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat {
        ceil(a.boundingRect(with: CGSize(width: max(1, w), height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    // MARK: cell content

    static func cellText(_ c: PDFCell, _ kind: PDFColumn.Kind) -> NSAttributedString {
        switch kind {
        case .index: return text(c.text, 8.5, color: soft, align: .center, ltr: true)
        case .date: return text(c.text, 9, color: ink, align: .center, ltr: true)
        case .category: return text(c.text, 9.5, bold: true, color: accent)
        case .sub: return text(c.text, 8.5, color: soft)
        case .icon: return NSAttributedString(string: "")
        case .text: return text(c.text, 9.5)
        case .amount: return text(c.text, 10, bold: true, align: .left, ltr: true)
        }
    }

    static func cellHeight(_ c: PDFCell, _ col: PDFColumn, _ w: CGFloat) -> CGFloat {
        var h = height(cellText(c, col.kind), w)
        for l in c.lines { h += 2 + height(text(l, 8, color: soft), w) }
        return h
    }

    static func rowHeight(_ r: PDFRow, _ cols: [PDFColumn], _ widths: [CGFloat]) -> CGFloat {
        var h: CGFloat = 14
        for (i, col) in cols.enumerated() where i < r.cells.count {
            h = max(h, cellHeight(r.cells[i], col, widths[i] - 10))
        }
        return h + 16
    }

    // MARK: drawing helpers

    static func paper(_ ctx: CGContext) {
        let cs = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: cs, colors: [paperTop.cgColor, paperBottom.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: page.height), options: [])
        }
        // soft colour glows (liquid feel)
        for (c, center, r) in [(accent.withAlphaComponent(0.10), CGPoint(x: page.width - 60, y: 40), CGFloat(260)),
                               (accent2.withAlphaComponent(0.08), CGPoint(x: 40, y: 340), CGFloat(240))] {
            if let g = CGGradient(colorsSpace: cs, colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
            }
        }
    }

    /// rounded glass panel: translucent fill, white rim, a highlight on the top half, soft shadow
    static func glass(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: UIColor, stroke: UIColor? = nil, strokeWidth: CGFloat = 0.8,
                      shadow: Bool = true) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        ctx.saveGState()
        if shadow { ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 5, color: UIColor.black.withAlphaComponent(0.06).cgColor) }
        fill.setFill()
        path.fill()
        ctx.restoreGState()
        // top highlight
        ctx.saveGState()
        path.addClip()
        let cs = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.minY + min(rect.height, 22)), options: [])
        }
        ctx.restoreGState()
        (stroke ?? UIColor.white.withAlphaComponent(0.9)).setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }

    static func symbol(_ name: String, in rect: CGRect, color: UIColor = accent) {
        let cfg = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let s = img.size
        let scale = min(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale, h = s.height * scale
        img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    // MARK: document

    static func make(_ doc: PDFDoc) -> Data {
        let contentW = page.width - margin * 2
        let total = doc.columns.reduce(0) { $0 + $1.width }
        let widths = doc.columns.map { $0.width / total * contentW }
        let headerTop = margin + 70          // table header y on page 1
        let headerTopNext = margin + 6
        let headH: CGFloat = 26
        let footerH: CGFloat = 34
        let bottom = page.height - margin - footerH
        let gap: CGFloat = 5

        // layout: rows then end blocks, never split
        enum Block { case row(Int), empty, total, card(Int) }
        var blocks: [(Block, CGFloat)] = doc.rows.isEmpty ? [(.empty, 40)] :
            doc.rows.enumerated().map { (.row($0.offset), rowHeight($0.element, doc.columns, widths)) }
        blocks.append((.total, 58))
        for (i, c) in doc.cards.enumerated() { blocks.append((.card(i), c.progress == nil ? 62 : 80)) }
        var pages: [[(Block, CGFloat)]] = [[]]
        var y = headerTop + headH + 6
        for b in blocks {
            if y + b.1 > bottom && !pages[pages.count - 1].isEmpty { pages.append([]); y = headerTopNext + headH + 6 }
            pages[pages.count - 1].append(b)
            y += b.1 + gap
        }
        let n = pages.count

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { r in
            for (pi, blocksOnPage) in pages.enumerated() {
                r.beginPage()
                let ctx = r.cgContext
                paper(ctx)
                var y: CGFloat
                if pi == 0 {
                    // title (right) + legend card (left)
                    let legendW: CGFloat = doc.legend.isEmpty ? 0 : 210
                    let titleW = contentW - legendW - 12
                    text(doc.title, 19, bold: true).draw(in: CGRect(x: page.width - margin - titleW, y: margin, width: titleW, height: 30))
                    text(doc.subtitle, 10, color: soft).draw(in: CGRect(x: page.width - margin - titleW, y: margin + 30, width: titleW, height: 16))
                    if !doc.legend.isEmpty {
                        let lr = CGRect(x: margin, y: margin, width: legendW, height: 50)
                        glass(ctx, lr, radius: 12, fill: UIColor.white.withAlphaComponent(0.7))
                        text("راهنمای آیکون روش پرداخت", 8.5, bold: true, color: soft)
                            .draw(in: CGRect(x: lr.minX + 10, y: lr.minY + 7, width: lr.width - 20, height: 14))
                        var x = lr.maxX - 10
                        for (icon, label) in doc.legend {
                            let a = text(label, 8, color: soft)
                            let w = ceil(a.size().width) + 2
                            if x - w - 16 < lr.minX + 6 { break }
                            symbol(icon, in: CGRect(x: x - 11, y: lr.minY + 28, width: 11, height: 9))
                            a.draw(in: CGRect(x: x - 14 - w, y: lr.minY + 25, width: w, height: 14))
                            x -= w + 24
                        }
                    }
                    y = headerTop
                } else {
                    y = headerTopNext
                }
                // column titles + a firm line under them (as on the web)
                var x = page.width - margin
                for (i, col) in doc.columns.enumerated() {
                    x -= widths[i]
                    let isCat = col.kind == .category
                    let align: NSTextAlignment = col.kind == .amount ? .left : (col.kind == .icon || col.kind == .index ? .center : .right)
                    let a = text(col.title, col.kind == .icon ? 7.5 : 9.5, bold: true, color: isCat || col.kind == .icon ? accent : ink, align: align)
                    let h = height(a, widths[i] - 10)
                    a.draw(in: CGRect(x: x + 5, y: y + (headH - h) / 2, width: widths[i] - 10, height: h + 2))
                }
                ink.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: y + headH, width: contentW, height: 1.6), cornerRadius: 0.8).fill()
                y += headH + 6

                for (block, h) in blocksOnPage {
                    switch block {
                    case .row(let i):
                        drawRow(ctx, doc.rows[i], doc.columns, widths, y: y, h: h, odd: i % 2 == 0)
                    case .empty:
                        glass(ctx, CGRect(x: margin, y: y, width: contentW, height: h), radius: 12, fill: UIColor.white.withAlphaComponent(0.75))
                        text(doc.emptyText, 10, color: soft, align: .center).draw(in: CGRect(x: margin, y: y + 12, width: contentW, height: 18))
                    case .total:
                        let rect = CGRect(x: margin, y: y + 4, width: contentW, height: h - 8)
                        glass(ctx, rect, radius: 14, fill: accent.withAlphaComponent(0.06), stroke: accent, strokeWidth: 1.3)
                        text(doc.totalLabel, 10.5, color: soft).draw(in: CGRect(x: rect.midX, y: rect.midY - 9, width: rect.width / 2 - 16, height: 18))
                        text(Money.persianDigits(Money.format(doc.total)), 19, bold: true, color: accent, align: .left, ltr: true)
                            .draw(in: CGRect(x: rect.minX + 16, y: rect.midY - 15, width: rect.width / 2, height: 30))
                    case .card(let i):
                        drawCard(ctx, doc.cards[i], CGRect(x: margin, y: y, width: contentW, height: h))
                    }
                    y += h + gap
                }

                // footer pill
                let label = text("صفحه " + Money.persianDigits(pi + 1) + " از " + Money.persianDigits(n), 9, color: soft, align: .center)
                let pill = CGRect(x: page.width / 2 - 60, y: page.height - margin - 22, width: 120, height: 22)
                glass(ctx, pill, radius: 11, fill: UIColor.white.withAlphaComponent(0.75))
                label.draw(in: CGRect(x: pill.minX, y: pill.minY + 4, width: pill.width, height: 14))
            }
        }
    }

    static func drawRow(_ ctx: CGContext, _ r: PDFRow, _ cols: [PDFColumn], _ widths: [CGFloat], y: CGFloat, h: CGFloat, odd: Bool) {
        let contentW = widths.reduce(0, +)
        let rect = CGRect(x: margin, y: y, width: contentW, height: h)
        let base = r.tint ?? (odd ? UIColor(red: 0.90, green: 0.915, blue: 0.94, alpha: 0.85) : UIColor.white.withAlphaComponent(0.88))
        glass(ctx, rect, radius: 10, fill: base, stroke: UIColor.white.withAlphaComponent(0.95), strokeWidth: 0.7)
        var x = page.width - margin
        for (i, col) in cols.enumerated() {
            x -= widths[i]
            guard i < r.cells.count else { continue }
            let c = r.cells[i]
            let inner = CGRect(x: x + 5, y: y + 8, width: widths[i] - 10, height: h - 16)
            if col.kind == .icon {
                if let s = c.icon { symbol(s, in: CGRect(x: inner.midX - 6, y: inner.minY + 1, width: 12, height: 10)) }
                continue
            }
            let a = cellText(c, col.kind)
            let th = height(a, inner.width)
            a.draw(in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: th + 2))
            var ly = inner.minY + th + 2
            for l in c.lines {
                let la = text(l, 8, color: soft)
                let lh = height(la, inner.width)
                la.draw(in: CGRect(x: inner.minX, y: ly, width: inner.width, height: lh + 2))
                ly += lh + 2
            }
        }
    }

    static func drawCard(_ ctx: CGContext, _ c: PDFInfoCard, _ rect: CGRect) {
        glass(ctx, rect, radius: 14, fill: UIColor.white.withAlphaComponent(0.82))
        text(c.title, 11.5, bold: true, color: accent).draw(in: CGRect(x: rect.minX + 14, y: rect.minY + 9, width: rect.width - 28, height: 20))
        let n = CGFloat(max(1, c.items.count))
        let colW = (rect.width - 28) / n
        var x = rect.maxX - 14
        for (label, value, neg) in c.items {
            let l = text(label + ":", 8.5, color: soft)
            let lw = ceil(l.size().width) + 4
            l.draw(in: CGRect(x: x - lw, y: rect.minY + 36, width: lw, height: 14))
            text(value, 9.5, bold: true, color: neg ? danger : ink, align: .right, ltr: true)
                .draw(in: CGRect(x: x - colW + 4, y: rect.minY + 35, width: colW - lw - 8, height: 16))
            x -= colW
        }
        if let p = c.progress {
            let track = CGRect(x: rect.minX + 14, y: rect.maxY - 18, width: rect.width - 28, height: 7)
            UIColor.black.withAlphaComponent(0.06).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 3.5).fill()
            let w = max(7, track.width * CGFloat(min(1, max(0, p))))
            let fill = CGRect(x: track.maxX - w, y: track.minY, width: w, height: track.height)     // fills from the right (RTL)
            (p >= 1 ? danger : (p >= 0.8 ? UIColor.orange : accent2)).setFill()
            UIBezierPath(roundedRect: fill, cornerRadius: 3.5).fill()
        }
    }
}

// MARK: - report data (web buildPdfReportEl inputs)

extension AppModel {
    static func pdfDate(_ d: JalaliDate) -> String {
        Money.persianDigits(String(d.jy) + "/" + String(format: "%02d", d.jm) + "/" + String(format: "%02d", d.jd))
    }

    /// web pdfPayMethodIconSvg / pdfPayMethodLegendHtml
    static func payIcon(_ e: JSONValue) -> String? {
        let tankhah = e["type"]?.stringValue == "tankhah"
        switch e["payMethod"]?.stringValue {
        case "check": return "doc.text"
        case "pos", "card": return "creditcard"
        case "cash": return "banknote"
        case "hamrahbank": return "arrow.left.arrow.right"
        case "transfer": return tankhah ? "arrow.left.arrow.right" : nil
        case "branch": return "building.columns"
        case "nasiyeh": return "hourglass"
        default: return nil
        }
    }
    static let legendOrder: [(String, String)] = [("doc.text", "چک"), ("creditcard", "کارت / پوز"), ("banknote", "نقدی"),
                                                  ("arrow.left.arrow.right", "همراه‌بانک / حواله"), ("building.columns", "شعبه بانک"),
                                                  ("hourglass", "نسیه")]

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

    /// web pdfBuildColumns + pdfRowHtml
    private func expenseDoc(title: String, records: [JSONValue], showPay: Bool) -> (cols: [PDFColumn], rows: [PDFRow], legend: [(String, String)]) {
        let hasSub = records.contains { e in
            !(e["subcategory"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                || (e["items"]?.arrayValue ?? []).contains { !($0["subcategory"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }
        var cols: [PDFColumn] = [PDFColumn(title: "#", kind: .index, width: 0.45), PDFColumn(title: "تاریخ", kind: .date, width: 1.25),
                                 PDFColumn(title: "دسته", kind: .category, width: 1.35)]
        if hasSub { cols.append(PDFColumn(title: "زیردسته", kind: .sub, width: 1.25)) }
        if showPay { cols.append(PDFColumn(title: "روش\nپرداخت", kind: .icon, width: 0.6)) }
        cols.append(PDFColumn(title: "توضیحات", kind: .text, width: hasSub ? 3.4 : 4.4))
        cols.append(PDFColumn(title: "مبلغ (تومان)", kind: .amount, width: 1.45))
        var used = Set<String>()
        let rows = records.enumerated().map { i, e -> PDFRow in
            let tankhah = e["type"]?.stringValue == "tankhah"
            let icon = showPay ? Self.payIcon(e) : nil
            if let ic = icon { used.insert(ic) }
            var cells = [PDFCell(text: Money.persianDigits(i + 1)), PDFCell(text: Self.pdfDate(ImportAnalyzer.date(e["date"]))),
                         PDFCell(text: tankhah ? "تنخواه" : catText(e, "category"))]
            if hasSub { cells.append(PDFCell(text: catText(e, "subcategory"))) }
            if showPay { cells.append(PDFCell(text: "", icon: icon)) }
            cells.append(PDFCell(text: e["desc"]?.stringValue ?? "", lines: descLines(e)))
            cells.append(PDFCell(text: Money.persianDigits(Money.format(ImportAnalyzer.toman(e)))))
            return PDFRow(cells: cells, tint: tankhah ? UIColor(red: 0.86, green: 0.95, blue: 0.90, alpha: 0.9) : nil)
        }
        return (cols, rows, Self.legendOrder.filter { used.contains($0.0) })
    }

    private func pdfFile(_ doc: PDFDoc, name: String) -> ExportFile? { exportFile(name: name, data: ModernPDF.make(doc)) }

    private func budgetCard(budget: Int, spent: Int) -> PDFInfoCard {
        let pct = budget > 0 ? Money.jsRound(Double(spent) / Double(budget) * 100) : 0
        return PDFInfoCard(title: "وضعیت بودجه — مبالغ به تومان",
                           items: [("کل بودجه", Money.persianDigits(Money.format(budget)), false),
                                   ("هزینه‌شده", Money.persianDigits(Money.format(spent)), false),
                                   ("باقی‌مانده", (budget - spent < 0 ? "−" : "") + Money.persianDigits(Money.format(abs(budget - spent))), budget - spent < 0),
                                   ("درصد مصرف", Money.persianDigits(pct) + "٪", false)],
                           progress: Double(pct) / 100)
    }

    func ledgerPDF(accountId: String, range: DateRange?) -> ExportFile? {
        guard let a = accounts.first(where: { $0.id == accountId }) else { return nil }
        let all = (state["expenses"]?.arrayValue ?? []).filter { $0["accountId"]?.idString == accountId }
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let total = list.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let d = expenseDoc(title: a.name, records: list, showPay: true)
        var cards: [PDFInfoCard] = []
        // web tankhahRemainingInfo: whole ledger
        let tk = all.filter { $0["type"]?.stringValue == "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        if all.contains(where: { $0["type"]?.stringValue == "tankhah" }) {
            let spent = all.filter { $0["type"]?.stringValue != "tankhah" }.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            cards.append(PDFInfoCard(title: "تنخواه (کل دفتر) — مبالغ به تومان",
                                     items: [("جمع تنخواه", Money.persianDigits(Money.format(tk)), false),
                                             ("جمع هزینه‌ها", Money.persianDigits(Money.format(spent)), false),
                                             ("باقی‌مانده تنخواه", (tk - spent < 0 ? "−" : "") + Money.persianDigits(Money.format(abs(tk - spent))), tk - spent < 0)]))
        }
        let pct = commissionPercent(accountId)
        if pct > 0 {
            let settlements = (accountRecord(accountId)?["commissionSettlements"]?.arrayValue ?? [])
                .filter { s in range.map { $0.contains(ImportAnalyzer.date(s["date"])) } ?? true }
            let settled = settlements.reduce(0) { $0 + ImportAnalyzer.toman($1) }
            cards.append(PDFInfoCard(title: "کمیسیون (" + Money.persianDigits(pct) + "٪) — مبالغ به تومان",
                                     items: [("کمیسیون", Money.persianDigits(Money.format(a.accrued)), false),
                                             ("پرداخت‌شده", Money.persianDigits(Money.format(settled)), false),
                                             ("باقی‌مانده", Money.persianDigits(Money.format(a.remaining)), a.remaining < 0)]))
        }
        let budget = budget(accountId: accountId)
        if budget > 0 { cards.append(budgetCard(budget: budget, spent: a.expenseTotal)) }
        let doc = PDFDoc(title: "گزارش هزینه‌های «" + a.name + "»",
                         subtitle: "گزارش هزینه‌ها — تا تاریخ " + BackupExporter.formatJalali(Self.today) + (range != nil ? " · " + rangeText(range) : ""),
                         legend: d.legend, columns: d.cols, rows: d.rows, emptyText: "هیچ هزینه‌ای ثبت نشده",
                         totalLabel: "جمع کل هزینه‌ها تا امروز (تومان)", total: total, cards: cards)
        return pdfFile(doc, name: "دفتر حساب - " + a.name + " - " + Self.todayTag() + ".pdf")
    }

    func personalPDF(range: DateRange?) -> ExportFile? {
        let all = state["personalExpenses"]?.arrayValue ?? []
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let total = list.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let d = expenseDoc(title: "", records: list, showPay: true)
        var cards: [PDFInfoCard] = []
        if personalBudget > 0 { cards.append(budgetCard(budget: personalBudget, spent: all.reduce(0) { $0 + ImportAnalyzer.toman($1) })) }
        let doc = PDFDoc(title: "گزارش هزینه‌های شخصی",
                         subtitle: "گزارش هزینه‌ها — تا تاریخ " + BackupExporter.formatJalali(Self.today) + (range != nil ? " · " + rangeText(range) : ""),
                         legend: d.legend, columns: d.cols, rows: d.rows, emptyText: "هیچ هزینه‌ای ثبت نشده",
                         totalLabel: "جمع کل هزینه‌ها تا امروز (تومان)", total: total, cards: cards)
        return pdfFile(doc, name: "هزینه‌های شخصی - " + Self.todayTag() + ".pdf")
    }

    func incomePDF(range: DateRange?) -> ExportFile? {
        let all = state["incomes"]?.arrayValue ?? []
        let list = sortedRecords(range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["date"])) } } ?? all)
        let total = list.reduce(0) { $0 + ImportAnalyzer.toman($1) }
        let d = expenseDoc(title: "", records: list, showPay: false)
        let doc = PDFDoc(title: "گزارش درآمد",
                         subtitle: "گزارش درآمد — تا تاریخ " + BackupExporter.formatJalali(Self.today) + (range != nil ? " · " + rangeText(range) : ""),
                         legend: [], columns: d.cols, rows: d.rows, emptyText: "هیچ درآمدی ثبت نشده",
                         totalLabel: "جمع کل درآمدها (تومان)", total: total)
        return pdfFile(doc, name: "درآمد - " + Self.todayTag() + ".pdf")
    }

    func remindersPDF(range: DateRange?) -> ExportFile? {
        let all = state["reminderChecks"]?.arrayValue ?? []
        let filtered = range.map { r in all.filter { r.contains(ImportAnalyzer.date($0["dueDate"])) } } ?? all
        let list = filtered.enumerated().sorted { a, b in
            let da = ImportAnalyzer.date(a.element["dueDate"]), db = ImportAnalyzer.date(b.element["dueDate"])
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        let status = ["pending": "در انتظار وصول", "cashed": "وصول شد", "bounced": "برگشت خورد", "cancelled": "باطل شد"]
        let cols = [PDFColumn(title: "#", kind: .index, width: 0.45), PDFColumn(title: "سررسید", kind: .date, width: 1.25),
                    PDFColumn(title: "طرف حساب", kind: .category, width: 1.6), PDFColumn(title: "بانک / شماره", kind: .sub, width: 1.4),
                    PDFColumn(title: "وضعیت", kind: .sub, width: 1.1), PDFColumn(title: "توضیحات", kind: .text, width: 2.6),
                    PDFColumn(title: "مبلغ (تومان)", kind: .amount, width: 1.45)]
        let rows = list.enumerated().map { i, c -> PDFRow in
            let bank = [c["bankName"]?.stringValue ?? "", (c["checkNumber"]?.idString).map { "#" + Money.persianDigits($0) } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            let st = c["status"]?.stringValue ?? ""
            let desc = [c["description"]?.stringValue ?? "", c["category"]?.stringValue ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
            return PDFRow(cells: [PDFCell(text: Money.persianDigits(i + 1)), PDFCell(text: Self.pdfDate(ImportAnalyzer.date(c["dueDate"]))),
                                  PDFCell(text: c["party"]?.stringValue ?? "—"), PDFCell(text: bank.isEmpty ? "—" : bank),
                                  PDFCell(text: status[st] ?? st), PDFCell(text: desc),
                                  PDFCell(text: Money.persianDigits(Money.format(c["amount"]?.intValue ?? 0)))],
                          tint: st == "cashed" ? UIColor(red: 0.86, green: 0.95, blue: 0.90, alpha: 0.9)
                              : (st == "bounced" ? UIColor(red: 0.98, green: 0.88, blue: 0.88, alpha: 0.9) : nil))
        }
        let doc = PDFDoc(title: "گزارش چک‌ها", subtitle: "تا تاریخ " + BackupExporter.formatJalali(Self.today) + (range != nil ? " · " + rangeText(range) : ""),
                         legend: [], columns: cols, rows: rows, emptyText: "هیچ چکی ثبت نشده",
                         totalLabel: "جمع مبلغ چک‌ها (تومان)", total: list.reduce(0) { $0 + ($1["amount"]?.intValue ?? 0) })
        return pdfFile(doc, name: "چک‌ها - " + Self.todayTag() + ".pdf")
    }
}
