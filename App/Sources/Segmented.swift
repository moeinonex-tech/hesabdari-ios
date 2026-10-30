import SwiftUI

/// Segmented choice that also follows a horizontal swipe: the glass thumb slides under the finger and the
/// choice changes as it crosses each part (tap still works). Vertical page scrolling is left alone.
struct Segmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @Environment(\.theme) private var t
    @Environment(\.layoutDirection) private var dir
    @State private var dragX: CGFloat?
    @State private var horizontal: Bool?

    init(selection: Binding<T>, _ options: [(T, String)]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        GeometryReader { g in
            let n = max(1, options.count)
            let inset: CGFloat = 3
            let w = (g.size.width - inset * 2) / CGFloat(n)
            let idx = options.firstIndex { $0.0 == selection } ?? 0
            let rtl = dir == .rightToLeft
            // visual slot (0 = left edge) of an option index
            let slotX = { (i: Int) -> CGFloat in inset + CGFloat(rtl ? n - 1 - i : i) * w }
            let thumbX = dragX.map { min(max(inset, $0 - w / 2), g.size.width - inset - w) } ?? slotX(idx)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(t.card.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .frame(width: w, height: g.size.height - inset * 2)
                    .offset(x: thumbX, y: inset)
                    .animation(dragX == nil ? .spring(duration: 0.32, bounce: 0.22) : .interactiveSpring(response: 0.18), value: thumbX)
                ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                    Text(o.1)
                        .font(i == idx ? AppFont.bold(13.5) : AppFont.medium(13.5))
                        .foregroundStyle(i == idx ? t.ink : t.ink.opacity(0.62))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: w, height: g.size.height)
                        .offset(x: slotX(i))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .contentShape(Capsule())
            .onTapGesture(coordinateSpace: .local) { p in pick(at: p.x, w: w, n: n, inset: inset, rtl: rtl) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { v in
                        if horizontal == nil { horizontal = abs(v.translation.width) > abs(v.translation.height) }
                        guard horizontal == true else { return }
                        dragX = v.location.x
                        pick(at: v.location.x, w: w, n: n, inset: inset, rtl: rtl)
                    }
                    .onEnded { _ in
                        horizontal = nil
                        dragX = nil
                    }
            )
        }
        .frame(height: 36)
        .background(Capsule().fill(t.ink.opacity(0.08)))
        .accessibilityRepresentation {
            Picker("", selection: $selection) { ForEach(Array(options.enumerated()), id: \.offset) { _, o in Text(o.1).tag(o.0) } }
                .pickerStyle(.segmented)
        }
    }

    private func pick(at x: CGFloat, w: CGFloat, n: Int, inset: CGFloat, rtl: Bool) {
        let slot = min(n - 1, max(0, Int(((x - inset) / max(1, w)).rounded(.down))))
        let i = rtl ? n - 1 - slot : slot
        guard options.indices.contains(i), options[i].0 != selection else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy) { selection = options[i].0 }
    }
}
