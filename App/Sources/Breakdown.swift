import SwiftUI
import Charts
import HesabCore

// Category / subcategory breakdown — web renderCategoryBreakdown + renderSubcatRanking:
// multi-item rows are split into their items (expandItemsForCategoryStats), totals are ranked biggest-first,
// and the colour follows the rank in the web palettes (DONUT_COLORS / GREEN_DONUT_COLORS).
// The web palette has 10 colours and repeats after that; here every category and every subcategory gets its own
// colour — the first 10 are exactly the web ones, the rest are new, evenly spread hues.

struct StatItem {
    let category: String
    let subcategory: String
    let toman: Int
}

enum BreakKind { case expense, income }

enum CategoryPalette {
    static let expense: [UInt32] = [0xFF3366, 0xFF7A00, 0xFFC400, 0x8B5CF6, 0x0A84FF, 0x00C2B8, 0x22C55E, 0xEC4899, 0x6366F1, 0x64748B]
    static let income: [UInt32] = [0x22C55E, 0x0D9488, 0xA3E635, 0x166534, 0x5EEAD4, 0x65A30D, 0x34D399, 0x134E4A, 0x84CC16, 0x047857]
    static let none = Color.hex(0x8A8F99)

    static func color(rank: Int, kind: BreakKind) -> Color {
        let base = kind == .income ? income : expense
        if rank < base.count { return Color.hex(base[rank]) }
        // beyond the web palette: golden-angle hues never repeat; income stays in the green–teal family
        let n = Double(rank - base.count)
        if kind == .income {
            let hue = 0.25 + (n * 0.618).truncatingRemainder(dividingBy: 1) * 0.25
            return Color(hue: hue, saturation: 0.65, brightness: 0.55 + (n.truncatingRemainder(dividingBy: 3)) * 0.15)
        }
        let hue = (0.05 + n * 0.381966).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.62 + (n.truncatingRemainder(dividingBy: 2)) * 0.18,
                     brightness: 0.92 - (n.truncatingRemainder(dividingBy: 3)) * 0.12)
    }
}

extension AppModel {
    /// rows of one list as stat items (web expandItemsForCategoryStats); tankhah rows are not expenses
    func statItems(_ key: String, accountId: String? = nil, range: DateRange? = nil) -> [StatItem] {
        var out: [StatItem] = []
        for e in state[key]?.arrayValue ?? [] {
            if let a = accountId, e["accountId"]?.idString != a { continue }
            if key == "expenses" && e["type"]?.stringValue == "tankhah" { continue }
            if let r = range, !r.contains(ImportAnalyzer.date(e["date"])) { continue }
            if let items = e["items"]?.arrayValue, !items.isEmpty {
                for it in items {
                    out.append(StatItem(category: it["category"]?.stringValue ?? "", subcategory: it["subcategory"]?.stringValue ?? "",
                                        toman: ImportAnalyzer.toman(it)))
                }
            } else {
                out.append(StatItem(category: e["category"]?.stringValue ?? "", subcategory: e["subcategory"]?.stringValue ?? "",
                                    toman: ImportAnalyzer.toman(e)))
            }
        }
        return out
    }

    /// ranked slices with their own colour; sub = by subcategory (rows without one are left out, as on the web)
    func breakdown(_ items: [StatItem], kind: BreakKind, sub: Bool = false) -> [CategorySlice] {
        var sums: [String: Int] = [:]
        var order: [String] = []
        for it in items {
            let raw = (sub ? it.subcategory : it.category).trimmingCharacters(in: .whitespaces)
            if sub && raw.isEmpty { continue }
            let name = raw.isEmpty ? "بدون دسته" : raw
            if sums[name] == nil { order.append(name) }
            sums[name, default: 0] += it.toman
        }
        // JS sort is stable: equal totals keep first-seen order
        let ranked = order.enumerated().sorted { a, b in
            let x = sums[a.element]!, y = sums[b.element]!
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        var rank = 0
        return ranked.map { name in
            let color: Color
            if name == "بدون دسته" { color = CategoryPalette.none } else { color = CategoryPalette.color(rank: rank, kind: kind); rank += 1 }
            return CategorySlice(name: name, total: sums[name]!, color: color)
        }
    }

    func colorMap(_ slices: [CategorySlice]) -> [String: Color] {
        Dictionary(slices.map { ($0.name, $0.color) }, uniquingKeysWith: { a, _ in a })
    }
}

private func percent(_ v: Int, _ total: Int) -> String {
    Money.persianDigits(total > 0 ? Money.jsRound(Double(v) / Double(total) * 100) : 0) + "٪"
}

private struct Donut: View {
    let slices: [CategorySlice]
    let label: String
    let side: CGFloat
    let highlight: Int?          // the slice the «clock hand» is on
    @Environment(\.theme) private var t
    var body: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { i, s in
            // the slice under the «clock hand» grows outward; nothing fades
            SectorMark(angle: .value("مبلغ", s.total),
                       innerRadius: .ratio(i == highlight ? 0.5 : 0.6),
                       outerRadius: .ratio(i == highlight ? 1.0 : 0.84),
                       angularInset: 1.2)
                .cornerRadius(3)
                .foregroundStyle(s.color)
        }
        .chartLegend(.hidden)
        .frame(width: side, height: side)
        .overlay {
            VStack(spacing: 0) {
                if let h = highlight, h < slices.count {
                    // the hand only counts: 1, 2, 3 … n
                    Text(Money.persianDigits(String(h + 1))).font(AppFont.heavy(26)).foregroundStyle(slices[h].color)
                        .contentTransition(.numericText(value: Double(h)))
                    Text("از " + Fmt.count(slices.count)).font(AppFont.caption).foregroundStyle(t.soft)
                } else {
                    Text(Fmt.count(slices.count)).font(AppFont.heavy(20)).foregroundStyle(t.ink)
                    Text(label).font(AppFont.caption).foregroundStyle(t.soft)
                }
            }
        }
    }
}

