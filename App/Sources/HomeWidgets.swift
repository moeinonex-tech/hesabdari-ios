import SwiftUI
import HesabCore

// iOS-style home widgets on a 4-column grid of square cells.
// Hold a widget → edit mode (widgets jiggle):
//   • «−» on a widget removes it, «+ افزودن ویجت» in the top bar brings one back
//   • hold-and-drag a widget to move it; the others make room and the grid re-packs itself (iOS flow)
//   • drag the corner handle to resize — square or rectangle, snapping to the grid
//   • «تمام» or a tap on the empty background ends editing
// Limits: 2–4 columns × 1–6 rows (4×6 = a full page, the iOS 27 extra-large size), with a per-widget minimum.
// Sizes stay on this phone; order and visibility use the same fields as the web app.

struct WidgetSpan: Codable, Equatable, Hashable {
    var c: Int
    var r: Int
}

enum WidgetSizes {
    static let key = "look.widgetSpans"
    static let columns = 4
    static let maxRows = 6

    static let defaults: [String: WidgetSpan] = [
        "date": WidgetSpan(c: 4, r: 1), "attention": WidgetSpan(c: 4, r: 2), "financial": WidgetSpan(c: 4, r: 3),
        "shortcuts": WidgetSpan(c: 4, r: 2), "activity": WidgetSpan(c: 4, r: 3)
    ]
    static let titles = ["date": "تاریخ امروز", "attention": "نیازمند توجه", "financial": "خلاصه دفترها",
                         "shortcuts": "میانبرها", "activity": "فعالیت اخیر"]
    static let icons = ["date": "calendar", "attention": "exclamationmark.triangle.fill", "financial": "book.closed.fill",
                        "shortcuts": "square.grid.2x2.fill", "activity": "clock.arrow.circlepath"]

