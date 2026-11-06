import SwiftUI
import HesabCore

/// Built-in card designs for the ten largest Iranian banks. They are original designs in each bank's own colour
/// identity (not copies of the banks' printed card artwork); the bank's logo tile is already on every card.
/// Everything is drawn as vectors at display time, so the design is sharp at any size and screen scale.
enum CardArt: String, CaseIterable, Identifiable {
    case melli, sepah, mellat, tejarat, saderat, pasargad, maskan, keshavarzi, parsian, refah
    var id: String { rawValue }

    /// the bank this design belongs to (SettingsOps.banks key)
    var bankKey: String { rawValue }

    var title: String {
        switch self {
        case .melli: return "ملی"
        case .sepah: return "سپه"
        case .mellat: return "ملت"
        case .tejarat: return "تجارت"
        case .saderat: return "صادرات"
        case .pasargad: return "پاسارگاد"
        case .maskan: return "مسکن"
        case .keshavarzi: return "کشاورزی"
        case .parsian: return "پارسیان"
        case .refah: return "رفاه"
        }
    }

    enum Pattern { case guilloche, rays, ribbons, waves, mesh, arcs, bands, rings, dots, chevrons }

    var colors: [Color] {
        switch self {
        case .melli: return [.hex(0x0A1F44), .hex(0x123E86), .hex(0x0B2A5B)]
        case .sepah: return [.hex(0x0B2559), .hex(0x1C4FA0), .hex(0x0E2F6B)]
        case .mellat: return [.hex(0x7A0B14), .hex(0xD3222A), .hex(0x9E1119)]
        case .tejarat: return [.hex(0x002B5C), .hex(0x0B63B5), .hex(0x1393D0)]
        case .saderat: return [.hex(0x081F3D), .hex(0x1F5A96), .hex(0x0B2E59)]
        case .pasargad: return [.hex(0x7A5508), .hex(0xD9A62B), .hex(0x9C6E0E)]
        case .maskan: return [.hex(0x9A3A0B), .hex(0xEB7A22), .hex(0xB8500F)]
        case .keshavarzi: return [.hex(0x08401F), .hex(0x1B8F45), .hex(0x0B6B34)]
        case .parsian: return [.hex(0x420817), .hex(0xA8193F), .hex(0x6E0F29)]
        case .refah: return [.hex(0x08343F), .hex(0x138A8A), .hex(0x0E5E6F)]
        }
    }

    /// colour of the fine pattern lines
    var ink: Color {
        switch self {
        case .melli: return .hex(0xE2C06A)
        case .sepah: return .hex(0xF2B233)
        case .mellat, .tejarat, .maskan, .refah: return .white
        case .saderat: return .hex(0x8FC0F0)
        case .pasargad: return .hex(0x2A1C02)
        case .keshavarzi: return .hex(0xF2D04B)
        case .parsian: return .hex(0xF3CFA8)
        }
    }

    var pattern: Pattern {
        switch self {
        case .melli: return .guilloche
        case .sepah: return .rays
        case .mellat: return .ribbons
        case .tejarat: return .waves
        case .saderat: return .mesh
        case .pasargad: return .arcs
        case .maskan: return .bands
        case .keshavarzi: return .rings
        case .parsian: return .dots
        case .refah: return .chevrons
        }
    }

    static func forBank(_ key: String?) -> CardArt? { key.flatMap(CardArt.init(rawValue:)) }
}

struct CardArtView: View {
    let art: CardArt

