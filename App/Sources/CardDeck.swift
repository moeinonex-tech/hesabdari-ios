import SwiftUI
import HesabCore

// Page cards that can be reordered, removed and added back (like the home widgets, without sizes).
// The layout lives on this phone (UserDefaults «deck.<page>»), not in the backup.
// Edit mode: every card becomes a compact tile that jiggles; drag a tile to move it, «−» removes it,
// «افزودن کارت» brings a removed one back, the header ✓ saves.

struct DeckCard: Identifiable {
    let id: String
    let title: String
    let icon: String
    let view: AnyView
    init<V: View>(_ id: String, _ title: String, _ icon: String, @ViewBuilder _ view: () -> V) {
        self.id = id; self.title = title; self.icon = icon; self.view = AnyView(view())
    }
}

struct DeckLayout: Codable, Equatable {
    var order: [String] = []
    var hidden: [String] = []

    /// cards in their saved order; new cards keep their default place
    func arranged(_ defaults: [String]) -> [String] {
        var out = order.filter { defaults.contains($0) }
        for (i, k) in defaults.enumerated() where !out.contains(k) {
            let prev = defaults[..<i].last { out.contains($0) }
            if let p = prev, let at = out.firstIndex(of: p) { out.insert(k, at: at + 1) } else { out.insert(k, at: 0) }
        }
        return out
    }
}

struct CardDeck: View {
    let cards: [DeckCard]
    @Binding var editing: Bool
    @AppStorage private var raw: String
    @Environment(\.theme) private var t

    @State private var liveOrder: [String]?
    @State private var dragKey: String?
    @State private var dragStart = 0
    @State private var dragY: CGFloat = 0

    private let tileH: CGFloat = 56
    private let gap: CGFloat = 10

    init(page: String, editing: Binding<Bool>, cards: [DeckCard]) {
        self.cards = cards
        _editing = editing
        _raw = AppStorage(wrappedValue: "", "deck." + page)
    }

    private var layout: DeckLayout {
        (try? JSONDecoder().decode(DeckLayout.self, from: Data(raw.utf8))) ?? DeckLayout()
    }
    private func save(_ l: DeckLayout) {
        if let d = try? JSONEncoder().encode(l), let s = String(data: d, encoding: .utf8) { raw = s }
    }
    private var visible: [String] {
        let l = layout
        return l.arranged(cards.map(\.id)).filter { !l.hidden.contains($0) }
    }
    private func card(_ k: String) -> DeckCard? { cards.first { $0.id == k } }

