import SwiftUI
import HesabCore

// iOS-style home widgets. Geometry comes from HesabCore.WidgetLayout (tested for every order × size).
// Sizes: small 2×2 (square) · medium 4×2 (wide) · large 4×4 (square, full width).
//
// Normal mode: tap a widget → its page; hold it → edit mode.
// Edit mode (widgets jiggle at a steady pace):
//   «−» removes · «+ افزودن ویجت» brings back · hold-and-drag moves (others re-flow) ·
//   corner handle: drag to resize (snaps small ⇄ medium ⇄ large) or tap to switch to the next size ·
//   «تمام» or a tap on empty space ends editing.
// Widget content never takes touches itself — every gesture is handled once, here, at the widget level.

enum HomeWidgetPrefs {
    static let key = "look.widgetSizes"
    static let defaults: [String: WidgetSize] = ["date": .small, "attention": .small, "financial": .medium,
                                                  "shortcuts": .medium, "activity": .large]
    static let titles = ["date": "تاریخ امروز", "attention": "نیازمند توجه", "financial": "خلاصه دفترها",
                         "shortcuts": "میانبرها", "activity": "فعالیت اخیر"]
    static let icons = ["date": "calendar", "attention": "exclamationmark.triangle.fill", "financial": "book.closed.fill",
                        "shortcuts": "square.grid.2x2.fill", "activity": "clock.arrow.circlepath"]

    static func decode(_ raw: String) -> [String: WidgetSize] {
        ((try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]).compactMapValues(WidgetSize.init(rawValue:))
    }
    static func encode(_ m: [String: WidgetSize]) -> String {
        (try? JSONEncoder().encode(m.mapValues(\.rawValue))).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

struct WidgetGrid<Cell: View>: View {
    let keys: [String]
    @Binding var editing: Bool
    let onTap: (String, CGPoint, CGSize) -> Void
    let onReorder: ([String]) -> Void
    let onRemove: (String) -> Void
    let onConfigure: (String) -> Void
    let onDragging: (Bool) -> Void
    let cell: (String, WidgetSize, CGSize) -> Cell

    static var gap: CGFloat { 14 }

    @AppStorage(HomeWidgetPrefs.key) private var sizesRaw = "{}"
    @AppStorage(Look.cardFxKey) private var cardFxRaw = CardFx.none.rawValue
    @State private var width: CGFloat = max(300, UIScreen.main.bounds.width - 32)
    @State private var liveSize: (key: String, size: WidgetSize)?
    @State private var liveOrder: [String]?
    @State private var dragKey: String?
    @State private var dragStart: CGPoint = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var lastOver: String?

    private func size(_ k: String) -> WidgetSize {
        if let l = liveSize, l.key == k { return l.size }
        return HomeWidgetPrefs.decode(sizesRaw)[k] ?? HomeWidgetPrefs.defaults[k] ?? .medium
    }

    private func layout(_ order: [String]) -> (frames: [String: WidgetRect], height: Double) {
        WidgetLayout.frames(order.map { (key: $0, size: size($0)) }, width: Double(width), gap: Double(Self.gap), rtl: true)
    }

    var body: some View {
        let order = liveOrder ?? keys
        let lay = layout(order)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !editing)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(order, id: \.self) { key in
                    if let f = lay.frames[key] {
                        let s = size(key)
                        let dragging = dragKey == key
                        // steady jiggle: same speed always, alternate direction per widget
                        let phase = Double(order.firstIndex(of: key) ?? 0)
                        let angle = editing && !dragging ? sin(t * 2 * .pi * 3.2 + phase * 1.7) * 0.9 : 0
                        widgetCell(key, s, CGSize(width: f.w, height: f.h), frames: lay.frames, order: order)
                            .rotationEffect(.degrees(angle))
                            .scaleEffect(dragging ? 1.05 : 1)
                            .shadow(color: .black.opacity(dragging ? 0.22 : 0), radius: 16, y: 8)
                            .offset(dragging ? CGSize(width: dragStart.x + dragTranslation.width - f.x,
                                                      height: dragStart.y + dragTranslation.height - f.y) : .zero)
                            .position(x: f.x + f.w / 2, y: f.y + f.h / 2)
                            .zIndex(dragging ? 10 : 0)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .coordinateSpace(.named("widgetGrid"))
        .frame(width: width, height: CGFloat(lay.height), alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { w in if w > 0 && abs(w - width) > 0.5 { width = w } }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: order.map { $0 + size($0).rawValue })
        .onChange(of: editing) { _, e in
            if !e { liveSize = nil; liveOrder = nil; dragKey = nil; lastOver = nil }
        }
    }

    @ViewBuilder
    private func widgetCell(_ key: String, _ s: WidgetSize, _ sz: CGSize, frames: [String: WidgetRect], order: [String]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let fx = editing ? CardFx.none : (CardFx(rawValue: cardFxRaw) ?? .none)
        cell(key, s, sz)
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: sz.width, height: sz.height)
            .allowsHitTesting(false)
            .modifier(CardEffect(fx: fx, corner: 24))
            .contentShape(shape)
            .gesture(editing ? nil : normalGesture(key, sz))
            .gesture(editing ? moveGesture(key, frames: frames, order: order) : nil)
            .overlay(alignment: .topTrailing) {
                if editing {
                    Badge(icon: "minus") { onRemove(key) }.offset(x: 6, y: -6)
                }
            }
            .overlay(alignment: .topLeading) {
                if editing && key == "shortcuts" {
                    Badge(icon: "slider.horizontal.3") { onConfigure(key) }.offset(x: -6, y: -6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if editing {
                    ResizeHandle()
                        .offset(x: -6, y: 6)
                        .highPriorityGesture(resizeGesture(key, current: s))
                }
            }
    }

    /// tap → open, hold → edit mode (only one of the two ever fires)
    private func normalGesture(_ key: String, _ sz: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .exclusively(before: SpatialTapGesture())
            .onEnded { v in
                switch v {
                case .first:
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring) { editing = true }
                case .second(let tap):
                    onTap(key, tap.location, sz)
                }
            }
    }

    private func moveGesture(_ key: String, frames: [String: WidgetRect], order: [String]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("widgetGrid")))
            .onChanged { v in
                guard case .second(true, let drag?) = v else { return }
                if dragKey != key {
                    let f = frames[key] ?? WidgetRect(x: 0, y: 0, w: 0, h: 0)
                    dragStart = CGPoint(x: f.x, y: f.y)
                    liveOrder = order
                    dragKey = key
                    onDragging(true)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                dragTranslation = drag.translation
                let current = liveOrder ?? order
                let lay = layout(current)
                let p = (Double(drag.location.x), Double(drag.location.y))
                let over = current.first { $0 != key && (lay.frames[$0]?.contains(p.0, p.1) ?? false) }
                guard let over else { lastOver = nil; return }
                guard over != lastOver else { return }        // hysteresis: no back-and-forth flicker
                lastOver = over
                let next = WidgetLayout.reorder(current, dragging: key, over: p, frames: lay.frames)
                if next != current {
                    liveOrder = next
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                if let o = liveOrder, o != keys { onReorder(o) }
                dragKey = nil
                dragTranslation = .zero
                liveOrder = nil
                lastOver = nil
                onDragging(false)
            }
    }

    /// handle: drag left (outward) for wide, down for tall; a plain tap switches to the next size
    private func resizeGesture(_ key: String, current: WidgetSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let stored = HomeWidgetPrefs.decode(sizesRaw)[key] ?? HomeWidgetPrefs.defaults[key] ?? .medium
                let cell = WidgetLayout.cell(width: Double(width), gap: Double(Self.gap))
                let out = Double(-v.translation.width), down = Double(v.translation.height)
                let wide = stored.cols == 4 ? out > -cell : out > cell
                let tall = stored.rows == 4 ? down > -cell * 1.5 : down > cell * 1.5
                let next: WidgetSize = !wide ? .small : (tall ? .large : .medium)
                if abs(out) + abs(down) < 6 { return }
                if size(key) != next { UISelectionFeedbackGenerator().selectionChanged() }
                liveSize = (key, next)
            }
            .onEnded { v in
                var m = HomeWidgetPrefs.decode(sizesRaw)
                if abs(v.translation.width) + abs(v.translation.height) < 6 {
                    m[key] = (m[key] ?? HomeWidgetPrefs.defaults[key] ?? .medium).next
                    UISelectionFeedbackGenerator().selectionChanged()
                } else if let l = liveSize {
                    m[key] = l.size
                }
                sizesRaw = HomeWidgetPrefs.encode(m)
                liveSize = nil
            }
    }
}

private struct Badge: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
    }
}

