import SwiftUI

// iOS-style home widgets: a 4-column grid with square cells. Hold a widget to enter edit mode (it jiggles),
// then drag the handle in its corner to make it smaller or bigger — square or rectangle, snapping to the grid
// like the iOS 27 Home Screen. Limits: 2–4 columns wide, 1–6 rows tall (4×6 = a full page, the new iOS 27
// extra-large size), and a per-widget minimum so its content still fits. Sizes are kept on this phone.

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
    static func minimum(_ key: String) -> WidgetSpan {
        switch key {
        case "date": return WidgetSpan(c: 2, r: 1)
        case "shortcuts": return WidgetSpan(c: 2, r: 1)
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

    /// iOS flow layout: each widget goes to the first free place (top to bottom, start to end).
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

struct WidgetGrid<Cell: View>: View {
    let keys: [String]
    @Binding var editing: Bool
    let cell: (String, WidgetSpan, CGSize) -> Cell
    @AppStorage(WidgetSizes.key) private var spansRaw = "{}"
    @AppStorage(Look.cardFxKey) private var cardFxRaw = CardFx.none.rawValue
    @State private var live: (key: String, span: WidgetSpan)?
    @State private var jiggle = false
    private let gap: CGFloat = 12

    private func span(_ k: String) -> WidgetSpan {
        if let l = live, l.key == k { return l.span }
        return WidgetSizes.clamp(WidgetSizes.decode(spansRaw)[k] ?? WidgetSizes.defaults[k] ?? WidgetSpan(c: 4, r: 2), k)
    }

    var body: some View {
        GeometryReader { g in
            let cellW = (g.size.width - gap * CGFloat(WidgetSizes.columns - 1)) / CGFloat(WidgetSizes.columns)
            let pitch = cellW + gap
            let items = keys.map { ($0, span($0)) }
            let lay = WidgetSizes.layout(items)
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.0) { key, s in
                    let p = lay.pos[key] ?? (0, 0)
                    let size = CGSize(width: CGFloat(s.c) * pitch - gap, height: CGFloat(s.r) * pitch - gap)
                    // RTL: the first widget sits on the right
                    let x = CGFloat(WidgetSizes.columns - p.x - s.c) * pitch
                    widgetCell(key, s, size, pitch: pitch)
                        .padding(.leading, x)
                        .padding(.top, CGFloat(p.y) * pitch)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: items.map { "\($0.0)\($0.1.c)x\($0.1.r)" })
            .frame(width: g.size.width, height: CGFloat(lay.rows) * pitch - gap, alignment: .topLeading)
            .preference(key: GridHeightKey.self, value: CGFloat(max(lay.rows, 0)) * pitch - gap)
        }
        .frame(height: gridHeight)
        .onPreferenceChange(GridHeightKey.self) { gridHeight = max(0, $0) }
        .onChange(of: editing) { _, e in
            if e { withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { jiggle = true } }
            else { withAnimation(.default) { jiggle = false } }
        }
    }
    @State private var gridHeight: CGFloat = 400

    @ViewBuilder
    private func widgetCell(_ key: String, _ s: WidgetSpan, _ size: CGSize, pitch: CGFloat) -> some View {
        let fx = editing ? CardFx.none : (CardFx(rawValue: cardFxRaw) ?? .none)
        ZStack(alignment: .bottomLeading) {
            cell(key, s, size)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(!editing)
                .modifier(CardEffect(fx: fx, corner: 24))
            if editing {
                ResizeHandle()
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                // handle is on the bottom-left (RTL); dragging left/down grows the widget
                                let base = WidgetSizes.clamp(WidgetSizes.decode(spansRaw)[key] ?? WidgetSizes.defaults[key] ?? s, key)
                                let dc = Int((-v.translation.width / pitch).rounded())
                                let dr = Int((v.translation.height / pitch).rounded())
                                let next = WidgetSizes.clamp(WidgetSpan(c: base.c + dc, r: base.r + dr), key)
                                if live?.span != next { Haptics.tap() }
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
                    )
                    .offset(x: -6, y: 6)
            }
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(editing ? (jiggle ? 0.9 : -0.9) * (key.hashValue % 2 == 0 ? 1 : -1) : 0))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            guard !editing else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            editing = true
        })
    }
}

private struct GridHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.down.left.and.arrow.up.right")
            .font(.system(size: 13, weight: .bold))
            .rotationEffect(.degrees(90))
            .frame(width: 34, height: 34)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle().inset(by: -10))
    }
}

/// A widget's card: same surface as every other card, filling its grid cell.
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