private struct BreakdownRow: View {
    let s: CategorySlice
    let max: Int
    let total: Int
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(s.color).frame(width: 9, height: 9)
                Text(s.name).font(AppFont.medium(13)).foregroundStyle(t.ink).lineLimit(1)
                Spacer(minLength: 6)
                Text(Money.persianDigits(Money.format(s.total))).font(AppFont.bold(12)).foregroundStyle(t.ink)
                Text(percent(s.total, total)).font(AppFont.bold(11)).foregroundStyle(t.soft).frame(minWidth: 30, alignment: .trailing)
            }
            GeometryReader { g in
                Capsule().fill(t.ink.opacity(0.06))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [s.color.opacity(0.6), s.color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: Swift.max(6, g.size.width * (max > 0 ? Swift.max(0.04, Double(s.total) / Double(max)) : 0)))
                    }
            }
            .frame(height: 6)
        }
    }
}

/// Ring + the top 5; a tap unfolds the rest with a spring, and the ring's «clock hand» sweeps once
/// over every slice (each one grows as the hand passes) and stops after the last.
struct BreakdownCard: View {
    let title: String
    let unit: String
    let slices: [CategorySlice]
    /// PDF of this chart; the Bool asks for the subcategories in the same file (category card only)
    var export: ((Bool) async -> ExportFile?)? = nil
    var canAddSubs = false
    @State private var open = false
    @State private var share: ExportFile?
    @State private var building = false
    @State private var hand: Int?
    @State private var sweep: Task<Void, Never>?
    @Environment(\.theme) private var t
    private let topCount = 5

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.total }
        let mx = slices.map(\.total).max() ?? 0
        let more = slices.count > topCount
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: title)
                Spacer()
                if export != nil { pdfMenu }
                if more {
                    HStack(spacing: 4) {
                        Text(open ? "بستن" : "همه (" + Fmt.count(slices.count) + ")").font(AppFont.medium(12))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .foregroundStyle(t.soft)
                }
            }
            HStack {
                Spacer()
                Donut(slices: slices, label: unit, side: 150, highlight: hand)
                Spacer()
            }
            VStack(spacing: 10) {
                ForEach(Array(slices.prefix(open ? slices.count : topCount).enumerated()), id: \.element.id) { i, s in
                    BreakdownRow(s: s, max: mx, total: total)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity)
                                .animation(.spring(duration: 0.45, bounce: 0.25).delay(Double(Swift.max(0, min(i - topCount, 12))) * 0.025)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
            }
        }
        .glassCard()
        .contentShape(Rectangle())
        .onTapGesture {
            guard more || slices.count > 1 else { return }
            Haptics.tap()
            if more { withAnimation(.spring(duration: 0.45, bounce: 0.25)) { open.toggle() } }
            runSweep()
        }
        .onDisappear { sweep?.cancel() }
        .sheet(item: $share) { f in ActivityView(items: [f.url]) }
    }

    @ViewBuilder private var pdfMenu: some View {
        if building {
            ProgressView().controlSize(.small).padding(.horizontal, 6)
        } else if canAddSubs {
            Menu {
                Button { make(false) } label: { Label("PDF فقط دسته‌ها", systemImage: "doc.richtext") }
                Button { make(true) } label: { Label("PDF دسته‌ها + زیردسته‌ها", systemImage: "doc.on.doc") }
            } label: { pdfIcon }
        } else {
            Button { make(false) } label: { pdfIcon }.buttonStyle(.plain)
        }
    }

    private var pdfIcon: some View {
        Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(t.accent)
            .frame(width: 32, height: 28).contentShape(Rectangle())
    }

    private func make(_ subs: Bool) {
        guard let export, !building else { return }
        Haptics.tap()
        building = true
        Task { @MainActor in
            share = await export(subs)
            building = false
        }
    }

    /// clockwise pass over the slices: about 0.8 s in total, 40–110 ms per slice
    private func runSweep() {
        sweep?.cancel()
        let n = slices.count
        guard n > 0 else { return }
        let step = UInt64(Swift.min(110, Swift.max(40, 800 / n))) * 1_000_000
        sweep = Task { @MainActor in
            for i in 0..<n {
                if Task.isCancelled { return }
                withAnimation(.spring(duration: 0.22, bounce: 0.3)) { hand = i }
                if i % 2 == 0 { UISelectionFeedbackGenerator().selectionChanged() }
                try? await Task.sleep(nanoseconds: step)
            }
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) { hand = nil }
        }
    }
}

struct CategoryChartCard: View {
    let slices: [CategorySlice]
    var subs: [CategorySlice] = []
    var model: AppModel? = nil
    var scope = ""
    var body: some View {
        BreakdownCard(title: "تفکیک دسته‌ها", unit: "دسته", slices: slices,
                      export: model.map { m in { withSubs in await m.breakdownPDF(scopeTitle: scope, cats: slices, subs: withSubs ? subs : nil) } },
                      canAddSubs: !subs.isEmpty)
    }
}

struct SubcategoryChartCard: View {
    let slices: [CategorySlice]
    var model: AppModel? = nil
    var scope = ""
    var body: some View {
        BreakdownCard(title: "تفکیک زیردسته‌ها", unit: "زیردسته", slices: slices,
                      export: model.map { m in { _ in await m.breakdownPDF(scopeTitle: scope, cats: slices, subs: nil, firstIsSub: true) } })
    }
}
