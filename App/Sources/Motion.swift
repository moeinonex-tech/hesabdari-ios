import SwiftUI

// Page-entrance animations (Settings › ظاهر › انیمیشن ورود) and the 3D bank cards.
// Rules that keep it clean: each style applies only its own effect (no idle filters left on the cards), charts and
// numbers never get blur, glow or 3D (they only grow / count, so they stay sharp), and nothing moves with «Reduce Motion».

enum PageFx: String, CaseIterable, Identifiable {
    case none, rise, spring, flip, blur, slide, neon
    var id: String { rawValue }
    static let key = "look.pageFx"
    var title: String {
        switch self {
        case .none: return "بدون انیمیشن"
        case .rise: return "ظهور پلکانی از پایین"
        case .spring: return "فنری و بزرگ‌شونده"
        case .flip: return "چرخش سه‌بعدی (ورق)"
        case .blur: return "محو از مه (شیشه‌ای)"
        case .slide: return "ورود موجی از کنار"
        case .neon: return "روشن‌شدن نرم (نئونی)"
        }
    }
    var note: String {
        switch self {
        case .none: return "کارت‌ها بی‌حرکت ظاهر می‌شوند"
        case .rise: return "هر کارت کمی بعد از قبلی، نرم از پایین بالا می‌آید — رایج‌ترین الگوی اپ‌های بانکی"
        case .spring: return "کارت‌ها از کمی کوچک‌تر با حرکت فنری به اندازه‌ی خود می‌رسند"
        case .flip: return "کارت‌ها از لبه‌ی بالا مثل ورق دفتر به جلو می‌چرخند"
        case .blur: return "کارت‌ها از حالت مات، شفاف و واضح می‌شوند"
        case .slide: return "کارت‌ها یکی‌یکی از سمت راست صفحه وارد می‌شوند"
        case .neon: return "کارت‌ها پرنور و درخشان ظاهر می‌شوند و نرم به رنگ خودشان برمی‌گردند — بدون چشمک"
        }
    }
    static var current: PageFx {
        PageFx(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .rise
    }
}

// whether the page holding a view is the one on screen (AppShell sets it per page)
private struct PageActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var pageActive: Bool {
        get { self[PageActiveKey.self] }
        set { self[PageActiveKey.self] = newValue }
    }
}

/// shared timing helpers
@MainActor
enum Motion {
    static func instantly(_ body: () -> Void) {
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr, body)
    }
    static func wait(_ s: Double) async {
        if s > 0 { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
    }
}

// MARK: - cards

private struct Entrance: ViewModifier {
    let index: Int
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var p: CGFloat = 0           // 0 hidden → 1 in place
    @State private var job: Task<Void, Never>?

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }

    func body(content: Content) -> some View {
        let q = 1 - p
        Group {
            switch fx {
            case .none: content
            case .rise: content.opacity(p).offset(y: 26 * q)
            case .spring: content.opacity(p).scaleEffect(0.88 + 0.12 * p)
            case .flip: content.opacity(p).rotation3DEffect(.degrees(62 * q), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
            case .blur: content.opacity(p).blur(radius: 12 * q)
            case .slide: content.opacity(p).offset(x: 60 * q)
            case .neon: content.opacity(p).brightness(0.4 * q)
            }
        }
        .onAppear { if active { play() } }
        .onChange(of: active) { _, now in
            job?.cancel()
            if now { play() } else { Motion.instantly { p = 0 } }
        }
        .onDisappear { job?.cancel() }
    }

    private func play() {
        job?.cancel()
        let f = fx
        guard f != .none else { p = 1; return }
        Motion.instantly { p = 0 }
        let delay = Double(min(index, 8)) * 0.06
        let anim: Animation
        switch f {
        case .spring: anim = .spring(duration: 0.55, bounce: 0.38)
        case .flip: anim = .spring(duration: 0.75, bounce: 0.14)
        case .blur: anim = .easeOut(duration: 0.5)
        case .slide: anim = .spring(duration: 0.55, bounce: 0.22)
        case .neon: anim = .easeOut(duration: 0.7)
        default: anim = .spring(duration: 0.55, bounce: 0.18)
        }
        withAnimation(anim.delay(delay)) { p = 1 }
    }
}

extension View {
    /// the page-entrance animation chosen in Settings; `index` = place on the page (sets the stagger)
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

// MARK: - charts follow the same choice (sharp: only the bars' values move)

/// rise = bars grow one after another · spring = all jump up together with a bounce · flip = they open from the middle
/// outward · blur = all rise slowly and softly · slide = a wave from the right · neon = the chart blinks on, bars fast.
/// A ring (donut) gets a matching 2D turn / pop.
enum RevealKind { case bars, ring }

struct ChartReveal: ViewModifier {
    let kind: RevealKind
    let count: Int
    @Binding var levels: [Double]
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var p: CGFloat = 1
    @State private var job: Task<Void, Never>?

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }

