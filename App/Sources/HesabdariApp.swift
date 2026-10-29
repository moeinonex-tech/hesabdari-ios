import SwiftUI
import HesabCore

@main
struct HesabdariApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "fa_IR"))
        }
    }
}

/// Pipeline shell only: proves that the app builds, signs and reaches TestFlight,
/// and that HesabCore is linked. Real screens come in Phase 2.
struct ContentView: View {
    private var today: String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let j = Jalali.toJalali(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
        return Money.persianDigits("\(j.jy)/\(j.jm)/\(j.jd)")
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("امروز", value: today)
                    LabeledContent("شماره‌ی ساخت", value: Money.persianDigits(buildNumber))
                } footer: {
                    Text("این نسخه فقط زیرساخت ساخت و ارسال به TestFlight را آزمایش می‌کند. هنوز داده‌ای ذخیره نمی‌کند.")
                }
            }
            .navigationTitle("دفتر حساب")
        }
    }
}
