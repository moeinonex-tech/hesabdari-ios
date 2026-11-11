import SwiftUI
import UIKit

// MARK: - palettes: the default (web) colors, plus palettes the owner sends. Each sent palette is used in its own order,
// from the main color to the secondary ones.

enum Palette: String, CaseIterable, Identifiable {
    case web
    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "آبی و فیروزه‌ای (پیش‌فرض)"
        }
    }

    /// the colors as sent, main → secondary (shown as swatches in Settings)
    var swatches: [Color] {
        switch self {
        case .web: return [.hex(0x0A7CFF), .hex(0x22B8A6), .hex(0x161822), .hex(0xEDEFF3)]
        }
    }

    struct Colors {
        let accent: Color
        let accent2: Color
        let paper: Color
        let card: Color
        let ink: Color
        let soft: Color
        let danger: Color
        let success: Color
        let warning: Color
        /// پاداش rows: a lime green, clearly apart from the emerald of تنخواه
        var reward: Color { dark ? .hex(0xA8DC4E) : .hex(0x5E9A0E) }
        let onAccent: Color
        var dark = false
    }

    func colors(_ scheme: ColorScheme) -> Colors {
        let dark = scheme == .dark
        switch self {
        case .web:   // app.html :root and html[data-theme="dark"]
            return dark
                ? Colors(accent: .hex(0x3E9BFF), accent2: .hex(0x39DCC4), paper: .hex(0x08090C), card: .hex(0x1B1C22),
                         ink: .hex(0xF3F4F7), soft: .hex(0x9BA0AC), danger: .hex(0xFF5C78), success: .hex(0x33D188),
                         warning: .hex(0xFFB020), onAccent: .hex(0x08090C), dark: true)
                : Colors(accent: .hex(0x0A7CFF), accent2: .hex(0x22B8A6), paper: .hex(0xEDEFF3), card: .hex(0xF5F7FA),
                         ink: .hex(0x161822), soft: .hex(0x585C68), danger: .hex(0xF0435F), success: .hex(0x1FAE74),
                         warning: .hex(0xC77700), onAccent: .white)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "خودکار (مثل گوشی)"
        case .light: return "روشن"
        case .dark: return "تیره"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - environment

struct ThemeKey: EnvironmentKey {
    static let defaultValue = Palette.web.colors(.light)
}

extension EnvironmentValues {
    var theme: Palette.Colors {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Injects the palette for the current light/dark scheme.
struct ThemeHost<Content: View>: View {
    let palette: Palette
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = palette.colors(scheme)
        content
            .environment(\.theme, c)
            .tint(c.accent)
    }
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// "#RRGGBB" from the web data (category colors); nil when malformed.
    static func web(_ s: String?) -> Color? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), t.hasPrefix("#") else { return nil }
        t.removeFirst()
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return .hex(v)
    }
}

// MARK: - font (Vazirmatn, bundled, OFL)

enum AppFont {
    static func regular(_ size: CGFloat, _ style: Font.TextStyle = .body) -> Font { .custom("Vazirmatn-Regular", size: size, relativeTo: style) }
    static func medium(_ size: CGFloat, _ style: Font.TextStyle = .body) -> Font { .custom("Vazirmatn-Medium", size: size, relativeTo: style) }
    static func bold(_ size: CGFloat, _ style: Font.TextStyle = .body) -> Font { .custom("Vazirmatn-Bold", size: size, relativeTo: style) }
    static func heavy(_ size: CGFloat, _ style: Font.TextStyle = .body) -> Font { .custom("Vazirmatn-ExtraBold", size: size, relativeTo: style) }

    static let body = regular(16)
    static let caption = regular(12, .caption)
    static let footnote = regular(13, .footnote)
    static let headline = bold(16, .headline)
    static let title = heavy(28, .largeTitle)

    /// UIKit parts (navigation titles, tab bar, segmented controls).
    static func configureUIKit() {
        if let f = UIFont(name: "Vazirmatn-Bold", size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: f]
            UISegmentedControl.appearance().setTitleTextAttributes([.font: f.withSize(14)], for: .normal)
        }
        if let f = UIFont(name: "Vazirmatn-ExtraBold", size: 32) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: f]
        }
        if let f = UIFont(name: "Vazirmatn-Medium", size: 11) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: f], for: .normal)
        }
    }
}

// MARK: - building blocks

/// Soft colour blobs behind the content, like the web background.
struct AppBackground: View {
    @Environment(\.theme) private var t
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Look.bgVersionKey) private var bgVersion = 0

    var body: some View {
        ZStack {
            if let img = BackgroundCache.shared.image {
                Color.clear.overlay {
                    Image(uiImage: img).resizable().scaledToFill()
                }
                .clipped()
                // keeps text readable on any photo
                (scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.2))
            } else {
                t.paper
                RadialGradient(colors: [t.accent.opacity(0.22), .clear], center: UnitPoint(x: 0.85, y: 0.05), startRadius: 0, endRadius: 360)
                RadialGradient(colors: [t.accent2.opacity(0.17), .clear], center: UnitPoint(x: 0.1, y: 0.5), startRadius: 0, endRadius: 320)
            }
        }
        .id(bgVersion)
        .ignoresSafeArea()
    }
}

/// Card surface. «میزان لیکوئیدی گلس» (0…100): 0 = the frosted card, higher = real Liquid Glass with less tint,
/// 100 = clear glass.
struct GlassCard: ViewModifier {
    @Environment(\.theme) private var t
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Look.glassKey) private var glass: Double = 0
    @AppStorage(Look.cardFxKey) private var cardFx = CardFx.none.rawValue
    var padding: CGFloat = 16
    /// the card effect is for the home page only (widgets get it per cell, the quote card asks for it)
    var effect = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let v = glass / 100
        let base = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if v <= 0.001 {
                base.background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(t.card.opacity(scheme == .dark ? 0.55 : 0.6)))
                        .overlay(shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0.55), lineWidth: 1))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 14, y: 6)
                }
            } else {
                let g: Glass = v >= 0.95 ? .clear : .regular.tint(t.card.opacity((scheme == .dark ? 0.5 : 0.55) * (1 - v)))
                base.glassEffect(g, in: shape)
            }
        }
        .modifier(CardEffect(fx: effect ? CardFx.from(cardFx) : .none))
        .neonEdge(radius: 24)
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, effect: Bool = false) -> some View { modifier(GlassCard(padding: padding, effect: effect)) }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.title).foregroundStyle(t.ink)
            Text(subtitle).font(AppFont.footnote).foregroundStyle(t.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

struct SectionTitle: View {
    let text: String
    @Environment(\.theme) private var t
    var body: some View {
        Text(text).font(AppFont.bold(15)).foregroundStyle(t.ink)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