    var body: some View {
        if editing { editor } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(visible, id: \.self) { k in card(k)?.view }
            }
        }
    }

    // MARK: edit mode

    private var editor: some View {
        let order = liveOrder ?? visible
        let hiddenCards = cards.filter { layout.hidden.contains($0.id) }
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    if hiddenCards.isEmpty { Text("همه‌ی کارت‌ها روی صفحه‌اند") }
                    ForEach(hiddenCards) { c in
                        Button { add(c.id) } label: { Label(c.title, systemImage: c.icon) }
                    }
                } label: {
                    Label("افزودن کارت", systemImage: "plus").font(AppFont.bold(14)).padding(.horizontal, 6).padding(.vertical, 2)
                }
                .buttonStyle(.glass)
                Spacer()
            }
            Text("کارت‌ها را بکشید تا جابه‌جا شوند؛ با «−» از صفحه برمی‌دارید و با «افزودن کارت» برمی‌گردانید. برای ثبت، دکمه‌ی ✓ بالا را بزنید.")
                .font(AppFont.caption).foregroundStyle(t.soft).frame(maxWidth: .infinity, alignment: .leading)
            if order.isEmpty {
                Text("کارتی روی صفحه نیست").font(AppFont.regular(13)).foregroundStyle(t.soft).padding(20)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                let time = tl.date.timeIntervalSinceReferenceDate
                VStack(spacing: gap) {
                    ForEach(Array(order.enumerated()), id: \.element) { i, k in
                        if let c = card(k) {
                            tile(c, wobble: dragKey == k ? 0 : sin(time * 9 + Double(i) * 1.7) * 0.6)
                                .offset(y: dragKey == k ? CGFloat(dragStart - i) * (tileH + gap) + dragY : 0)
                                .zIndex(dragKey == k ? 1 : 0)
                                .gesture(drag(k, order))
                        }
                    }
                }
            }
        }
    }

    private func tile(_ c: DeckCard, wobble: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: c.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(t.accent).frame(width: 26)
            Text(c.title).font(AppFont.bold(14)).foregroundStyle(t.ink).lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.soft)
        }
        .padding(.horizontal, 16)
        .frame(height: tileH)
        .glassCard(padding: 0)
        .overlay(alignment: .topTrailing) {
            Button { remove(c.id) } label: {
                Image(systemName: "minus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(t.danger))
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
        }
        .rotationEffect(.degrees(wobble))
        .scaleEffect(dragKey == c.id ? 1.04 : 1)
        .shadow(color: .black.opacity(dragKey == c.id ? 0.25 : 0), radius: 12, y: 6)
        .contentShape(Rectangle())
    }

    private func drag(_ k: String, _ order: [String]) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                if dragKey == nil {
                    dragKey = k
                    dragStart = order.firstIndex(of: k) ?? 0
                    liveOrder = order
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                guard var o = liveOrder, dragKey == k else { return }
                // the lifted tile stays under the finger: its offset is measured from where it started (dragStart),
                // so it is right whichever slot it currently occupies
                dragY = v.translation.height
                let n = o.count
                let target = min(n - 1, max(0, dragStart + Int((v.translation.height / (tileH + gap)).rounded())))
                if let cur = o.firstIndex(of: k), cur != target {
                    o.remove(at: cur); o.insert(k, at: target)
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(duration: 0.28, bounce: 0.2)) { liveOrder = o }
                }
            }
            .onEnded { _ in
                if let o = liveOrder {
                    var l = layout
                    l.order = o + l.hidden
                    save(l)
                }
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    dragKey = nil; dragY = 0; liveOrder = nil
                }
            }
    }

    private func remove(_ k: String) {
        Haptics.warning()
        var l = layout
        l.order = visible + l.hidden.filter { $0 != k }
        if !l.hidden.contains(k) { l.hidden.append(k) }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { save(l) }
    }

    private func add(_ k: String) {
        Haptics.success()
        var l = layout
        l.hidden.removeAll { $0 == k }
        l.order = visible.filter { $0 != k } + [k] + l.hidden
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { save(l) }
    }
}

/// the round glass button used in every page header — one size everywhere, whatever the symbol's own shape
struct HeaderIconButton: View {
    let icon: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 26, height: 26)
                .padding(10)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
    }
}

/// header button that switches a page into card-arranging mode; the same button (✓) confirms and leaves it
struct DeckEditButton: View {
    @Binding var editing: Bool
    var body: some View {
        HeaderIconButton(icon: editing ? "checkmark" : "square.stack.3d.up") {
            if editing { Haptics.success() } else { Haptics.tap() }
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { editing.toggle() }
        }
        .tint(editing ? .accentColor : nil)
    }
}

// MARK: - rows card (web floating list): 5 rows visible, scroll inside, unfold to all; newest first, month separators

struct RowsCardEntry<Row: Identifiable>: Identifiable {
    enum Kind { case month(String, Int), row(Row) }
    let id: String
    let kind: Kind
}

struct RowsCard<Row: Identifiable, RowView: View>: View {
    let title: String
    let total: String
    let rows: [Row]                       // newest first
    let date: (Row) -> JalaliDate
    let amount: (Row) -> Int
    let empty: String
    /// PDF of these rows (no budget card — that is only in the reports tab)
    var export: (() async -> ExportFile?)? = nil
    @ViewBuilder let rowView: (Row) -> RowView
    @State private var open = false
    @State private var position = ScrollPosition(edge: .top)
    @State private var share: ExportFile?
    @State private var building = false
    @Environment(\.theme) private var t

    static var rowH: CGFloat { 62 }
    static var headH: CGFloat { 30 }
    private let visibleRows = 5

    init(title: String, total: String, rows: [Row], date: @escaping (Row) -> JalaliDate, amount: @escaping (Row) -> Int,
         empty: String, export: (() async -> ExportFile?)? = nil, @ViewBuilder rowView: @escaping (Row) -> RowView) {
        self.title = title; self.total = total; self.rows = rows; self.date = date; self.amount = amount
        self.empty = empty; self.export = export; self.rowView = rowView
    }

