import SwiftUI
import CoreMotion

// Page-entrance animations (Settings › ظاهر › انیمیشن ورود) and the floating 3D bank cards.
// Patterns used by modern iOS apps: content rises in a short stagger (≈50–60 ms apart) on springs, never all at once,
// and nothing moves when «Reduce Motion» is on.

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
        case .neon: return "خط نئونی (هماهنگ با داک)"
        }
    }
    var note: String {
        switch self {
        case .none: return "کارت‌ها بی‌حرکت ظاهر می‌شوند"
        case .rise: return "هر کارت کمی بعد از قبلی، نرم از پایین بالا می‌آید — رایج‌ترین الگوی اپ‌های بانکی"
        case .spring: return "کارت‌ها از کمی کوچک‌تر با حرکت فنری به اندازه‌ی خود می‌رسند"
        case .flip: return "کارت‌ها از لبه‌ی بالا مثل ورق دفتر به جلو می‌چرخند"
        case .blur: return "کارت‌ها از حالت مات و بلوری، شفاف و واضح می‌شوند"
        case .slide: return "کارت‌ها یکی‌یکی از سمت راست صفحه وارد می‌شوند"
        case .neon: return "همان خط درخشان داک دور لبه‌ی هر کارت می‌دود و خاموش می‌شود"
        }
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

private struct Entrance: ViewModifier {
    let index: Int
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    @State private var trace: CGFloat = 0
    @State private var glow: Double = 0
    @Environment(\.theme) private var t

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }
    private var on: Bool { fx == .none || shown }

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(x: !on && fx == .slide ? 60 : 0, y: !on && fx == .rise ? 26 : 0)
            .scaleEffect(!on && fx == .spring ? 0.88 : (!on && fx == .blur ? 1.04 : 1), anchor: .center)
            .blur(radius: !on && fx == .blur ? 14 : 0)
            .rotation3DEffect(.degrees(!on && fx == .flip ? 62 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
            .overlay {
                if fx == .neon && glow > 0 {
                    // the dock's light line: same colour, width and two-layer glow, running once around the card's edge
                    NeonTrace(p: trace)
                        .stroke(t.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: t.accent.opacity(0.85), radius: 4)
                        .shadow(color: t.accent.opacity(0.45), radius: 9)
                        .opacity(glow)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { if active { play() } }
            .onChange(of: active) { _, now in
                if now { shown = false; play() } else { shown = false }
            }
    }

    private func play() {
        guard fx != .none else { shown = true; return }
        let delay = Double(min(index, 8)) * 0.06
        let anim: Animation
        switch fx {
        case .rise: anim = .spring(duration: 0.55, bounce: 0.18)
        case .spring: anim = .spring(duration: 0.55, bounce: 0.38)
        case .flip: anim = .spring(duration: 0.75, bounce: 0.14)
        case .blur: anim = .easeOut(duration: 0.5)
        case .slide: anim = .spring(duration: 0.55, bounce: 0.22)
        case .neon: anim = .easeOut(duration: 0.35)
        case .none: anim = .default
        }
        withAnimation(anim.delay(delay)) { shown = true }
        if fx == .neon {
            trace = 0; glow = 1
            withAnimation(.easeInOut(duration: 0.85).delay(delay)) { trace = 1.32 }
            withAnimation(.easeOut(duration: 0.5).delay(delay + 0.8)) { glow = 0 }
        }
    }
}

extension View {
    /// the page-entrance animation chosen in Settings; `index` = place on the page (sets the stagger)
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

/// a bright segment that travels once around a rounded card (p: 0 → 1.32)
struct NeonTrace: Shape {
    var p: CGFloat
    var animatableData: CGFloat {
        get { p }
        set { p = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let from = max(0, p - 0.32), to = min(1, p)
        guard to > from else { return Path() }
        return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect).trimmedPath(from: from, to: to)
    }
}

// MARK: - charts and numbers follow the same choice

/// Each card style has its own matching motion for charts:
/// rise = bars grow one after another · spring = all bars jump up together with a bounce · flip = the chart tips up
/// from its base in 3D · blur = the chart clears out of a haze · slide = bars grow in a wave from the right ·
/// neon = bars light up quickly with the dock's glow, which then fades. A ring (donut) gets the matching turn.
enum RevealKind { case bars, ring }

struct ChartReveal: ViewModifier {
    let kind: RevealKind
    let count: Int
    @Binding var levels: [Double]
    let glowColor: Color
    @AppStorage(PageFx.key) private var raw = PageFx.rise.rawValue
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var phase: CGFloat = 1
    @State private var neon: Double = 0
    @State private var job: Task<Void, Never>?

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }

    func body(content: Content) -> some View {
        let q = 1 - phase
        return Group {
            if kind == .ring {
                content
                    .rotationEffect(.degrees(fx == .rise ? -90 * q : fx == .slide ? -180 * q : 0))
                    .scaleEffect(fx == .spring ? 0.5 + 0.5 * phase : fx == .rise ? 0.85 + 0.15 * phase : 1)
                    .rotation3DEffect(.degrees(fx == .flip ? 180 * q : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .offset(x: fx == .slide ? 40 * q : 0)
            } else {
                content
                    .offset(y: fx == .rise ? 12 * q : 0)
                    .scaleEffect(fx == .spring ? 0.94 + 0.06 * phase : 1, anchor: .bottom)
                    .rotation3DEffect(.degrees(fx == .flip ? 75 * q : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                    .offset(x: fx == .slide ? 50 * q : 0)
            }
        }
        .blur(radius: fx == .blur ? 10 * q : 0)
        .opacity(fx == .none ? 1 : 0.15 + 0.85 * phase)
        .shadow(color: glowColor.opacity(0.85 * neon), radius: 4)
        .shadow(color: glowColor.opacity(0.45 * neon), radius: 10)
        .onAppear { if active { play() } }
        .onChange(of: active) { _, now in if now { play() } }
        .onChange(of: count) { _, _ in job?.cancel(); levels = []; phase = 1; neon = 0 }
        .onDisappear { job?.cancel(); levels = []; phase = 1; neon = 0 }
    }

    private func instantly(_ body: () -> Void) {
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr, body)
    }

    private func play() {
        job?.cancel()
        let f = fx
        guard f != .none else { levels = []; phase = 1; return }
        let n = kind == .bars ? count : 0
        instantly { levels = Array(repeating: 0, count: n); phase = 0; neon = 0 }
        let full = { (all: inout [Double]) in for i in all.indices { all[i] = 1 } }
        let step = n > 0 ? min(0.06, 0.6 / Double(n)) : 0
        job = Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
            func grow(_ i: Int, _ a: Animation) { if i < levels.count { withAnimation(a) { levels[i] = 1 } } }
            await wait(0.18)
            if Task.isCancelled { return }
            switch f {
            case .rise:
                withAnimation(.spring(duration: 0.7, bounce: 0.2)) { phase = 1 }
                for i in 0..<n { if Task.isCancelled { return }; grow(i, .spring(duration: 0.55, bounce: 0.15)); await wait(step) }
            case .spring:
                withAnimation(.spring(duration: 0.8, bounce: 0.3)) { phase = 1; full(&levels) }
            case .flip:
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) { phase = 1 }
                await wait(0.15)
                withAnimation(.spring(duration: 0.6, bounce: 0.18)) { full(&levels) }
            case .blur:
                withAnimation(.easeOut(duration: 0.7)) { phase = 1; full(&levels) }
            case .slide:
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { phase = 1 }
                for i in (0..<n).reversed() { if Task.isCancelled { return }; grow(i, .spring(duration: 0.5, bounce: 0.2)); await wait(step) }
            case .neon:
                withAnimation(.easeOut(duration: 0.3)) { phase = 1; neon = 1 }
                if kind == .ring {
                    withAnimation(.easeInOut(duration: 0.35).repeatCount(2, autoreverses: true)) { neon = 0.35 }
                    await wait(0.75)
                }
                for i in 0..<n { if Task.isCancelled { return }; grow(i, .easeOut(duration: 0.3)); await wait(step * 0.7) }
                await wait(0.35)
                withAnimation(.easeOut(duration: 1.0)) { neon = 0 }
            case .none: break
            }
        }
    }
}

/// wraps a chart: `level(i)` is how far bar i has grown (0…1); multiply each bar's value by it
struct Revealing<Content: View>: View {
    var kind: RevealKind = .bars
    let count: Int
    var glow: Color? = nil
    @ViewBuilder let content: (_ level: @escaping (Int) -> Double) -> Content
    @State private var levels: [Double] = []
    @Environment(\.theme) private var t

    var body: some View {
        let lv = levels
        content({ i in i >= 0 && i < lv.count ? lv[i] : 1 })
            .modifier(ChartReveal(kind: kind, count: count, levels: $levels, glowColor: glow ?? t.accent))
    }
}

/// a number that plays the same entrance as the cards: counts up from zero, and per style also rises, pops,
/// flips like a flip-clock, clears from a blur, slides in, or glows like the dock's line
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
    @Environment(\.theme) private var t
    @State private var shown: Double?
    @State private var phase: CGFloat = 1
    @State private var neon: Double = 0

    init(_ value: Int, _ text: @escaping (Int) -> String) {
        self.value = value
        self.text = text
    }

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }

    var body: some View {
        let q = 1 - phase
        CountingText(value: shown ?? Double(value), text: text)
            .offset(x: fx == .slide ? 24 * q : 0, y: fx == .rise ? 10 * q : 0)
            .scaleEffect(fx == .spring ? 0.7 + 0.3 * phase : 1)
            .rotation3DEffect(.degrees(fx == .flip ? 90 * q : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .blur(radius: fx == .blur ? 8 * q : 0)
            .opacity(fx == .none ? 1 : 0.2 + 0.8 * phase)
            .shadow(color: t.accent.opacity(0.9 * neon), radius: 5)
            .onAppear { if active { play() } }
            .onChange(of: active) { _, now in if now { play() } }
            .onChange(of: value) { _, _ in shown = nil }
    }

    private func play() {
        let f = fx
        guard f != .none, value != 0 else { shown = nil; phase = 1; return }
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { shown = 0; phase = 0; neon = 0 }
        let delay = 0.15
        let phaseAnim: Animation
        switch f {
        case .spring: phaseAnim = .spring(duration: 0.6, bounce: 0.45)
        case .flip: phaseAnim = .spring(duration: 0.7, bounce: 0.2)
        case .blur: phaseAnim = .easeOut(duration: 0.6)
        default: phaseAnim = .spring(duration: 0.55, bounce: 0.2)
        }
        withAnimation(phaseAnim.delay(delay)) { phase = 1 }
        if f == .neon {
            withAnimation(.easeOut(duration: 0.25).delay(delay)) { neon = 1 }
            withAnimation(.easeOut(duration: 1.0).delay(delay + 0.9)) { neon = 0 }
        }
        let target = Double(value)
        withAnimation(.easeOut(duration: f == .spring ? 0.7 : 0.9).delay(delay)) {
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

// MARK: - floating 3D bank cards

enum CardFloat {
    static let key = "look.cardFloat"
}

/// device tilt, shared by every card (one sensor stream, ~30 per second, only while a card is on screen)
@MainActor
final class Tilt: ObservableObject {
    static let shared = Tilt()
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    private let mm = CMMotionManager()
    private var users = 0
    private var base: (Double, Double)?

    func start() {
        users += 1
        guard users == 1, mm.isDeviceMotionAvailable else { return }
        base = nil
        mm.deviceMotionUpdateInterval = 1.0 / 30
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            if self.base == nil { self.base = (a.pitch, a.roll) }
            // relative to how the phone was held when the cards appeared, softly smoothed
            let p = a.pitch - (self.base?.0 ?? 0), r = a.roll - (self.base?.1 ?? 0)
            self.pitch += (p - self.pitch) * 0.2
            self.roll += (r - self.roll) * 0.2
        }
    }
    func stop() {
        users = max(0, users - 1)
        if users == 0 { mm.stopDeviceMotionUpdates() }
    }
}

/// the card hovers: it follows the tilt of the phone a few degrees in 3D, its shadow moves the other way, a soft light
/// glides across it, and it slowly bobs up and down
struct FloatingCard: ViewModifier {
    let index: Int
    @AppStorage(CardFloat.key) private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ObservedObject private var tilt = Tilt.shared
    @State private var bob = false

    func body(content: Content) -> some View {
        if !enabled || reduce {
            content
        } else {
            let rx = max(-9, min(9, -tilt.pitch * 28))
            let ry = max(-9, min(9, tilt.roll * 28))
            content
                .overlay {
                    // moving sheen
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
                                   startPoint: UnitPoint(x: 0.0 + ry / 30, y: 0), endPoint: UnitPoint(x: 1.0 + ry / 30, y: 1))
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .allowsHitTesting(false)
                }
                .rotation3DEffect(.degrees(rx), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(ry), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .offset(y: bob ? -3 : 3)
                .shadow(color: .black.opacity(0.22), radius: 18, x: -ry * 1.2, y: 14 + rx * 0.8)
                .animation(.interactiveSpring(response: 0.25), value: rx)
                .onAppear {
                    Tilt.shared.start()
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(Double(index % 3) * 0.4)) { bob = true }
                }
                .onDisappear { Tilt.shared.stop() }
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
            Text("هر بار که وارد صفحه‌ای می‌شوید، کارت‌ها با همین حرکت ظاهر می‌شوند؛ میله‌های نمودار، نمودارهای دایره‌ای و مبلغ‌های اصلی هم حرکت مخصوص همین سبک را دارند (اعداد از صفر می‌شمارند). اگر «کاهش حرکت» آیفون روشن باشد، انیمیشنی پخش نمی‌شود.").font(AppFont.caption)
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
            Toggle(isOn: $float) { Label("کارت‌های بانکی معلق و سه‌بعدی", systemImage: "rotate.3d") }
        } footer: {
            Text("کارت‌ها با کج کردن گوشی کمی می‌چرخند، سایه و نورشان جابه‌جا می‌شود و آرام در هوا بالا و پایین می‌روند.").font(AppFont.caption)
        }
    }
}
