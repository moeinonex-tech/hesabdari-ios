import XCTest
@testable import HesabCore

/// Exhaustive geometry check: every order of the 5 home widgets × every size combination (120 × 243 = 29 160
/// layouts) on several phone widths — no overlap, nothing outside the screen, height = the lowest widget.
final class WidgetLayoutTests: XCTestCase {
    let keys = ["date", "attention", "financial", "shortcuts", "activity"]

    func permutations(_ a: [String]) -> [[String]] {
        if a.count <= 1 { return [a] }
        return a.indices.flatMap { i -> [[String]] in
            var rest = a; let x = rest.remove(at: i)
            return permutations(rest).map { [x] + $0 }
        }
    }

    func testEveryLayoutIsClean() {
        let sizes = WidgetSize.allCases
        let perms = permutations(keys)
        var checked = 0
        for width in [343.0, 358.0, 398.0] {
            for combo in 0..<243 {
                var c = combo
                var size: [String: WidgetSize] = [:]
                for k in keys { size[k] = sizes[c % 3]; c /= 3 }
                for order in perms {
                    let items = order.map { (key: $0, size: size[$0]!) }
                    for rtl in [true, false] {
                        let r = WidgetLayout.frames(items, width: width, gap: 14, rtl: rtl)
                        let fs = order.map { r.frames[$0]! }
                        var bottom = 0.0
                        var ok = true
                        for (i, f) in fs.enumerated() {
                            if f.x < -0.001 || f.maxX > width + 0.001 || f.w <= 0 { ok = false }
                            bottom = max(bottom, f.maxY)
                            for g in fs[(i + 1)...] where f.intersects(g) { ok = false }
                        }
                        if !ok || abs(r.height - bottom) > 0.001 {
                            XCTFail("bad layout \(order) \(size) width \(width) rtl \(rtl)")
                            return
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 3 * 243 * 120 * 2)
    }

    func testSizesAndPacking() {
        let w = 358.0, g = 14.0
        let cell = WidgetLayout.cell(width: w, gap: g)
        let r = WidgetLayout.frames([("a", .small), ("b", .large), ("c", .small)], width: w, gap: g, rtl: true)
        // small is square, large is square and full width, two smalls share a row (c fills the hole next to a)
        XCTAssertEqual(r.frames["a"]!.w, r.frames["a"]!.h, accuracy: 0.001)
        XCTAssertEqual(r.frames["b"]!.w, w, accuracy: 0.001)
        XCTAssertEqual(r.frames["b"]!.h, w, accuracy: 0.001)
        XCTAssertEqual(r.frames["c"]!.y, 0, accuracy: 0.001)
        XCTAssertEqual(r.frames["a"]!.x, w - r.frames["a"]!.w, accuracy: 0.001)   // RTL: first on the right
        XCTAssertEqual(r.height, (2 * cell + g) + g + w, accuracy: 0.001)
    }

    func testReorderTakesThePlaceUnderTheFinger() {
        let items: [(key: String, size: WidgetSize)] = keys.map { ($0, .medium) }
        let f = WidgetLayout.frames(items, width: 358, gap: 14, rtl: true).frames
        let mid = f["financial"]!
        let o = WidgetLayout.reorder(keys, dragging: "activity", over: (mid.x + 10, mid.y + 10), frames: f)
        XCTAssertEqual(o, ["date", "attention", "activity", "financial", "shortcuts"])
        XCTAssertEqual(WidgetLayout.reorder(keys, dragging: "date", over: (-50, -50), frames: f), keys)
    }

    func testTilesFitAndHitTest() {
        for (w, h) in [(144.0, 144.0), (330.0, 110.0), (330.0, 290.0), (130.0, 60.0)] {
            for n in 0...7 {
                let t = WidgetLayout.tiles(count: n, width: w, height: h)
                for i in 0..<min(n, t.capacity) {
                    for rtl in [true, false] {
                        let r = WidgetLayout.tileRect(i, t, areaWidth: w, rtl: rtl)
                        XCTAssertGreaterThanOrEqual(r.x, -0.001); XCTAssertLessThanOrEqual(r.maxX, w + 0.001)
                        XCTAssertLessThanOrEqual(r.maxY, h + 0.001, "tiles \(n) in \(w)x\(h)")
                        XCTAssertEqual(WidgetLayout.tileIndex(at: r.x + r.w / 2, r.y + r.h / 2, count: n, t, areaWidth: w, rtl: rtl), i)
                    }
                }
            }
        }
    }

    /// the content-height «attention» block anywhere in any order, with any sizes: still no overlap
    func testBlocksNeverOverlap() {
        let sizes = WidgetSize.allCases
        for h in [60.0, 133.0, 250.0] {
            for combo in 0..<81 {
                var c = combo
                var size: [String: WidgetSize] = [:]
                for k in keys where k != "attention" { size[k] = sizes[c % 3]; c /= 3 }
                size["attention"] = .medium
                for order in permutations(keys) {
                    let items = order.map { (key: $0, size: size[$0]!) }
                    let r = WidgetLayout.frames(items, width: 358, gap: 14, rtl: true, blocks: ["attention": h])
                    let fs = order.map { r.frames[$0]! }
                    var bottom = 0.0
                    for (i, f) in fs.enumerated() {
                        bottom = max(bottom, f.maxY)
                        for g in fs[(i + 1)...] where f.intersects(g) { XCTFail("overlap \(order) h\(h)"); return }
                    }
                    XCTAssertEqual(r.frames["attention"]!.h, h, accuracy: 0.001)
                    if abs(r.height - bottom) > 0.001 { XCTFail("height \(order)"); return }
                }
            }
        }
    }
}
