import SwiftUI
import UIKit
import Charts
import UniformTypeIdentifiers
import HesabCore

// MARK: - settings

/// Settings hub: a short list of topics (like the phone's own Settings), each opening its own page.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var showImporter: Bool
    @Binding var exportFile: ExportFile?
    @AppStorage("palette") private var paletteRaw = Palette.web.rawValue
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(AppLock.enabledKey) private var lockEnabled = true
    @AppStorage(Notifier.enabledKey) private var notifyEnabled = true
    @AppStorage(Backups.lastAtKey) private var lastBackupAt: Double = 0
    @AppStorage(Backups.lastICloudKey) private var lastICloud: Int = -2
    @Environment(\.colorScheme) private var scheme
    @Environment(\.theme) private var t

    var body: some View {
        Form {
            Section {
                NavigationLink { appearancePage } label: {
                    SettingsRow(icon: "paintbrush.fill", tint: .indigo, title: "ظاهر",
                                detail: (Palette(rawValue: paletteRaw)?.title ?? "") + " · " + (Appearance(rawValue: appearanceRaw)?.title ?? ""))
                }
                NavigationLink { homePage } label: {
                    SettingsRow(icon: "house.fill", tint: .blue, title: "صفحه‌ی خانه", detail: "ویجت‌ها و جمله‌های انگیزشی")
                }
            }

            Section {
                NavigationLink { PartiesView(model: model) } label: {
                    SettingsRow(icon: "person.2.fill", tint: .teal, title: "طرف‌های حساب", detail: nil)
                }
                NavigationLink { CategoryManagerView(model: model) } label: {
                    SettingsRow(icon: "tag.fill", tint: .orange, title: "دسته‌ها و زیردسته‌ها", detail: "مرور، حذف و جایگزینی")
                }
                .accessibilityIdentifier("settings.categories")
            }

            Section {
                NavigationLink { securityPage } label: {
                    SettingsRow(icon: "lock.fill", tint: .gray, title: "امنیت",
                                detail: (lockEnabled ? "Face ID روشن" : "Face ID خاموش") + (model.hasEditPassword ? " · رمز ردیف‌ها دارد" : ""))
                }
                NavigationLink { notificationsPage } label: {
                    SettingsRow(icon: "bell.badge.fill", tint: .red, title: "اعلان‌ها", detail: notifyEnabled ? "روشن" : "خاموش")
                }
            }

            Section {
                NavigationLink { dataPage } label: {
                    SettingsRow(icon: "externaldrive.fill.badge.icloud", tint: .green, title: "پشتیبان و داده‌ها",
                                detail: lastBackupAt > 0 ? "آخرین پشتیبان: " + Backups.describeLast() : "هنوز پشتیبانی گرفته نشده")
                }
            }

            Section {
            } footer: {
                Text("نسخه‌ی " + Money.persianDigits((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                     + " (" + Money.persianDigits(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")")
                    .font(AppFont.caption).frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("تنظیمات")
    }

    // MARK: pages

    private func page<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Form { content() }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var appearancePage: some View {
        page("ظاهر") {
            Section {
                ForEach(Palette.allCases) { p in
                    let c = p.colors(scheme)
                    Button {
                        Haptics.tap()
                        withAnimation(.smooth) { paletteRaw = p.rawValue }
                    } label: {
                        HStack(spacing: 12) {
                            // the palette's colors in their own order, main → secondary
                            HStack(spacing: -7) {
                                ForEach(Array(p.swatches.enumerated()), id: \.offset) { _, col in
                                    Circle().fill(col).frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                            Text(p.title).font(AppFont.medium(15)).foregroundStyle(t.ink)
                            Spacer()
                            if paletteRaw == p.rawValue {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(c.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("رنگ اصلی").font(AppFont.medium(13))
            }
            Section {
                Picker("حالت نمایش", selection: $appearanceRaw) {
                    ForEach(Appearance.allCases) { a in Text(a.title).tag(a.rawValue) }
                }
            } header: {
                Text("روشن و تیره").font(AppFont.medium(13))
            }
            AppearanceSection()
            MotionSettingsSection()
        }
    }

    private var homePage: some View {
        page("صفحه‌ی خانه") {
            Section {
                NavigationLink { WidgetsSettingsView(model: model) } label: {
                    Label("ویجت‌های خانه", systemImage: "square.grid.2x2")
                }
                NavigationLink { QuotesSettingsView(model: model) } label: {
                    Label("جمله‌های انگیزشی", systemImage: "quote.bubble")
                }
            } footer: {
                Text("برای جابه‌جا کردن یا تغییر اندازه‌ی ویجت‌ها، روی یک ویجت در صفحه‌ی خانه انگشت نگه دارید.").font(AppFont.caption)
            }
        }
    }

    private var securityPage: some View {
        page("امنیت") {
            Section {
                Toggle(isOn: $lockEnabled) { Label("قفل با Face ID", systemImage: "faceid") }
            } footer: {
                Text("وقتی بیش از یک دقیقه از اپ بیرون باشید، Face ID (یا رمز گوشی) خواسته می‌شود.").font(AppFont.caption)
            }
            Section {
                NavigationLink { EditPasswordView(model: model) } label: {
                    Label("رمز ویرایش ردیف‌های قدیمی", systemImage: "lock.rectangle")
                }
            } footer: {
                Text("با رمز، ویرایش و حذف ردیف‌هایی که بیش از ۸ روز از تاریخشان گذشته رمز می‌خواهد.").font(AppFont.caption)
            }
        }
    }

    private var notificationsPage: some View {
        page("اعلان‌ها") {
            Section {
                Toggle(isOn: $notifyEnabled) { Label("اعلان سررسید چک، قسط و قرار", systemImage: "bell.badge") }
                    .onChange(of: notifyEnabled) { _, _ in Notifier.sync(model.state) }
            } footer: {
                Text("شب قبل از سررسید چک و قسط ساعت ۲۰، و قرارها ۳ ساعت قبل (قرار بدون ساعت: ۹ صبح همان روز). برای فرستادن یک چک یا قرار به Reminders گوشی، در «یادآوری‌ها» انگشت را روی آن نگه دارید.").font(AppFont.caption)
            }
        }
    }

    private var dataPage: some View {
        page("پشتیبان و داده‌ها") {
            Section {
                LabeledContent("آخرین پشتیبان", value: lastBackupAt > 0 ? Backups.describeLast() : "هنوز گرفته نشده")
                LabeledContent("iCloud Drive", value: iCloudText)
                Button {
                    model.backupToday(showErrors: true)
                    Haptics.success()
                } label: {
                    Label("پشتیبان‌گیری همین الان", systemImage: "icloud.and.arrow.up")
                }
            } header: {
                Text("پشتیبان خودکار").font(AppFont.medium(13))
            } footer: {
                Text("بعد از هر تغییر، پشتیبان امروز به‌روز می‌شود: در iCloud Drive › دفتر حساب › پشتیبان‌ها و یک نسخه در Files › On My iPhone › دفتر حساب.").font(AppFont.caption)
            }
            Section {
                Button { exportFile = model.makeExportFile() } label: {
                    Label("خروجی پشتیبان کامل", systemImage: "square.and.arrow.up")
                }
                Button { showImporter = true } label: {
                    Label("ورود دوباره‌ی پشتیبان", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("فایل پشتیبان").font(AppFont.medium(13))
            } footer: {
                Text(model.lastImportText ?? "قالب فایل همان پشتیبان کامل اپ وب است.").font(AppFont.caption)
            }
            Section {
                NavigationLink { SectionBackupView(model: model) } label: {
                    Label("پشتیبان و بازیابی هر بخش جداگانه", systemImage: "square.stack.3d.up")
                }
            } footer: {
                Text("فقط دفتر حساب، فقط شخصی، فقط درآمد، فقط یادآوری‌ها یا فقط کیف کارت — به صورت فایل JSON (برای بازیابی) یا متن (برای خواندن و فرستادن).").font(AppFont.caption)
            }
            Section {
                NavigationLink { DangerZoneView(model: model) } label: {
                    Label("پاک‌سازی (هیستوری یادگیری / همه‌ی اطلاعات)", systemImage: "trash").foregroundStyle(t.danger)
                }
            }
        }
    }

    private var iCloudText: String {
        switch lastICloud {
        case 1: return "ذخیره شد ✓"
        case 0: return "گوشی به iCloud Drive وصل نیست"
        case -2: return "این نسخه‌ی اپ مجوز آیکلود ندارد"
        case -3: return "پوشه‌ی آیکلود اپ هنوز آماده نشده — دوباره امتحان کنید"
        case -1: return "ذخیره نشد"
        default: return "—"
        }
    }
}