    var body: some View {
        ZStack {
            LinearGradient(colors: art.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas(rendersAsynchronously: false) { ctx, size in
                draw(&ctx, size)
            }
            // a soft light from the top corner, like a printed card under a lamp
            RadialGradient(colors: [.white.opacity(0.22), .white.opacity(0)], center: UnitPoint(x: 0.15, y: 0.0),
                           startRadius: 0, endRadius: 320)
                .blendMode(.softLight)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, u = w / 340          // u = 1 at a typical card width
        let ink = art.ink
        func line(_ p: Path, _ a: Double, _ width: CGFloat = 0.7) { ctx.stroke(p, with: .color(ink.opacity(a)), lineWidth: width * u) }

        switch art.pattern {
        case .guilloche:
            // banknote-style rosette lines across the card
            for k in 0..<26 {
                var p = Path()
                let phase = Double(k) * 0.24
                for i in 0...160 {
                    let x = w * CGFloat(i) / 160
                    let t = Double(i) / 160 * .pi * 4
                    let y = h * 0.58 + CGFloat(sin(t + phase) * 34 * (0.55 + 0.45 * cos(t * 0.5 - phase))) * u
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
                line(p, 0.16)
            }
        case .rays:
            let c = CGPoint(x: w * 1.02, y: h * 1.05)
            for k in 0..<44 {
                let a = Double.pi + Double(k) * (.pi / 2 / 43)
                var p = Path(); p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(a) * w * 1.4, y: c.y + sin(a) * w * 1.4))
                line(p, k % 2 == 0 ? 0.16 : 0.07, k % 2 == 0 ? 1.1 : 0.6)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 90 * u, y: c.y - 90 * u, width: 180 * u, height: 180 * u)), with: .color(ink.opacity(0.14)))
        case .ribbons:
            for (i, a) in [(0, 0.16), (1, 0.10), (2, 0.06)] {
                var p = Path()
                let off = CGFloat(i) * 26 * u
                p.move(to: CGPoint(x: -10, y: h * 0.78 - off))
                p.addCurve(to: CGPoint(x: w + 10, y: h * 0.22 - off), control1: CGPoint(x: w * 0.35, y: h * 0.05 - off), control2: CGPoint(x: w * 0.6, y: h * 1.05 - off))
                p.addLine(to: CGPoint(x: w + 10, y: h * 0.22 - off + 34 * u))
                p.addCurve(to: CGPoint(x: -10, y: h * 0.78 - off + 34 * u), control1: CGPoint(x: w * 0.6, y: h * 1.05 - off + 34 * u), control2: CGPoint(x: w * 0.35, y: h * 0.05 - off + 34 * u))
                p.closeSubpath()
                ctx.fill(p, with: .color(ink.opacity(a)))
            }
        case .waves:
            for (i, a) in [(0, 0.10), (1, 0.13), (2, 0.17)] {
                var p = Path()
                let base = h * (0.62 + 0.12 * CGFloat(i))
                p.move(to: CGPoint(x: 0, y: h))
                for k in 0...80 {
                    let x = w * CGFloat(k) / 80
                    let y = base + CGFloat(sin(Double(k) / 80 * .pi * 2.2 + Double(i) * 1.3)) * 14 * u
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                ctx.fill(p, with: .color(ink.opacity(a)))
            }
        case .mesh:
            for k in 0..<22 {
                var a = Path(), b = Path()
                for i in 0...120 {
                    let x = w * CGFloat(i) / 120
                    let t = Double(i) / 120 * .pi * 2
                    let ya = h * CGFloat(k) / 21 + CGFloat(sin(t * 1.5 + Double(k) * 0.3)) * 12 * u
                    let yb = h * CGFloat(k) / 21 + CGFloat(sin(-t * 1.2 + Double(k) * 0.4)) * 12 * u
                    i == 0 ? a.move(to: CGPoint(x: x, y: ya)) : a.addLine(to: CGPoint(x: x, y: ya))
                    i == 0 ? b.move(to: CGPoint(x: x, y: yb)) : b.addLine(to: CGPoint(x: x, y: yb))
                }
                line(a, 0.12); line(b, 0.08)
            }
        case .arcs:
            let c = CGPoint(x: w * 0.92, y: h * 1.0)
            for k in 1...30 {
                let r = CGFloat(k) * 11 * u
                line(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), k % 3 == 0 ? 0.22 : 0.10, k % 3 == 0 ? 1.0 : 0.6)
            }
        case .bands:
            for k in 0..<7 {
                var p = Path()
                let x0 = w * (CGFloat(k) * 0.2 - 0.3)
                p.move(to: CGPoint(x: x0, y: h)); p.addLine(to: CGPoint(x: x0 + 34 * u, y: h))
                p.addLine(to: CGPoint(x: x0 + 34 * u + h * 0.8, y: 0)); p.addLine(to: CGPoint(x: x0 + h * 0.8, y: 0)); p.closeSubpath()
                ctx.fill(p, with: .color(ink.opacity(k % 2 == 0 ? 0.10 : 0.05)))
            }
        case .rings:
            let c = CGPoint(x: w * 0.12, y: h * 0.1)
            for k in 1...26 {
                let r = CGFloat(k) * 12 * u
                line(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), 0.13 - Double(k) * 0.003)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.68, y: h * 0.52, width: 150 * u, height: 150 * u)), with: .color(ink.opacity(0.10)))
        case .dots:
            let step = 11 * u
            var y: CGFloat = step / 2
            var row = 0
            while y < h {
                var x: CGFloat = (row % 2 == 0 ? 0 : step / 2)
                while x < w + step {
                    let f = max(0, min(1, (x / w) * 0.8 + (y / h) * 0.4 - 0.25))
                    let r = (0.5 + 2.6 * f) * u
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(ink.opacity(0.18)))
                    x += step
                }
                y += step; row += 1
            }
        case .chevrons:
            for k in 0..<14 {
                var p = Path()
                let x = w * 0.45 + CGFloat(k) * 16 * u
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + h * 0.32, y: h * 0.5)); p.addLine(to: CGPoint(x: x, y: h))
                line(p, k % 2 == 0 ? 0.16 : 0.08, k % 2 == 0 ? 1.4 : 0.8)
            }
        }
    }
}

/// «طرح کارت» row in the card form: no design, or one of the ten bank designs (the card's own bank first)
struct CardArtPicker: View {
    @Binding var selection: String?
    let bankKey: String?
    @Environment(\.theme) private var t

    var body: some View {
        let own = CardArt.forBank(bankKey)
        let list = (own.map { [$0] } ?? []) + CardArt.allCases.filter { $0 != own }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                tile(nil) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.soft.opacity(0.15))
                        .overlay(Image(systemName: "nosign").foregroundStyle(t.soft))
                }
                ForEach(list) { a in
                    tile(a.rawValue) { CardArtView(art: a).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous)) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func tile<C: View>(_ key: String?, @ViewBuilder _ content: () -> C) -> some View {
        let on = selection == key
        return Button {
            Haptics.tap()
            selection = key
        } label: {
            VStack(spacing: 4) {
                content()
                    .frame(width: 76, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? t.accent : .clear, lineWidth: 2).padding(-3))
                Text(key.flatMap(CardArt.init(rawValue:))?.title ?? "بدون طرح")
                    .font(AppFont.caption).foregroundStyle(on ? t.accent : t.soft)
            }
        }
        .buttonStyle(.plain)
    }
}
