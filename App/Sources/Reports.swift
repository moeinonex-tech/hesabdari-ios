import SwiftUI
import UIKit
import Charts
import HesabCore

// MARK: - PDF (A4, right-to-left table, page numbers "صفحه i از n" like the web exports)

struct PDFTable {
    var title: String
    var subtitle: String
    var info: [(String, String)]
    var header: [String]
    var widths: [CGFloat]            // relative
    var rows: [[String]]
    var totalRow: [String]?
}

enum PDFMaker {
    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 32

    static func font(_ name: String, _ size: CGFloat) -> UIFont { UIFont(name: name, size: size) ?? .systemFont(ofSize: size) }

    static func attr(_ s: String, size: CGFloat, bold: Bool = false, color: UIColor = .black, align: NSTextAlignment = .right) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.baseWritingDirection = .rightToLeft
        p.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: s, attributes: [.font: font(bold ? "Vazirmatn-Bold" : "Vazirmatn-Regular", size),
                                                          .foregroundColor: color, .paragraphStyle: p])
    }

    static func make(_ t: PDFTable) -> Data {
        let contentWidth = page.width - margin * 2
        let total = t.widths.reduce(0, +)
        let colW = t.widths.map { $0 / total * contentWidth }
        let cellPad: CGFloat = 5
        func rowHeight(_ cells: [String], bold: Bool) -> CGFloat {
            var h: CGFloat = 18
            for (i, c) in cells.enumerated() where i < colW.count {
                let r = attr(c, size: 9, bold: bold).boundingRect(with: CGSize(width: colW[i] - cellPad * 2, height: 2000),
                                                                  options: [.usesLineFragmentOrigin], context: nil)
                h = max(h, ceil(r.height) + 8)
            }
            return h
        }
        // layout pass: page breaks
        let headerH = rowHeight(t.header, bold: true)
        let firstTop: CGFloat = margin + 110
        let top: CGFloat = margin + 30
        let bottom = page.height - margin - 26
        var pages: [[Int]] = [[]]
        var y = firstTop + headerH
        let allRows = t.rows + (t.totalRow.map { [$0] } ?? [])
        for (i, r) in allRows.enumerated() {
            let h = rowHeight(r, bold: i == t.rows.count)
            if y + h > bottom { pages.append([]); y = top + headerH }
            pages[pages.count - 1].append(i)
            y += h
        }
        let n = pages.count
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            for (pi, rowsOnPage) in pages.enumerated() {
                ctx.beginPage()
                var y: CGFloat
                if pi == 0 {
                    attr(t.title, size: 18, bold: true).draw(in: CGRect(x: margin, y: margin, width: contentWidth, height: 28))
                    attr(t.subtitle, size: 10, color: .darkGray).draw(in: CGRect(x: margin, y: margin + 28, width: contentWidth, height: 16))
                    var iy = margin + 50
                    for (k, v) in t.info.prefix(4) {
                        attr(k + ": " + v, size: 10).draw(in: CGRect(x: margin, y: iy, width: contentWidth, height: 15))
                        iy += 15
                    }
                    y = firstTop
                } else {
                    attr(t.title, size: 11, bold: true, color: .darkGray).draw(in: CGRect(x: margin, y: margin, width: contentWidth, height: 18))
                    y = top
                }
                drawRow(t.header, y: y, h: headerH, colW: colW, bold: true, fill: UIColor(white: 0.9, alpha: 1), pad: cellPad)
                y += headerH
                for (k, i) in rowsOnPage.enumerated() {
                    let isTotal = i == t.rows.count
                    let r = allRows[i]
                    let h = rowHeight(r, bold: isTotal)
                    drawRow(r, y: y, h: h, colW: colW, bold: isTotal,
                            fill: isTotal ? UIColor(white: 0.86, alpha: 1) : (k % 2 == 1 ? UIColor(white: 0.97, alpha: 1) : nil), pad: cellPad)
                    y += h
                }
                let footer = "صفحه " + Money.persianDigits(pi + 1) + " از " + Money.persianDigits(n)
                attr(footer, size: 9, color: .gray, align: .center)
                    .draw(in: CGRect(x: margin, y: page.height - margin - 14, width: contentWidth, height: 14))
            }
        }
    }

    static func drawRow(_ cells: [String], y: CGFloat, h: CGFloat, colW: [CGFloat], bold: Bool, fill: UIColor?, pad: CGFloat) {
        let width = colW.reduce(0, +)
        if let f = fill {
            f.setFill()
            UIBezierPath(rect: CGRect(x: margin, y: y, width: width, height: h)).fill()
        }
        var x = page.width - margin          // right to left
        for (i, w) in colW.enumerated() {
            x -= w
            let text = i < cells.count ? cells[i] : ""
            let align: NSTextAlignment = text.range(of: #"^[۰-۹0-9.,\s]+(تومان|ریال)?$"#, options: .regularExpression) != nil ? .center : .right
            attr(text, size: 9, bold: bold, align: align).draw(in: CGRect(x: x + pad, y: y + 4, width: w - pad * 2, height: h - 6))
            UIColor(white: 0.8, alpha: 1).setStroke()
            let p = UIBezierPath(rect: CGRect(x: x, y: y, width: w, height: h))
            p.lineWidth = 0.4
            p.stroke()
        }
    }
}

