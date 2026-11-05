import SwiftUI
import Charts
import HesabCore

/// web «نمودار نوسانات»: monthly / daily (with a month picker) / yearly bars.
struct TrendChartCard: View {
    let title: String
    let items: [ReportCharts.Item]
    let color: Color
    @Environment(\.theme) private var t
    @State private var mode = 0           // 0 monthly, 1 daily, 2 yearly
    @State private var monthKey: Int?

    var body: some View {
        let months = ReportCharts.monthly(items)
        let key = monthKey.flatMap { k in months.contains { $0.jy * 100 + $0.jm == k } ? k : nil } ?? months.last.map { $0.jy * 100 + $0.jm }
        let data: [ChartPoint] = {
            switch mode {
            case 1: return key.map { ReportCharts.daily(items, jy: $0 / 100, jm: $0 % 100) } ?? []
            case 2: return ReportCharts.yearly(items)
            default: return months
            }
        }()
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            Segmented(selection: $mode.animation(.snappy), [(0, "ماهانه"), (1, "روزانه"), (2, "سالانه")])
            if mode == 1, !months.isEmpty {
                Picker("ماه", selection: Binding(get: { key ?? 0 }, set: { monthKey = $0 })) {
                    ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                        Text(BackupExporter.months[m.jm - 1] + " " + Money.persianDigits(String(m.jy))).tag(m.jy * 100 + m.jm)
                    }
                }
                .pickerStyle(.menu)
            }
            if data.isEmpty {
                Text("هنوز داده‌ای برای نمودار نیست").font(AppFont.regular(13)).foregroundStyle(t.soft).frame(maxWidth: .infinity).padding(16)
            } else {
                let yMax = Double(max(1, data.map(\.value).max() ?? 1)) * 1.12
                HScroll {
                  Revealing(count: data.count, glow: color) { lv in
                    Chart(Array(data.enumerated()), id: \.offset) { i, p in
                        BarMark(x: .value("بازه", "\(i)|" + p.label), y: .value("مبلغ", Double(p.value) * lv(i)))
                            .foregroundStyle(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(4)
                    }
                    .chartYScale(domain: 0...yMax)
                    .chartXAxis {
                        AxisMarks { v in
                            AxisValueLabel { if let s = v.as(String.self) { Text(s.split(separator: "|").last.map(String.init) ?? "").font(AppFont.caption) } }
                        }
                    }
                    .chartYAxis { AxisMarks { _ in AxisGridLine() } }
                    .frame(width: max(300, CGFloat(data.count) * (mode == 1 ? 16 : 44)), height: 200)
                  }
                }
                .defaultScrollAnchor(.trailing)
            }
        }
        .glassCard()
    }
}

/// web «جریان نقدی — درآمد در برابر هزینه» for one ledger.
struct CashFlowCard: View {
    let income: [ReportCharts.Item]
    let expense: [ReportCharts.Item]
    @Environment(\.theme) private var t
    @State private var yearly = false

    var body: some View {
        let inc = income.reduce(0) { $0 + $1.toman }, exp = expense.reduce(0) { $0 + $1.toman }
        if inc > 0 || exp > 0 {
            let data = ReportCharts.cashFlow(income: income, expense: expense, yearly: yearly)
            let net = inc - exp
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "جریان نقدی — درآمد در برابر هزینه")
                HStack {
                    VStack(alignment: .leading) { Text("درآمد").font(AppFont.caption).foregroundStyle(t.soft); FxNumber(inc, Fmt.toman).font(AppFont.bold(13)).foregroundStyle(t.success) }
                    Spacer()
                    VStack(alignment: .leading) { Text("هزینه").font(AppFont.caption).foregroundStyle(t.soft); FxNumber(exp, Fmt.toman).font(AppFont.bold(13)).foregroundStyle(t.accent) }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("خالص").font(AppFont.caption).foregroundStyle(t.soft)
                        Text((net >= 0 ? "+" : "−") + Fmt.toman(abs(net))).font(AppFont.bold(13)).foregroundStyle(net >= 0 ? t.success : t.danger)
                    }
                }
                Segmented(selection: $yearly.animation(.snappy), [(false, "ماهانه"), (true, "سالانه")])
                let yMax = Double(max(1, data.map { max($0.income, $0.expense) }.max() ?? 1)) * 1.12
                Revealing(count: data.count) { lv in
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { i, p in
                        BarMark(x: .value("بازه", "\(i)|" + p.label), y: .value("مبلغ", Double(p.income) * lv(i)))
                            .foregroundStyle(by: .value("نوع", "درآمد"))
                            .position(by: .value("نوع", "درآمد"))
                            .cornerRadius(3)
                        BarMark(x: .value("بازه", "\(i)|" + p.label), y: .value("مبلغ", Double(p.expense) * lv(i)))
                            .foregroundStyle(by: .value("نوع", "هزینه"))
                            .position(by: .value("نوع", "هزینه"))
                            .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...yMax)
                .chartForegroundStyleScale(["درآمد": t.success, "هزینه": t.accent])
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { if let s = v.as(String.self) { Text(s.split(separator: "|").last.map(String.init) ?? "").font(AppFont.caption) } }
                    }
                }
                .chartYAxis { AxisMarks { _ in AxisGridLine() } }
                .frame(height: 210)
                }
            }
            .glassCard()
        }
    }
}

/// web buildBarChart for comparisons (accounts / commission).
struct CompareBarCard: View {
    let title: String
    let data: [(name: String, value: Int)]
    let color: Color
    @Environment(\.theme) private var t

    var body: some View {
        let maxV = max(1, data.map(\.value).max() ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            Revealing(count: data.count, glow: color) { lv in
            VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(d.name).font(AppFont.medium(13)).foregroundStyle(t.ink).lineLimit(1)
                        Spacer()
                        Text(Fmt.toman(d.value)).font(AppFont.bold(13)).foregroundStyle(t.ink)
                    }
                    GradientBar(value: Double(d.value) / Double(maxV) * lv(i), from: color, to: t.accent2)
                }
            }
            }
            }
        }
        .glassCard()
    }
}

/// web «درآمد در برابر هزینه» (personal or one ledger).
struct ComparisonCard: View {
    let title: String
    let c: Comparison
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            LabeledContent("درآمد", value: Fmt.toman(c.income))
            LabeledContent("هزینه", value: Fmt.toman(c.expense))
            LabeledContent("خالص", value: (c.net < 0 ? "−" : "") + Fmt.toman(abs(c.net)))
                .foregroundStyle(c.net >= 0 ? t.success : t.danger)
            LabeledContent("نسبت هزینه به درآمد", value: Money.persianDigits(String(c.pct)) + "٪")
            if c.income > 0 {
                Revealing(count: 1) { lv in
                    GradientBar(value: min(1, Double(c.expense) / Double(c.income)) * lv(0), from: t.accent, to: c.pct >= 80 ? t.warning : t.accent2)
                }
            }
        }
        .font(AppFont.regular(14))
        .glassCard()
    }
}