    func body(content: Content) -> some View {
        let q = 1 - p
        Group {
            if kind == .ring {
                switch fx {
                case .none: content
                case .rise: content.opacity(p).rotationEffect(.degrees(-90 * q))
                case .spring: content.opacity(p).scaleEffect(0.6 + 0.4 * p)
                case .flip: content.opacity(p).scaleEffect(x: max(0.01, p), y: 1)
                case .blur: content.opacity(p)
                case .slide: content.opacity(p).rotationEffect(.degrees(-180 * q))
                case .neon: content.opacity(p).brightness(0.3 * q)
                }
            } else {
                switch fx {
                case .neon: content.opacity(p).brightness(0.3 * q)
                default: content
                }
            }
        }
        .onAppear { if active { play() } }
        .onChange(of: active) { _, now in if now { play() } else { job?.cancel() } }
        .onChange(of: count) { _, _ in job?.cancel(); levels = []; p = 1 }
        .onDisappear { job?.cancel() }
    }

    private func play() {
        job?.cancel()
        let f = fx
        guard f != .none else { levels = []; p = 1; return }
        let n = kind == .bars ? count : 0
        Motion.instantly { levels = Array(repeating: 0, count: n); p = f == .neon || kind == .ring ? 0 : 1 }
        let step = n > 0 ? min(0.06, 0.6 / Double(n)) : 0
        job = Task { @MainActor in
            func grow(_ i: Int, _ a: Animation) { if i < levels.count { withAnimation(a) { levels[i] = 1 } } }
            func growAll(_ a: Animation) { withAnimation(a) { for i in levels.indices { levels[i] = 1 } } }
            await Motion.wait(0.18)
            if Task.isCancelled { return }
            switch f {
            case .rise:
                if kind == .ring { withAnimation(.spring(duration: 0.7, bounce: 0.15)) { p = 1 } }
                for i in 0..<n { if Task.isCancelled { return }; grow(i, .spring(duration: 0.5, bounce: 0.15)); await Motion.wait(step) }
            case .spring:
                withAnimation(.spring(duration: 0.7, bounce: 0.35)) { p = 1 }
                growAll(.spring(duration: 0.7, bounce: 0.3))
            case .flip:
                if kind == .ring { withAnimation(.spring(duration: 0.6, bounce: 0.2)) { p = 1 } }
                let mid = Double(n - 1) / 2
                let order = (0..<n).sorted { abs(Double($0) - mid) < abs(Double($1) - mid) }
                for i in order { if Task.isCancelled { return }; grow(i, .spring(duration: 0.5, bounce: 0.2)); await Motion.wait(step * 0.8) }
            case .blur:
                withAnimation(.easeOut(duration: 0.7)) { p = 1 }
                growAll(.easeOut(duration: 0.8))
            case .slide:
                if kind == .ring { withAnimation(.spring(duration: 0.8, bounce: 0.15)) { p = 1 } }
                for i in (0..<n).reversed() { if Task.isCancelled { return }; grow(i, .spring(duration: 0.5, bounce: 0.2)); await Motion.wait(step) }
            case .neon:
                withAnimation(.easeOut(duration: 0.7)) { p = 1 }
                for i in 0..<n { if Task.isCancelled { return }; grow(i, .easeOut(duration: 0.3)); await Motion.wait(step * 0.6) }
            case .none: break
            }
        }
    }
}

/// wraps a chart: `level(i)` is how far bar i has grown (0…1); multiply each bar's value by it
struct Revealing<Content: View>: View {
    var kind: RevealKind = .bars
    let count: Int
    var glow: Color? = nil          // kept for call sites; charts no longer glow (it made them look blurry)
    @ViewBuilder let content: (_ level: @escaping (Int) -> Double) -> Content
    @State private var levels: [Double] = []

    var body: some View {
        let lv = levels
        content({ i in i >= 0 && i < lv.count ? lv[i] : 1 })
            .modifier(ChartReveal(kind: kind, count: count, levels: $levels))
    }
}

// MARK: - numbers count up from zero (sharp: no blur, glow or 3D)

private struct CountingText: View, Animatable {
    var value: Double
    let text: (Int) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(text(Int(value.rounded()))) }
}

struct FxNumber: View {
    let value: Int
    let text: (Int) -> String
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double?
    @State private var p: CGFloat = 1
    @State private var job: Task<Void, Never>?