// MARK: - files

extension AppModel {
    func exportFile(name: String, data: Data) -> ExportFile? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return ExportFile(url: url)
        } catch {
            errorMessage = "فایل ساخته نشد: \(error.localizedDescription)"
            return nil
        }
    }

    func rangeText(_ r: DateRange?) -> String {
        guard let r else { return "همه‌ی تاریخ‌ها" }
        return "از " + BackupExporter.formatJalali(r.from) + " تا " + BackupExporter.formatJalali(r.to)
    }

    static func todayTag() -> String { let t = today; return Money.persianDigits("\(t.jy)-\(t.jm)-\(t.jd)") }

    /// Rows → PDF table, dropping the rial column (A4 width), keeping the web column order.
    func pdf(_ title: String, rows: [[ExportCell]], widths: [CGFloat], info: [(String, String)], dropRial: Bool = true) -> Data {
        var cells = rows.map { $0.map(\.display) }
        let header = cells.first ?? []
        let rialIndex = header.firstIndex(of: "مبلغ (ریال)")
        if dropRial, let ri = rialIndex { cells = cells.map { r in r.enumerated().filter { $0.offset != ri }.map(\.element) } }
        let body = Array(cells.dropFirst().dropLast())
        let total = cells.count > 1 ? cells.last : nil
        return PDFMaker.make(PDFTable(title: title, subtitle: "دفتر حساب · ساخته‌شده در " + BackupExporter.formatJalali(Self.today),
                                      info: info, header: cells.first ?? [], widths: widths, rows: body, totalRow: total))
    }


    func ledgerExcel(accountIds: [String], range: DateRange?) -> ExportFile? {
        let sheets = accountIds.compactMap { id -> (name: String, rows: [[ExportCell]])? in
            guard let a = accounts.first(where: { $0.id == id }) else { return nil }
            return (a.name, ExportBuilder.ledger(state, accountId: id, range: range))
        }
        let name = accountIds.count == 1 ? (accounts.first { $0.id == accountIds[0] }?.name ?? "دفتر") : "همه‌ی دفترها"
        return exportFile(name: "دفتر حساب - " + name + " - " + Self.todayTag() + ".xlsx", data: XLSXWriter.make(sheets: sheets))
    }

    func personalExcel(range: DateRange?) -> ExportFile? {
        exportFile(name: "هزینه‌های شخصی - " + Self.todayTag() + ".xlsx",
                   data: XLSXWriter.make(sheets: [("هزینه‌های شخصی", ExportBuilder.personal(state, range: range))]))
    }
    func incomeExcel(range: DateRange?) -> ExportFile? {
        exportFile(name: "درآمد - " + Self.todayTag() + ".xlsx",
                   data: XLSXWriter.make(sheets: [("درآمد", ExportBuilder.income(state, range: range))]))
    }
    func remindersExcel(range: DateRange?) -> ExportFile? {
        exportFile(name: "یادآوری‌ها - " + Self.todayTag() + ".xlsx",
                   data: XLSXWriter.make(sheets: [("چک‌ها", ExportBuilder.checks(state, range: range)),
                                                  ("اشخاص", ExportBuilder.persons(state, range: range))]))
    }

    /// Monthly totals for the last 12 Jalali months (for charts).
    func monthly(_ items: [(JalaliDate, Int)]) -> [(label: String, total: Int)] {
        let t = Self.today
        var keys: [(Int, Int)] = []
        var y = t.jy, m = t.jm
        for _ in 0..<12 { keys.insert((y, m), at: 0); m -= 1; if m == 0 { m = 12; y -= 1 } }
        return keys.map { k in
            let total = items.filter { $0.0.jy == k.0 && $0.0.jm == k.1 }.reduce(0) { $0 + $1.1 }
            return (BackupExporter.months[k.1 - 1], total)
        }
    }
}