private struct ResizeHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.right.and.arrow.down.left")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 32, height: 32)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle().inset(by: -8))
    }
}

/// The card of one widget: fixed size, content clipped inside — it can never grow past its slot.
struct WidgetCard<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content
    static var padding: CGFloat { 14 }
    var body: some View {
        content
            .frame(width: max(0, size.width - Self.padding * 2), height: max(0, size.height - Self.padding * 2), alignment: .topLeading)
            .clipped()
            .padding(Self.padding)
            .frame(width: size.width, height: size.height)
            .modifier(GlassSurface())
    }
}

/// glassCard's surface without its padding / flexible frame
private struct GlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.glassCard(padding: 0)
    }
}

/// Top bar in edit mode (iOS: «Done» on one side, «+» on the other).
struct WidgetEditBar: View {
    let hidden: [String]
    let onAdd: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            Button(action: onDone) {
                Text("تمام").font(AppFont.bold(16)).padding(.horizontal, 8).fixedSize()
            }
            .buttonStyle(.glassProminent)
            Spacer(minLength: 12)
            Menu {
                if hidden.isEmpty { Text("همه‌ی ویجت‌ها روی صفحه هستند") }
                ForEach(hidden, id: \.self) { k in
                    Button { onAdd(k) } label: {
                        Label(HomeWidgetPrefs.titles[k] ?? k, systemImage: HomeWidgetPrefs.icons[k] ?? "square")
                    }
                }
            } label: {
                Label("افزودن ویجت", systemImage: "plus").font(AppFont.bold(15)).fixedSize()
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