    private var entries: [RowsCardEntry<Row>] {
        var out: [RowsCardEntry<Row>] = []
        var last: (Int, Int)?
        var monthTotals: [String: Int] = [:]
        for r in rows { let d = date(r); monthTotals["\(d.jy)-\(d.jm)", default: 0] += amount(r) }
        for r in rows {
            let d = date(r)
            if last == nil || last! != (d.jy, d.jm) {
                last = (d.jy, d.jm)
                let name = BackupExporter.months[max(0, min(11, d.jm - 1))] + " " + Money.persianDigits(String(d.jy))
                out.append(RowsCardEntry(id: "m\(d.jy)-\(d.jm)", kind: .month(name, monthTotals["\(d.jy)-\(d.jm)"] ?? 0)))
            }
            out.append(RowsCardEntry(id: "r\(r.id)", kind: .row(r)))
        }
        return out
    }

    /// height of the first `limit` rows (with the month labels among them); nil limit = everything
    private func height(_ e: [RowsCardEntry<Row>], rows limit: Int?) -> CGFloat {
        var h: CGFloat = 0, n = 0
        for x in e {
            switch x.kind {
            case .month: h += Self.headH
            case .row: h += Self.rowH; n += 1
            }
            if let l = limit, n == l { break }
        }
        return h
    }

    var body: some View {
        let e = entries
        let more = rows.count > visibleRows
        VStack(alignment: .leading, spacing: 10) {
            // header like the category card: title, then the PDF button and the «همه / بستن» toggle at the top
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: title)
                    Text(total).font(AppFont.caption).foregroundStyle(t.soft)
                }
                Spacer()
                if export != nil {
                    if building {
                        ProgressView().controlSize(.small).frame(width: 32, height: 28)
                    } else {
                        Button { makePDF() } label: {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold)).foregroundStyle(t.accent)
                                .frame(width: 32, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if more {
                    Button { toggle() } label: {
                        HStack(spacing: 4) {
                            Text(open ? "بستن" : "همه (" + Fmt.count(rows.count) + ")").font(AppFont.medium(12))
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                .rotationEffect(.degrees(open ? 180 : 0))
                        }
                        .foregroundStyle(t.soft)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if rows.isEmpty {
                Text(empty).font(AppFont.regular(13)).foregroundStyle(t.soft).padding(.vertical, 8)
            } else {
                // one scroll view whose height springs between «5 rows» and «everything»: the card unfolds downward
                // from its top edge, like the category card; folded, the rest scrolls inside
                ScrollView(.vertical) { list(e) }
                    .scrollPosition($position)
                    .scrollDisabled(open || !more)
                    .scrollIndicators(open ? .hidden : .visible)
                    .frame(height: more && !open ? height(e, rows: visibleRows) : height(e, rows: nil))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: more && !open ? 0.9 : 1),
                                                 .init(color: .black.opacity(more && !open ? 0.35 : 1), location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .glassCard()
        .sheet(item: $share) { f in ActivityView(items: [f.url]) }
    }

    private func toggle() {
        Haptics.tap()
        if open { position.scrollTo(edge: .top) }
        withAnimation(.spring(duration: 0.5, bounce: 0.18)) { open.toggle() }
    }

    private func makePDF() {
        guard let export, !building else { return }
        Haptics.tap()
        building = true
        Task { @MainActor in
            share = await export()
            building = false
        }
    }

    private func list(_ e: [RowsCardEntry<Row>]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(e) { x in
                switch x.kind {
                case .month(let name, let sum):
                    HStack(spacing: 8) {
                        Text(name).font(AppFont.bold(12)).foregroundStyle(t.accent)
                        Rectangle().fill(t.accent.opacity(0.25)).frame(height: 1)
                        Text(Money.persianDigits(Money.format(sum))).font(AppFont.medium(11)).foregroundStyle(t.soft)
                    }
                    .frame(height: Self.headH)
                case .row(let r):
                    rowView(r).frame(height: Self.rowH)
                        .overlay(alignment: .bottom) { Rectangle().fill(t.ink.opacity(0.07)).frame(height: 0.6) }
                }
            }
        }
    }
}
