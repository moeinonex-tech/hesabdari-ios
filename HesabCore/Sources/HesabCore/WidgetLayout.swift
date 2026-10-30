import Foundation

// Home widget geometry — pure math, fully unit-tested (every order × every size combination).
//
// Grid: 4 columns of square cells, gap g.   cell = (W − 3g) / 4
//   small  = 2×2 cells → side S = 2·cell + g          (square)
//   medium = 4×2 cells → W × S                        (wide)
//   large  = 4×4 cells → W × W  (= 2S + g)            (square)
// Placement (iOS flow): in order, each widget takes the first free slot scanning rows top→bottom and
// columns start→end. Only small widgets can sit side by side, so a slot is either a full row pair or a half.

public enum WidgetSize: String, CaseIterable, Sendable, Codable {
    case small, medium, large
    public var cols: Int { self == .small ? 2 : 4 }
    public var rows: Int { self == .large ? 4 : 2 }
    public var next: WidgetSize { self == .small ? .medium : (self == .medium ? .large : .small) }
    public var title: String { self == .small ? "کوچک" : (self == .medium ? "متوسط" : "بزرگ") }
}

public struct WidgetRect: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < maxX && py >= y && py < maxY }
    public func intersects(_ o: WidgetRect, tolerance: Double = 0.001) -> Bool {
        x < o.maxX - tolerance && o.x < maxX - tolerance && y < o.maxY - tolerance && o.y < maxY - tolerance
    }
}

public enum WidgetLayout {
    public static let columns = 4

    /// grid cells (column, row) of every widget
    public static func cells(_ items: [(key: String, size: WidgetSize)]) -> (pos: [String: (col: Int, row: Int)], rows: Int) {
        var used = Set<Int>()
        var pos: [String: (col: Int, row: Int)] = [:]
        var rows = 0
        for it in items {
            let c = it.size.cols, r = it.size.rows
            var y = 0
            placing: while true {
                var x = 0
                while x + c <= columns {
                    let cells = (0..<r).flatMap { dy in (0..<c).map { dx in (y + dy) * columns + x + dx } }
                    if cells.allSatisfy({ !used.contains($0) }) {
                        cells.forEach { used.insert($0) }
                        pos[it.key] = (x, y)
                        rows = max(rows, y + r)
                        break placing
                    }
                    x += 2              // only half/full positions exist → no odd gaps
                }
                y += 2                  // every size is a multiple of 2 rows
            }
        }
        return (pos, rows)
    }

    public static func cell(width: Double, gap: Double) -> Double { (width - gap * Double(columns - 1)) / Double(columns) }

    /// pixel frames; rtl puts column 0 on the right
    public static func frames(_ items: [(key: String, size: WidgetSize)], width: Double, gap: Double, rtl: Bool)
        -> (frames: [String: WidgetRect], height: Double) {
        let cell = cell(width: width, gap: gap)
        let pitch = cell + gap
        let lay = cells(items)
        var out: [String: WidgetRect] = [:]
        for it in items {
            guard let p = lay.pos[it.key] else { continue }
            let w = Double(it.size.cols) * pitch - gap
            let h = Double(it.size.rows) * pitch - gap
            let xLTR = Double(p.col) * pitch
            let x = rtl ? width - xLTR - w : xLTR
            out[it.key] = WidgetRect(x: x, y: Double(p.row) * pitch, w: w, h: h)
        }
        return (out, lay.rows == 0 ? 0 : Double(lay.rows) * pitch - gap)
    }

    /// while dragging: the widget under the finger gives its place to the dragged one
    public static func reorder(_ order: [String], dragging key: String, over point: (Double, Double),
                               frames: [String: WidgetRect]) -> [String] {
        guard let from = order.firstIndex(of: key) else { return order }
        for (i, other) in order.enumerated() where other != key {
            if let f = frames[other], f.contains(point.0, point.1) {
                var o = order
                o.remove(at: from)
                o.insert(key, at: i)
                return o
            }
        }
        return order
    }

    // MARK: shortcut tiles inside a widget

    public struct Tiles: Equatable, Sendable {
        public let perRow: Int
        public let rows: Int
        public let side: Double
        public let spacing: Double
        public var capacity: Int { perRow * rows }
    }

    /// biggest square tiles that fit `count` items in the area (perRow 2…4)
    public static func tiles(count: Int, width: Double, height: Double, spacing: Double = 8) -> Tiles {
        var best = Tiles(perRow: 4, rows: 1, side: 0, spacing: spacing)
        for perRow in 2...4 {
            let side = (width - spacing * Double(perRow - 1)) / Double(perRow)
            let maxRows = max(1, Int((height + spacing) / (side + spacing)))
            let needRows = max(1, Int((Double(max(count, 1)) / Double(perRow)).rounded(.up)))
            let rows = min(maxRows, needRows)
            var s = side
            // shrink the tile if even one row does not fit the height
            if s > height { s = height }
            let shows = min(count, perRow * rows)
            let bestShows = min(count, best.capacity)
            if shows > bestShows || (shows == bestShows && s > best.side) {
                best = Tiles(perRow: perRow, rows: rows, side: s, spacing: spacing)
            }
        }
        return best
    }

    /// tile frame (LTR coordinates inside the area); rtl mirrors the columns
    public static func tileRect(_ index: Int, _ t: Tiles, areaWidth: Double, rtl: Bool) -> WidgetRect {
        let col = index % t.perRow, row = index / t.perRow
        let rowWidth = Double(t.perRow) * t.side + Double(t.perRow - 1) * t.spacing
        let start = (areaWidth - rowWidth) / 2
        let xLTR = start + Double(col) * (t.side + t.spacing)
        let x = rtl ? areaWidth - xLTR - t.side : xLTR
        return WidgetRect(x: x, y: Double(row) * (t.side + t.spacing), w: t.side, h: t.side)
    }

    public static func tileIndex(at x: Double, _ y: Double, count: Int, _ t: Tiles, areaWidth: Double, rtl: Bool) -> Int? {
        for i in 0..<min(count, t.capacity) where tileRect(i, t, areaWidth: areaWidth, rtl: rtl).contains(x, y) { return i }
        return nil
    }
}