    static func minimum(_ key: String) -> WidgetSpan {
        switch key {
        case "date", "shortcuts": return WidgetSpan(c: 2, r: 1)
        default: return WidgetSpan(c: 2, r: 2)
        }
    }
    static func clamp(_ s: WidgetSpan, _ key: String) -> WidgetSpan {
        let m = minimum(key)
        return WidgetSpan(c: min(columns, max(m.c, s.c)), r: min(maxRows, max(m.r, s.r)))
    }
    static func decode(_ raw: String) -> [String: WidgetSpan] {
        (try? JSONDecoder().decode([String: WidgetSpan].self, from: Data(raw.utf8))) ?? [:]
    }
    static func encode(_ m: [String: WidgetSpan]) -> String {
        (try? JSONEncoder().encode(m)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// iOS flow layout: each widget takes the first free place (top to bottom, start to end).
    static func layout(_ items: [(String, WidgetSpan)]) -> (pos: [String: (x: Int, y: Int)], rows: Int) {
        var used = Set<Int>()
        var pos: [String: (x: Int, y: Int)] = [:]
        var rows = 0
        for (key, s) in items {
            var y = 0
            search: while true {
                for x in 0...(columns - s.c) {
                    let cells = (0..<s.r).flatMap { dy in (0..<s.c).map { dx in (y + dy) * columns + x + dx } }
                    if cells.allSatisfy({ !used.contains($0) }) {
                        cells.forEach { used.insert($0) }
                        pos[key] = (x, y)
                        rows = max(rows, y + s.r)
                        break search
                    }
                }
                y += 1
            }
        }
        return (pos, rows)
    }
}

/// Scales a widget's text and items with its size, so a bigger widget shows bigger, clearer data.
struct WidgetMetrics {
    let size: CGSize
    let span: WidgetSpan
    /// 0.85 for a small 2×1 … 1.3 for a big widget
    var k: CGFloat {
        let ref: CGFloat = 175          // ≈ one 2×2 widget side
        let v = sqrt(size.width * size.height) / (ref * 1.6)
        return min(1.3, max(0.85, v))
    }
    var compact: Bool { span.c <= 2 }
    func font(_ base: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let s = base * k
        switch weight {
        case .bold: return AppFont.bold(s)
        case .heavy, .black: return AppFont.heavy(s)
        case .medium, .semibold: return AppFont.medium(s)
        default: return AppFont.regular(s)
        }
    }
    /// how many rows of `rowHeight` (unscaled) fit under the title
    func fit(_ rowHeight: CGFloat) -> Int { max(1, Int((size.height - 28 - 30 * k) / (rowHeight * k))) }
}

struct WidgetGrid<Cell: View>: View {
    let keys: [String]
    @Binding var editing: Bool
    let onReorder: ([String]) -> Void
    let onRemove: (String) -> Void
    var onDragging: (Bool) -> Void = { _ in }
    /// widgets with settings get a «تنظیم» button in edit mode (like iOS «Edit Widget»)
    var onConfigure: ((String) -> Void)? = nil
    let cell: (String, WidgetMetrics) -> Cell

    @AppStorage(WidgetSizes.key) private var spansRaw = "{}"
    @AppStorage(Look.cardFxKey) private var cardFxRaw = CardFx.none.rawValue
    @State private var live: (key: String, span: WidgetSpan)?
    @State private var liveOrder: [String]?
    @State private var dragKey: String?
    @State private var dragStart: CGPoint = .zero      // top-left of the dragged widget when the drag began
    @State private var dragNow: CGPoint = .zero
    @State private var jiggle = false
    @State private var gridHeight: CGFloat = 300
    private let gap: CGFloat = 12

    private func span(_ k: String) -> WidgetSpan {
        if let l = live, l.key == k { return l.span }
        return WidgetSizes.clamp(WidgetSizes.decode(spansRaw)[k] ?? WidgetSizes.defaults[k] ?? WidgetSpan(c: 4, r: 2), k)
    }

    var body: some View {
        GeometryReader { g in
            let cellW = (g.size.width - gap * CGFloat(WidgetSizes.columns - 1)) / CGFloat(WidgetSizes.columns)
            let pitch = cellW + gap
            let order = liveOrder ?? keys
            let items = order.map { ($0, span($0)) }
            let lay = WidgetSizes.layout(items)
            let origin = { (key: String) -> CGPoint in
                let p = lay.pos[key] ?? (0, 0)
                let s = span(key)
                // RTL: the first widget sits on the right
                return CGPoint(x: CGFloat(WidgetSizes.columns - p.x - s.c) * pitch, y: CGFloat(p.y) * pitch)
            }
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.0) { key, s in
                    let size = CGSize(width: CGFloat(s.c) * pitch - gap, height: CGFloat(s.r) * pitch - gap)
                    let o = origin(key)
                    let dragging = dragKey == key
                    widgetCell(key, s, size, pitch: pitch)
                        .padding(.leading, o.x)
                        .padding(.top, o.y)
                        .offset(dragging ? CGSize(width: dragNow.x - o.x, height: dragNow.y - o.y) : .zero)
                        .scaleEffect(dragging ? 1.04 : 1, anchor: .center)
                        .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 18, y: 10)
                        .zIndex(dragging ? 10 : 0)
                        .gesture(editing ? moveGesture(key, origin: o, size: size, pitch: pitch, origins: origin, items: items) : nil)
                }
            }
            .coordinateSpace(.named("widgetGrid"))
            .environment(\.layoutDirection, .leftToRight)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: items.map { "\($0.0)\($0.1.c)x\($0.1.r)" })
            .frame(width: g.size.width, height: max(0, CGFloat(lay.rows) * pitch - gap), alignment: .topLeading)
            .preference(key: GridHeightKey.self, value: max(0, CGFloat(lay.rows) * pitch - gap))
        }
        .frame(height: gridHeight)
        .onPreferenceChange(GridHeightKey.self) { gridHeight = $0 }
        .onChange(of: editing) { _, e in
            if e { withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { jiggle = true } }
            else { jiggle = false; live = nil; liveOrder = nil; dragKey = nil }
        }
    }

    /// hold briefly, then drag: the widget follows the finger and the others re-flow around it
    private func moveGesture(_ key: String, origin: CGPoint, size: CGSize, pitch: CGFloat,
                             origins: @escaping (String) -> CGPoint, items: [(String, WidgetSpan)]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("widgetGrid")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if dragKey != key {
                    dragKey = key
                    onDragging(true)
                    dragStart = origin
                    liveOrder = items.map(\.0)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                dragNow = CGPoint(x: dragStart.x + drag.translation.width, y: dragStart.y + drag.translation.height)
                // the finger is over which widget? → take its place
                let finger = drag.location
                guard var order = liveOrder else { return }
                for other in order where other != key {
                    let o = origins(other)
                    let s = span(other)
                    let rect = CGRect(x: o.x, y: o.y, width: CGFloat(s.c) * pitch - gap, height: CGFloat(s.r) * pitch - gap)
                    if rect.contains(finger), let from = order.firstIndex(of: key), let to = order.firstIndex(of: other) {
                        order.remove(at: from)
                        order.insert(key, at: to)
                        withAnimation(.spring(duration: 0.3)) { liveOrder = order }
                        UISelectionFeedbackGenerator().selectionChanged()
                        break
                    }
                }
            }
            .onEnded { _ in
                if let order = liveOrder, order != keys { onReorder(order) }
                withAnimation(.spring(duration: 0.3)) { dragKey = nil }
                liveOrder = nil
                onDragging(false)
            }
    }

    @ViewBuilder
    private func widgetCell(_ key: String, _ s: WidgetSpan, _ size: CGSize, pitch: CGFloat) -> some View {
        let fx = editing ? CardFx.none : (CardFx(rawValue: cardFxRaw) ?? .none)
        let tilt = (key.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 2 == 0) ? 1.0 : -1.0
        ZStack {
            cell(key, WidgetMetrics(size: size, span: s))
                .environment(\.layoutDirection, .rightToLeft)
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(!editing)
                .modifier(CardEffect(fx: fx, corner: 24))
            if editing {
                // remove (top-right in RTL = iOS top-left mirrored)
                Button {
                    Haptics.tap()
                    onRemove(key)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .frame(width: size.width, height: size.height, alignment: .topTrailing)
                .offset(x: 8, y: -8)
                if key == "shortcuts", let configure = onConfigure {
                    Button {
                        Haptics.tap()
                        configure(key)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .offset(x: -8, y: -8)
                }
                // resize (bottom-left in RTL = iOS bottom-right mirrored)
                ResizeHandle()
                    .frame(width: size.width, height: size.height, alignment: .bottomLeading)
                    .offset(x: -8, y: 8)
                    .highPriorityGesture(resizeGesture(key, base: s, pitch: pitch))
            }
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(editing && dragKey != key ? (jiggle ? 0.8 : -0.8) * tilt : 0))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            guard !editing else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            editing = true
        })
    }

    private func resizeGesture(_ key: String, base: WidgetSpan, pitch: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let stored = WidgetSizes.clamp(WidgetSizes.decode(spansRaw)[key] ?? WidgetSizes.defaults[key] ?? base, key)
                // the handle is on the left: dragging left / down makes the widget bigger
                let dc = Int((-v.translation.width / pitch).rounded())
                let dr = Int((v.translation.height / pitch).rounded())
                let next = WidgetSizes.clamp(WidgetSpan(c: stored.c + dc, r: stored.r + dr), key)
                if live?.span != next { UISelectionFeedbackGenerator().selectionChanged() }
                live = (key, next)
            }
            .onEnded { _ in
                if let l = live {
                    var m = WidgetSizes.decode(spansRaw)
                    m[l.key] = l.span
                    spansRaw = WidgetSizes.encode(m)
                }
                live = nil
            }
    }
}

