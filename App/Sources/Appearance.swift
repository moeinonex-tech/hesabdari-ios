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

// MARK: - card effect (every card in the app)

enum CardFx: String, CaseIterable, Identifiable {
    case none, scroll
    var id: String { rawValue }
    var title: String { self == .none ? "بدون افکت" : "ظاهر شدن با اسکرول" }
    /// old saved values (glint / parallax) fall back to «none»
    static func from(_ raw: String) -> CardFx { CardFx(rawValue: raw) ?? .none }
}

struct CardEffect: ViewModifier {
    let fx: CardFx
    var corner: CGFloat = 24

    @ViewBuilder
    func body(content: Content) -> some View {
        switch fx {
        case .none:
            content
        case .scroll:
            content
                .scrollTransition(.interactive, axis: .vertical) { v, phase in
                    v.scaleEffect(phase.isIdentity ? 1 : 0.92)
                        .opacity(phase.isIdentity ? 1 : 0.4)
                }
        }
    }
}

// MARK: - tab switching (Telegram-style slide)

enum TabOrder {
    static let order: [AppTab] = [.home, .ledger, .personal, .reminders, .cards, .search]
    static func index(_ t: AppTab) -> Int { order.firstIndex(of: t) ?? 0 }
}

/// The page that becomes visible slides in from the side of the tab you came from (tabs run right→left in RTL),
/// with a short spring — like switching chat folders in Telegram.
struct TabSlide: ViewModifier {
    let tab: AppTab
    let current: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .onChange(of: current) { old, now in
                guard now == tab, !reduceMotion else { return }
                // RTL: a tab further along the bar sits to the left → the new page enters from the left
                let forward = TabOrder.index(now) > TabOrder.index(old)
                let w = UIScreen.main.bounds.width
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { x = forward ? -w * 0.35 : w * 0.35 }
                DispatchQueue.main.async { withAnimation(.spring(duration: 0.34, bounce: 0.12)) { x = 0 } }
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
            Picker("افکت کارت‌ها", selection: $cardFx) {
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