// MARK: - reports screen

struct MonthBar: Identifiable {
    let id = UUID()
    let label: String
    let series: String
    let total: Int
}

struct ReportsView: View {
    @ObservedObject var model: AppModel
    @Binding var scope: Int
    @Environment(\.theme) private var t
    @State private var useRange = false
    @State private var from = JalaliDate(jy: AppModel.today.jy, jm: 1, jd: 1)
    @State private var to = AppModel.today
    @State private var account: String?
    @State private var share: ExportFile?
    @State private var makingPDF = false

    private var range: DateRange? { useRange ? DateRange(from: from, to: to) : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "گزارش‌ها", subtitle: "نمودارها و خروجی PDF و Excel")
                HScroll {
                    HStack(spacing: 8) {
                        ForEach(Array(["کلی", "دفتر حساب", "شخصی", "درآمد", "یادآوری‌ها"].enumerated()), id: \.offset) { i, name in
                            Button {
                                Haptics.tap()
                                withAnimation(.snappy) { scope = i }
                            } label: {
                                Text(name).font(AppFont.bold(14)).padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(scope == i ? t.onAccent : t.ink)
                                    .background(scope == i ? t.accent : t.card.opacity(0.7), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if scope != 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("فقط یک بازه‌ی تاریخ", isOn: $useRange.animation())
                        if useRange {
                            JalaliDateField(title: "از", date: $from)
                            JalaliDateField(title: "تا", date: $to)
                        }
                    }
                    .font(AppFont.regular(14))
                    .glassCard()
                }

                switch scope {
                case 0: overview
                case 1: ledgerReport
                case 2: listReport(personal: true)
                case 3: listReport(personal: false)
                default: remindersReport
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(AppBackground())
        .scrollsToTopOnDockTap(.reports)
        .pageSwipe($scope, [0, 1, 2, 3, 4])
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scope) { _, _ in account = nil }
        .sheet(item: $share) { f in ActivityView(items: [f.url]) }
    }

    // overview

    private var overview: some View {
        let ledgerTotal = model.accounts.reduce(0) { $0 + $1.expenseTotal }
        let personal = model.personalRows.reduce(0) { $0 + $1.toman }
        let income = model.incomeRows.reduce(0) { $0 + $1.toman }
        var bars: [MonthBar] = []
        let ledgerItems = (model.state["expenses"]?.arrayValue ?? []).filter { $0["type"]?.stringValue != "tankhah" }
            .map { (ImportAnalyzer.date($0["date"]), ImportAnalyzer.toman($0)) }
        for m in model.monthly(ledgerItems) { bars.append(MonthBar(label: m.label, series: "دفتر حساب", total: m.total)) }
        for m in model.monthly(model.personalRows.map { ($0.dateValue, $0.toman) }) { bars.append(MonthBar(label: m.label, series: "شخصی", total: m.total)) }
        return VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryTile(title: "هزینه‌ی دفترها", value: ledgerTotal, color: t.accent)
                SummaryTile(title: "هزینه‌ی شخصی", value: personal, color: t.accent2)
                SummaryTile(title: "درآمد", value: income, color: t.success)
                SummaryTile(title: "بدهی من", value: model.iOwe, color: t.danger)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "هزینه‌ها در ۱۲ ماه اخیر")
                Chart(bars) { b in
                    BarMark(x: .value("ماه", b.label), y: .value("مبلغ", b.total))
                        .foregroundStyle(by: .value("بخش", b.series))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(["دفتر حساب": t.accent, "شخصی": t.accent2])
                .chartYAxis { AxisMarks { _ in AxisGridLine() } }
                .frame(height: 220)
            }
            .glassCard()
            let ac = ReportCharts.accountsCompare(model.accounts)
            if ac.count >= 2 { CompareBarCard(title: "مقایسه‌ی هزینه‌ی دفترها", data: ac, color: t.accent) }
            let cc = ReportCharts.commissionCompare(model.accounts)
            if !cc.isEmpty { CompareBarCard(title: "کمیسیون تعلق‌گرفته‌ی هر دفتر (تا امروز)", data: cc, color: t.accent2) }
            ForEach(model.accounts.filter { $0.commissionEnabled || $0.percent != 0 }) { a in
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "کمیسیون — " + a.name)
                    LabeledContent("پرداخت‌شده", value: Fmt.toman(a.settled))
                    LabeledContent("مانده", value: Fmt.balance(a.remaining))
                }
                .font(AppFont.regular(14))
                .glassCard()
            }
        }
    }

    // ledger

    private var ledgerReport: some View {
        let id = account ?? model.activeAccountId ?? ""
        let rows = model.rows(accountId: id).filter { r in range.map { $0.contains(r.dateValue) } ?? true }
        let items = rows.filter { $0.kind != .tankhah }.map { ($0.dateValue, $0.toman) }
        return VStack(alignment: .leading, spacing: 16) {
            if model.accounts.count > 1 {
                Segmented(selection: Binding(get: { id }, set: { account = $0 }), model.accounts.map { ($0.id, $0.name) })
            }
            monthChart(items, color: t.accent)
            TrendChartCard(title: "نمودار نوسانات هزینه‌ی دفتر", items: ReportCharts.ledgerExpenses(model.state, accountId: id), color: t.accent)
            CashFlowCard(income: ReportCharts.ledgerIncomes(model.state, accountId: id), expense: ReportCharts.ledgerExpenses(model.state, accountId: id))
            ComparisonCard(title: "درآمد در برابر هزینه — " + (model.accounts.first { $0.id == id }?.name ?? ""),
                           c: ReportCharts.comparisonLedger(model.state, accountId: id))
            let st = model.statItems("expenses", accountId: id, range: range)
            let s = model.breakdown(st, kind: .expense)
            let sub = model.breakdown(st, kind: .expense, sub: true)
            let scope = model.accounts.first { $0.id == id }?.name ?? "دفتر حساب"
            if !s.isEmpty { CategoryChartCard(slices: s, subs: sub, model: model, scope: scope) }
            if !sub.isEmpty { SubcategoryChartCard(slices: sub, model: model, scope: scope) }
            exportButtons(pdf: { await model.ledgerPDF(accountId: id, range: range) },
                          excel: { model.ledgerExcel(accountIds: [id], range: range) },
                          extra: model.accounts.count > 1 ? ("Excel همه‌ی دفترها", { model.ledgerExcel(accountIds: model.accounts.map(\.id), range: range) }) : nil)
        }
    }

    private func listReport(personal: Bool) -> some View {
        let rows = (personal ? model.personalRows : model.incomeRows).filter { r in range.map { $0.contains(r.dateValue) } ?? true }
        return VStack(alignment: .leading, spacing: 16) {
            monthChart(rows.map { ($0.dateValue, $0.toman) }, color: personal ? t.accent2 : t.success)
            TrendChartCard(title: personal ? "نمودار نوسانات هزینه‌ی شخصی" : "نمودار نوسانات درآمد",
                           items: personal ? ReportCharts.personalExpenses(model.state) : ReportCharts.allIncomes(model.state),
                           color: personal ? t.accent2 : t.success)
            ComparisonCard(title: "درآمد شخصی در برابر هزینه شخصی", c: ReportCharts.comparisonPersonal(model.state))
            let st = model.statItems(personal ? "personalExpenses" : "incomes", range: range)
            let s = model.breakdown(st, kind: personal ? .expense : .income)
            let sub = model.breakdown(st, kind: personal ? .expense : .income, sub: true)
            let scope = personal ? "دفتر شخصی" : "درآمد"
            if !s.isEmpty { CategoryChartCard(slices: s, subs: sub, model: model, scope: scope) }
            if !sub.isEmpty { SubcategoryChartCard(slices: sub, model: model, scope: scope) }
            exportButtons(pdf: { personal ? await model.personalPDF(range: range) : await model.incomePDF(range: range) },
                          excel: { personal ? model.personalExcel(range: range) : model.incomeExcel(range: range) }, extra: nil)
        }
    }

    private var remindersReport: some View {
        let checks = model.checks.filter { c in range.map { $0.contains(c.due) } ?? true }
        let groups: [(String, Int, Color)] = [
            ("در انتظار وصول", checks.filter { $0.status == "pending" }.reduce(0) { $0 + $1.amount }, t.warning),
            ("وصول‌شده", checks.filter { $0.status == "cashed" }.reduce(0) { $0 + $1.amount }, t.success),
            ("برگشتی/باطل", checks.filter { $0.status == "bounced" || $0.status == "cancelled" }.reduce(0) { $0 + $1.amount }, t.danger)
        ].filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SummaryTile(title: "طلب من", value: model.owedToMe, color: t.success)
                SummaryTile(title: "بدهی من", value: model.iOwe, color: t.danger)
            }
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "گزارش چک‌ها (" + Fmt.count(checks.count) + " چک)")
                    Chart(Array(groups.enumerated()), id: \.offset) { _, g in
                        SectorMark(angle: .value("مبلغ", g.1), innerRadius: .ratio(0.6), angularInset: 1.5).foregroundStyle(g.2)
                    }
                    .frame(height: 170)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        HStack {
                            Circle().fill(g.2).frame(width: 8, height: 8)
                            Text(g.0).font(AppFont.regular(13))
                            Spacer()
                            Text(Fmt.toman(g.1)).font(AppFont.bold(13))
                        }
                    }
                }
                .glassCard()
            }
            exportButtons(pdf: { await model.remindersPDF(range: range) }, excel: { model.remindersExcel(range: range) }, extra: nil)
        }
    }

    // pieces

    private func monthChart(_ items: [(JalaliDate, Int)], color: Color) -> some View {
        let data = model.monthly(items).map { MonthBar(label: $0.label, series: "", total: $0.total) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "۱۲ ماه اخیر")
            Chart(data) { b in
                BarMark(x: .value("ماه", b.label), y: .value("مبلغ", b.total))
                    .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .cornerRadius(4)
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine() } }
            .frame(height: 200)
        }
        .glassCard()
    }

    private func exportButtons(pdf: @escaping () async -> ExportFile?, excel: @escaping () -> ExportFile?,
                               extra: (String, () -> ExportFile?)?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    guard !makingPDF else { return }
                    makingPDF = true
                    Task { @MainActor in
                        share = await pdf()
                        makingPDF = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if makingPDF { ProgressView().tint(.white) } else { Image(systemName: "doc.richtext") }
                        Text(makingPDF ? "در حال ساخت…" : "PDF")
                    }
                    .font(AppFont.bold(15)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                Button { share = excel() } label: {
                    Label("Excel", systemImage: "tablecells").font(AppFont.bold(15)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            if let e = extra {
                Button { share = e.1() } label: {
                    Label(e.0, systemImage: "square.stack.3d.up").font(AppFont.medium(14)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }
}