private struct GridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 13, weight: .bold))
            .rotationEffect(.degrees(90))
            .frame(width: 34, height: 34)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle().inset(by: -10))
    }
}

/// A widget's card: the same surface as every other card, filling its grid cell.
struct WidgetCard<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .glassCard(padding: 14)
            .frame(width: size.width, height: size.height)
    }
}

/// Top bar while editing the home widgets (iOS: «+» on one side, «Done» on the other).
struct WidgetEditBar: View {
    let hidden: [String]
    let onAdd: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            Button("تمام", action: onDone)
                .font(AppFont.bold(16))
                .buttonStyle(.glassProminent)
                .fixedSize()
            Spacer()
            Menu {
                if hidden.isEmpty {
                    Text("همه‌ی ویجت‌ها روی صفحه هستند")
                }
                ForEach(hidden, id: \.self) { k in
                    Button { onAdd(k) } label: { Label(WidgetSizes.titles[k] ?? k, systemImage: WidgetSizes.icons[k] ?? "square") }
                }
            } label: {
                Label("افزودن ویجت", systemImage: "plus")
                    .font(AppFont.bold(15))
                    .fixedSize()
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - size-aware widget rows

struct WidgetAttentionRow: View {
    let item: AttentionItem
    let m: WidgetMetrics
    @Environment(\.theme) private var t
    var body: some View {
        let color: Color = item.level == .danger ? t.danger : (item.level == .warning ? t.warning : t.accent)
        HStack(spacing: 8 * m.k) {
            Image(systemName: item.icon).font(.system(size: 14 * m.k)).foregroundStyle(color)
            Text(item.text).font(m.font(m.compact ? 12 : 14, .medium)).foregroundStyle(t.ink)
                .lineLimit(m.compact ? 3 : 2).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8 * m.k).padding(.horizontal, 10 * m.k)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct WidgetAccountRow: View {
    let account: AccountImportSummary
    let budget: Int
    let m: WidgetMetrics
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 4 * m.k) {
            Text(account.name).font(m.font(m.compact ? 12 : 14, .bold)).foregroundStyle(t.ink).lineLimit(1)
            Text(Fmt.toman(account.expenseTotal)).font(m.font(m.compact ? 15 : 19, .heavy)).foregroundStyle(t.accent)
                .lineLimit(1).minimumScaleFactor(0.6)
            if budget > 0 {
                let pct = min(1, Double(account.expenseTotal) / Double(budget))
                ProgressView(value: pct).tint(pct >= 0.8 ? t.warning : t.accent2)
                if !m.compact {
                    Text("\(Money.persianDigits(Money.jsRound(pct * 100)))٪ از بودجه")
                        .font(m.font(11)).foregroundStyle(t.soft)
                }
            }
            if !m.compact && (account.commissionEnabled || account.percent != 0) {
                Text("مانده‌ی کمیسیون: " + Fmt.balance(account.remaining)).font(m.font(12, .medium)).foregroundStyle(t.ink).lineLimit(1)
            }
        }
        .padding(10 * m.k)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WidgetActivityRow: View {
    let item: RecentItem
    let color: Color?
    let m: WidgetMetrics
    @Environment(\.theme) private var t
    var body: some View {
        let r = item.row
        HStack(spacing: 8 * m.k) {
            Circle().fill(r.kind == .commission ? Color.purple : (r.kind == .tankhah ? t.success : (color ?? t.accent)))
                .frame(width: 8 * m.k, height: 8 * m.k)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.desc.isEmpty ? "—" : r.desc).font(m.font(m.compact ? 12 : 14, .medium)).foregroundStyle(t.ink).lineLimit(1)
                if m.compact {
                    Text(Money.persianDigits(Money.format(r.toman))).font(m.font(12, .bold))
                        .foregroundStyle(r.kind == .tankhah ? t.success : t.ink)
                } else {
                    HStack(spacing: 6) {
                        if !item.account.isEmpty { Text(item.account) }
                        Text(r.date)
                        if r.kind == .tankhah { Text("تنخواه").foregroundStyle(t.success) }
                    }
                    .font(m.font(11)).foregroundStyle(t.soft).lineLimit(1)
                }
            }
            if !m.compact {
                Spacer(minLength: 6)
                Text(Money.persianDigits(Money.format(r.toman))).font(m.font(14, .bold))
                    .foregroundStyle(r.kind == .tankhah ? t.success : t.ink).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 4 * m.k)
    }
}

struct WidgetShortcutTile: View {
    let title: String
    let icon: String
    let side: CGFloat
    let action: () -> Void
    @Environment(\.theme) private var t
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: side * 0.08) {
                Image(systemName: icon).font(.system(size: side * 0.3)).foregroundStyle(t.accent)
                if side >= 64 {
                    Text(title).font(AppFont.medium(max(10, side * 0.15))).foregroundStyle(t.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: side)
            .background(t.card.opacity(0.7), in: RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
