import SwiftUI
import UIKit

// UIKit-level help for the page scroll views (SwiftUI's ScrollView is a UIScrollView underneath):
//  • page swipe with a direction lock like Telegram: once a drag is horizontal it flips the page and the vertical
//    scroll is cancelled for that touch; a vertical drag never flips the page; horizontal strips keep their own scroll.
//  • dock tap → top immediately, even while the page is still gliding (the glide is stopped first).

/// sits inside a page's scroll content and reports the UIScrollView it lives in (its nearest scrolling ancestor)
struct ScrollAnchor: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> AnchorView {
        let v = AnchorView()
        v.found = found
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: AnchorView, context: Context) { v.found = found; v.report() }

    final class AnchorView: UIView {
        var found: ((UIScrollView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func report() {
            guard window != nil else { return }
            var node = superview
            while let n = node {
                if let sv = n as? UIScrollView { found?(sv); return }
                node = n.superview
            }
        }
    }
}

/// a page's main vertical scroll view, known to the dock (top) and to the page swipe
struct PageScrollView<Content: View>: View {
    let tab: AppTab
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            content.background(ScrollAnchor { sv in ScrollRegistry.register(tab, sv) })
        }
    }
}

// MARK: - dock tap → top

@MainActor
enum ScrollRegistry {
    private static var views: [AppTab: WeakScroll] = [:]
    static var pagers: [AppTab: PagingPan] = [:]
    final class WeakScroll { weak var sv: UIScrollView?; init(_ s: UIScrollView) { sv = s } }

    static func register(_ tab: AppTab, _ sv: UIScrollView) {
        if views[tab]?.sv !== sv { views[tab] = WeakScroll(sv) }
        pagers[tab]?.attach(to: sv)
    }
    static func scrollView(_ tab: AppTab) -> UIScrollView? { views[tab]?.sv }

    /// after a page switch the content can be much shorter than where the page was scrolled to, which left an empty
    /// screen "below the end"; bring the offset back inside the new content
    static func clamp(_ tab: AppTab) {
        if let sv = views[tab]?.sv, sv.window != nil {
            let top = -sv.adjustedContentInset.top
            if sv.contentOffset.y > top + 1 {
                sv.setContentOffset(sv.contentOffset, animated: false)       // stop any glide
                sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: top), animated: false)
            }
        }
        for delay in [0.05, 0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let sv = views[tab]?.sv, sv.window != nil, !sv.isDragging else { return }
                sv.layoutIfNeeded()
                let top = -sv.adjustedContentInset.top
                let maxY = max(top, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                if sv.contentOffset.y > maxY + 1 {
                    sv.setContentOffset(sv.contentOffset, animated: false)
                    sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: maxY), animated: delay > 0.05)
                }
            }
        }
    }

    /// stops any glide at once, then animates to the very top; false when the scroll view is unknown
    static func toTop(_ tab: AppTab) -> Bool {
        guard let sv = views[tab]?.sv, sv.window != nil else { return false }
        sv.setContentOffset(sv.contentOffset, animated: false)        // kills the deceleration immediately
        let top = CGPoint(x: sv.contentOffset.x, y: -sv.adjustedContentInset.top)
        if abs(sv.contentOffset.y - top.y) < 1 { return true }
        sv.setContentOffset(top, animated: true)
        return true
    }
}

// MARK: - page swipe with direction lock

final class PagingPan: NSObject, UIGestureRecognizerDelegate {
    weak var scroll: UIScrollView?
    let pan = UIPanGestureRecognizer()
    var enabled = true
    /// (horizontal travel, horizontal velocity) when a horizontal drag ends
    var onSwipe: ((CGFloat, CGFloat) -> Void)?

    func attach(to sv: UIScrollView) {
        guard scroll !== sv else { return }
        if let old = scroll { old.removeGestureRecognizer(pan) }
        scroll = sv
        pan.delegate = self
        pan.cancelsTouchesInView = true          // the row / button under the finger gets a cancel, never a tap
        pan.addTarget(self, action: #selector(handle(_:)))
        sv.addGestureRecognizer(pan)
    }

    @objc private func handle(_ g: UIPanGestureRecognizer) {
        guard let sv = scroll else { return }
        switch g.state {
        case .began:
            // a horizontal drag: freeze the vertical scroll for this touch (direction lock) …
            sv.panGestureRecognizer.isEnabled = false
            sv.panGestureRecognizer.isEnabled = true
            // … and cancel every other gesture waiting under the finger (row taps, long-press menus, buttons),
            // so swiping across a row never opens or edits it
            var node = sv.hitTest(g.location(in: sv), with: nil)
            while let n = node, n !== sv {
                for r in n.gestureRecognizers ?? [] where r !== pan && r.isEnabled {
                    r.isEnabled = false
                    r.isEnabled = true
                }
                node = n.superview
            }
            UISelectionFeedbackGenerator().prepare()
        case .ended:
            onSwipe?(g.translation(in: sv).x, g.velocity(in: sv).x)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard enabled, g === pan, let sv = scroll else { return false }
        if sv.isDecelerating || (sv.isDragging && sv.panGestureRecognizer.state == .changed && abs(sv.panGestureRecognizer.translation(in: sv).y) > 6) {
            return false                        // the page is already moving vertically
        }
        let t = pan.translation(in: sv), v = pan.velocity(in: sv)
        let dx = abs(t.x) > 1 ? abs(t.x) : abs(v.x), dy = abs(t.x) > 1 ? abs(t.y) : abs(v.y)
        guard dx > dy * 1.6 else { return false }
        // a touch that starts on a horizontally scrolling strip belongs to that strip
        let p = pan.location(in: sv)
        var node = sv.hitTest(p, with: nil)
        while let n = node, n !== sv {
            if let inner = n as? UIScrollView, inner.contentSize.width > inner.bounds.width + 1 { return false }
            node = n.superview
        }
        return true
    }

    /// only the page's own scroll runs alongside (it has to, so the direction can be decided); nothing else does
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // scroll views (the page, and a vertical list inside a card) may start alongside; they are stopped on .began
        other === scroll?.panGestureRecognizer || (other is UIPanGestureRecognizer && other.view is UIScrollView)
    }
}
