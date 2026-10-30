import SwiftUI
import UIKit

// MARK: - palettes (owner's choice: all four selectable, default = the web colors)

enum Palette: String, CaseIterable, Identifiable {
    case web, navyGold, emerald, indigo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "آبی و فیروزه‌ای (همان وب)"
        case .navyGold: return "سرمه‌ای و طلایی"
        case .emerald: return "زمردی"
        case .indigo: return "نیلی"
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
        let onAccent: Color
    }

    func colors(_ scheme: ColorScheme) -> Colors {
        let dark = scheme == .dark
        switch self {
        case .web:   // app.html :root and html[data-theme="dark"]
            return dark
                ? Colors(accent: .hex(0x3E9BFF), accent2: .hex(0x39DCC4), paper: .hex(0x08090C), card: .hex(0x1B1C22),
                         ink: .hex(0xF3F4F7), soft: .hex(0x9BA0AC), danger: .hex(0xFF5C78), success: .hex(0x33D188),
                         warning: .hex(0xFFB020), onAccent: .hex(0x08090C))
                : Colors(accent: .hex(0x0A7CFF), accent2: .hex(0x22B8A6), paper: .hex(0xEDEFF3), card: .hex(0xF5F7FA),
                         ink: .hex(0x161822), soft: .hex(0x585C68), danger: .hex(0xF0435F), success: .hex(0x1FAE74),
                         warning: .hex(0xC77700), onAccent: .white)
        case .navyGold:
            return dark
                ? Colors(accent: .hex(0xD9B45A), accent2: .hex(0x7FA7D9), paper: .hex(0x0B1020), card: .hex(0x1C2234),
                         ink: .hex(0xF2EEE4), soft: .hex(0xA3A9B8), danger: .hex(0xFF6B7F), success: .hex(0x4FD18F),
                         warning: .hex(0xFFB84D), onAccent: .hex(0x0B1020))
                : Colors(accent: .hex(0x1F3A5F), accent2: .hex(0xB8892E), paper: .hex(0xF1EEE7), card: .hex(0xFFFDF8),
                         ink: .hex(0x1B2433), soft: .hex(0x5E6675), danger: .hex(0xC8364F), success: .hex(0x1E8E5A),
                         warning: .hex(0xB86E00), onAccent: .white)
        case .emerald:
            return dark
                ? Colors(accent: .hex(0x3DDBA4), accent2: .hex(0x7AA7FF), paper: .hex(0x07100D), card: .hex(0x182620),
                         ink: .hex(0xEEF5F1), soft: .hex(0x97A8A0), danger: .hex(0xFF6B7F), success: .hex(0x3DDBA4),
                         warning: .hex(0xFFB84D), onAccent: .hex(0x07100D))
                : Colors(accent: .hex(0x0E8F6A), accent2: .hex(0x2F6FDB), paper: .hex(0xECF1EE), card: .hex(0xFFFFFF),
                         ink: .hex(0x14211C), soft: .hex(0x53635C), danger: .hex(0xD23A55), success: .hex(0x0E8F6A),
                         warning: .hex(0xB86E00), onAccent: .white)
        case .indigo:
            return dark
                ? Colors(accent: .hex(0x8E8CFF), accent2: .hex(0xFF7A9C), paper: .hex(0x0A0A14), card: .hex(0x202034),
                         ink: .hex(0xF1F0FA), soft: .hex(0xA3A2B8), danger: .hex(0xFF6B7F), success: .hex(0x4FD18F),
                         warning: .hex(0xFFB84D), onAccent: .hex(0x0A0A14))
                : Colors(accent: .hex(0x5B5BD6), accent2: .hex(0xE0577A), paper: .hex(0xEEEEF6), card: .hex(0xFFFFFF),
                         ink: .hex(0x1A1A2E), soft: .hex(0x5C5C70), danger: .hex(0xD23A55), success: .hex(0x1E8E5A),
                         warning: .hex(0xB86E00), onAccent: .white)
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
    var padding: CGFloat = 16

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let v = glass / 100
        let base = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

extension View {
    func glassCard(padding: CGFloat = 16) -> some View { modifier(GlassCard(padding: padding)) }
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
