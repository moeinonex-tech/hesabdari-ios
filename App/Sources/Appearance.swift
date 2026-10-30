import SwiftUI
import CoreMotion
import PhotosUI
import HesabCore

// Look-and-feel preferences of this phone (kept on the device, not in the backup):
// page transition, home card effect, Liquid Glass amount, custom background photo.

enum Look {
    static let cardFxKey = "look.cardFx"          // none | glint | parallax | scroll
    static let glassKey = "look.glass"            // 0...100, how "liquid" (clear) the cards are
    static let bgVersionKey = "look.bgVersion"    // bumps when the photo changes

    static var backgroundURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("background.jpg")
    }

    static func saveBackground(_ img: UIImage) throws {
        guard let url = backgroundURL else { return }
        let maxSide: CGFloat = 2000
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: url, options: .atomic)
        BackgroundCache.shared.reload()
    }

    static func removeBackground() {
        if let url = backgroundURL { try? FileManager.default.removeItem(at: url) }
        BackgroundCache.shared.reload()
    }
}

final class BackgroundCache {
    static let shared = BackgroundCache()
    private(set) var image: UIImage?
    init() { reload() }
    func reload() {
        image = Look.backgroundURL.flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
    }
}

// MARK: - home card effects
// glint: a Liquid-Glass style light streak that follows the phone's tilt (Wallet / iOS 26+ lock screen)
// parallax: the card leans with the phone in 3D (Apple TV / Wallet passes)
// scroll: cards scale and fade in as they scroll into view (App Store, Photos)

enum CardFx: String, CaseIterable, Identifiable {
    case none, glint, parallax, scroll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "بدون افکت"
        case .glint: return "درخشش شیشه‌ای با حرکت گوشی"
        case .parallax: return "پارالاکس سه‌بعدی"
        case .scroll: return "ظاهر شدن با اسکرول"
        }
    }
}

@MainActor
final class Tilt: ObservableObject {
    static let shared = Tilt()
    @Published var roll: Double = 0     // -1...1
    @Published var pitch: Double = 0
    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            self.roll = max(-1, min(1, a.roll / 0.6))
            self.pitch = max(-1, min(1, (a.pitch - 0.7) / 0.6))
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

struct CardEffect: ViewModifier {
    let fx: CardFx
    let corner: CGFloat
    @ObservedObject private var tilt = Tilt.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        switch fx {
        case .none:
            content
        case .glint:
            content
                .overlay {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.55)
                            .rotationEffect(.degrees(20))
                            .offset(x: (tilt.roll + 1) / 2 * g.size.width * 1.4 - g.size.width * 0.45, y: tilt.pitch * 20)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .allowsHitTesting(false)
                }
                .onAppear { tilt.start() }
                .onDisappear { tilt.stop() }
        case .parallax:
            content
                .rotation3DEffect(.degrees(tilt.roll * 6), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-tilt.pitch * 5), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .animation(.interactiveSpring(duration: 0.25), value: tilt.roll)
                .onAppear { tilt.start() }
                .onDisappear { tilt.stop() }
        case .scroll:
            content
                .scrollTransition(.interactive, axis: .vertical) { v, phase in
                    v.scaleEffect(phase.isIdentity ? 1 : 0.9)
                        .opacity(phase.isIdentity ? 1 : 0.35)
                        .blur(radius: phase.isIdentity ? 0 : 1.5)
                }
        }
    }
}

// MARK: - settings section


struct AppearanceSection: View {
    @AppStorage(Look.cardFxKey) private var cardFx = CardFx.none.rawValue
    @AppStorage(Look.glassKey) private var glass: Double = 0
    @AppStorage(Look.bgVersionKey) private var bgVersion = 0
    @State private var photo: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        Section {
            Picker("افکت کارت‌های خانه", selection: $cardFx) {
                ForEach(CardFx.allCases) { Text($0.title).tag($0.rawValue) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("میزان لیکوئید گلس")
                    Spacer()
                    Text(Money.persianDigits(String(Int(glass))) + "٪").foregroundStyle(.secondary)
                }
                Slider(value: $glass, in: 0...100, step: 5)
                Text(glass == 0 ? "کارت‌های مات (حالت فعلی)" : glass >= 95 ? "شیشه‌ی کاملاً شفاف" : "شیشه‌ی مایع با رنگ کمتر")
                    .font(AppFont.caption).foregroundStyle(.secondary)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label(BackgroundCache.shared.image == nil ? "انتخاب عکس پس‌زمینه" : "تغییر عکس پس‌زمینه", systemImage: "photo.on.rectangle")
            }
            if BackgroundCache.shared.image != nil {
                Button("برگرداندن پس‌زمینه‌ی پیش‌فرض", role: .destructive) {
                    Look.removeBackground()
                    bgVersion += 1
                }
            }
            if let e = error { Text(e).font(AppFont.caption).foregroundStyle(.red) }
        } header: {
            Text("ظاهر").font(AppFont.medium(13))
        } footer: {
            Text("این تنظیمات فقط روی همین گوشی است و داخل فایل پشتیبان نمی‌رود. برای تغییر اندازه‌ی ویجت‌های خانه، روی یک ویجت انگشت نگه دارید و دستگیره‌ی گوشه‌اش را بکشید.")
                .font(AppFont.caption)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        try Look.saveBackground(img)
                        bgVersion += 1
                    }
                } catch { self.error = "عکس ذخیره نشد: " + error.localizedDescription }
                photo = nil
            }
        }
    }
}
