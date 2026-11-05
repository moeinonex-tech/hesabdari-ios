import SwiftUI
import CoreMotion

// Page-entrance animations (Settings › ظاهر › انیمیشن ورود) and the floating 3D bank cards.
// Patterns used by modern iOS apps: content rises in a short stagger (≈50–60 ms apart) on springs, never all at once,
// and nothing moves when «Reduce Motion» is on.

enum PageFx: String, CaseIterable, Identifiable {
    case none, rise, spring, flip, blur, slide
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

    private var fx: PageFx { reduce ? .none : (PageFx(rawValue: raw) ?? .rise) }
    private var on: Bool { fx == .none || shown }

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(x: !on && fx == .slide ? 60 : 0, y: !on && fx == .rise ? 26 : 0)
            .scaleEffect(!on && fx == .spring ? 0.88 : (!on && fx == .blur ? 1.04 : 1), anchor: .center)
            .blur(radius: !on && fx == .blur ? 14 : 0)
            .rotation3DEffect(.degrees(!on && fx == .flip ? 62 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
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
        case .none: anim = .default
        }
        withAnimation(anim.delay(delay)) { shown = true }
    }
}

extension View {
    /// the page-entrance animation chosen in Settings; `index` = place on the page (sets the stagger)
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
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
            Text("هر بار که وارد صفحه‌ای می‌شوید، کارت‌ها با همین حرکت ظاهر می‌شوند و نمودارهای دایره‌ای یک دور می‌چرخند. اگر «کاهش حرکت» آیفون روشن باشد، انیمیشنی پخش نمی‌شود.").font(AppFont.caption)
        }
        Section {
            Toggle(isOn: $float) { Label("کارت‌های بانکی معلق و سه‌بعدی", systemImage: "rotate.3d") }
        } footer: {
            Text("کارت‌ها با کج کردن گوشی کمی می‌چرخند، سایه و نورشان جابه‌جا می‌شود و آرام در هوا بالا و پایین می‌روند.").font(AppFont.caption)
        }
    }
}