    init(_ value: Int, _ text: @escaping (Int) -> String) {
        self.value = value
        self.text = text
    }

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }

    var body: some View {
        let q = 1 - p
        let label = CountingText(value: shown ?? Double(value), text: text)
        Group {
            switch fx {
            case .none: label
            case .rise: label.opacity(p).offset(y: 10 * q)
            case .spring: label.opacity(p).scaleEffect(0.7 + 0.3 * p)
            case .flip: label.opacity(p).scaleEffect(x: 1, y: max(0.01, p))
            case .blur: label.opacity(p)
            case .neon: label.opacity(p).brightness(0.4 * q)
            case .slide: label.opacity(p).offset(x: 24 * q)
            }
        }
        .onAppear { if active { play() } }
        .onChange(of: active) { _, now in if now { play() } else { job?.cancel() } }
        .onChange(of: value) { _, _ in shown = nil }
        .onDisappear { job?.cancel() }
    }

    private func play() {
        job?.cancel()
        let f = fx
        guard f != .none, value != 0 else { shown = nil; p = 1; return }
        Motion.instantly { shown = 0; p = 0 }
        let delay = 0.15
        switch f {
        case .neon: withAnimation(.easeOut(duration: 0.7).delay(delay)) { p = 1 }
        case .spring: withAnimation(.spring(duration: 0.6, bounce: 0.45).delay(delay)) { p = 1 }
        case .flip: withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(delay)) { p = 1 }
        case .blur: withAnimation(.easeOut(duration: 0.6).delay(delay)) { p = 1 }
        default: withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(delay)) { p = 1 }
        }
        let target = Double(value)
        withAnimation(.easeOut(duration: 0.85).delay(delay)) {
            shown = target
        } completion: {
            if shown == target { shown = nil }
        }
    }
}

// MARK: - dock animation

enum DockFx: String, CaseIterable, Identifiable {
    case wave, off
    var id: String { rawValue }
    static let key = "look.dockFx"
    var title: String {
        switch self {
        case .wave: return "موج نئونی"
        case .off: return "خاموش"
        }
    }
    var note: String {
        switch self {
        case .wave: return "خط درخشان پایین داک که روی آیکون انتخاب‌شده قوس می‌زند و بین صفحه‌ها سُر می‌خورد"
        case .off: return "بدون خط و قوس؛ فقط رنگ آیکون انتخاب‌شده عوض می‌شود"
        }
    }
}

// MARK: - 3D bank cards (no sensors)

enum CardFloat {
    static let key = "look.cardFloat"
}

/// depth without any tilt or motion: a soft light across the top, a fine bright rim, and two layered shadows
/// (a tight one under the card and a wide soft one), so the card reads as lifted off the page.
struct FloatingCard: ViewModifier {
    let index: Int
    @AppStorage(CardFloat.key) private var enabled = true

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            content
                .overlay {
                    ZStack {
                        LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0)], startPoint: .top, endPoint: .center)
                        shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 14)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - settings section

struct MotionSettingsSection: View {
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @AppStorage(CardFloat.key) private var float = true
    @AppStorage(DockFx.key) private var dockRaw = DockFx.wave.rawValue
    @Environment(\.theme) private var t

    var body: some View {
        Section {
            ForEach(PageFx.allCases) { f in
                Button {
                    Haptics.tap()
                    raw = f.rawValue
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: raw == f.rawValue ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(raw == f.rawValue ? t.accent : t.soft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(AppFont.medium(14)).foregroundStyle(t.ink)
                            Text(f.note).font(AppFont.caption).foregroundStyle(t.soft)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("انیمیشن ورود به هر صفحه").font(AppFont.medium(13))
        } footer: {
            Text("هر بار که وارد صفحه‌ای می‌شوید، کارت‌ها با همین حرکت ظاهر می‌شوند؛ میله‌های نمودار، نمودارهای دایره‌ای و مبلغ‌های اصلی هم حرکت مخصوص همین سبک را دارند (اعداد از صفر می‌شمارند) و همیشه واضح می‌مانند. اگر «کاهش حرکت» آیفون روشن باشد، انیمیشنی پخش نمی‌شود.").font(AppFont.caption)
        }
        Section {
            ForEach(DockFx.allCases) { f in
                Button {
                    Haptics.tap()
                    dockRaw = f.rawValue
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: dockRaw == f.rawValue ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(dockRaw == f.rawValue ? t.accent : t.soft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(AppFont.medium(14)).foregroundStyle(t.ink)
                            Text(f.note).font(AppFont.caption).foregroundStyle(t.soft)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("انیمیشن داک").font(AppFont.medium(13))
        }
        Section {
            Toggle(isOn: $float) { Label("کارت‌های بانکی با سایه و عمق", systemImage: "square.stack.3d.down.forward") }
        } footer: {
            Text("کارت‌ها صاف می‌مانند و فقط با نور لبه و سایه‌ی دولایه، برجسته و جدا از صفحه دیده می‌شوند.").font(AppFont.caption)
        }
    }
}
