import SwiftUI

/// Segmented choice (tap) with a glass thumb that slides to the chosen part. Laid out by a plain HStack, so it follows
/// the page direction and can never be pushed off screen (no manual offsets).
struct Segmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @Environment(\.theme) private var t
    @Namespace private var ns

    init(selection: Binding<T>, _ options: [(T, String)]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.0 == selection
                Text(o.1)
                    .font(on ? AppFont.bold(13.5) : AppFont.medium(13.5))
                    .foregroundStyle(on ? t.ink : t.ink.opacity(0.62))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background {
                        if on {
                            Capsule()
                                .fill(t.card.opacity(0.95))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.6))
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard !on else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(duration: 0.32, bounce: 0.2)) { selection = o.0 }
                    }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(t.ink.opacity(0.08)))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - page swipe (Telegram-like): a horizontal swipe anywhere on the page moves to the next / previous part

/// Horizontal scroll rows (chips, chart strips) mark themselves busy, so scrolling them never flips the page.
@MainActor
enum PagingGuard {
    static var lastHorizontalScroll = Date.distantPast
    static var busy: Bool { Date().timeIntervalSince(lastHorizontalScroll) < 0.35 }
}

extension View {
    /// put on horizontal ScrollViews inside a swipeable page
    func guardsPageSwipe() -> some View {
        onScrollPhaseChange { _, phase in
            if phase != .idle { PagingGuard.lastHorizontalScroll = Date() }
        }
    }

    /// RTL book order: the first part is on the right; a swipe toward the right brings the next part (like turning a page)
    func pageSwipe<T: Hashable>(_ selection: Binding<T>, _ order: [T], enabled: Bool = true) -> some View {
        modifier(PageSwipe(selection: selection, order: order, enabled: enabled))
    }
}

private struct PageSwipe<T: Hashable>: ViewModifier {
    @Binding var selection: T
    let order: [T]
    let enabled: Bool
    @Environment(\.layoutDirection) private var dir
    @State private var pull: CGFloat = 0
    @State private var decided: Bool?          // nil = not yet known, true = horizontal swipe, false = something else

    func body(content: Content) -> some View {
        content
            .offset(x: pull)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onChanged { v in
                        guard enabled, order.count > 1 else { return }
                        if decided == nil {
                            let dx = abs(v.translation.width), dy = abs(v.translation.height)
                            if dx > 20 || dy > 20 { decided = dx > dy * 1.8 && !PagingGuard.busy }
                        }
                        guard decided == true else { return }
                        // the page follows the finger a little (rubber band), the real move happens on release
                        let canGo = target(v.translation.width) != nil
                        pull = v.translation.width * (canGo ? 0.22 : 0.08)
                    }
                    .onEnded { v in
                        defer { decided = nil; withAnimation(.spring(duration: 0.3, bounce: 0.25)) { pull = 0 } }
                        guard enabled, decided == true, !PagingGuard.busy else { return }
                        let dx = v.translation.width, predicted = v.predictedEndTranslation.width
                        guard abs(dx) > 60 || abs(predicted) > 160, let next = target(abs(dx) > 60 ? dx : predicted) else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(duration: 0.38, bounce: 0.18)) { selection = next }
                    }
            )
    }

    private func target(_ dx: CGFloat) -> T? {
        guard let i = order.firstIndex(of: selection) else { return nil }
        // RTL: next part sits on the left, so the finger moves to the right to reach it
        let forward = dir == .rightToLeft ? dx > 0 : dx < 0
        let j = forward ? i + 1 : i - 1
        return order.indices.contains(j) ? order[j] : nil
    }
}

/// horizontal strip that never flips the page while it scrolls
struct HScroll<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { content }.guardsPageSwipe()
    }
}
