# تحویل کامل پروژه‌ی «دفتر حساب» (iOS)

تاریخ: ۱۸ آبان ۱۴۰۵ (۸ نوامبر ۲۰۲۶) — آخرین نسخه: **0.36.0**

این سند برای این است که اگر روی حساب دیگری (یا با برنامه‌نویس/هوش مصنوعی دیگری) کار را ادامه دادید، چیزی گم نشود.
نسخه‌ی کوتاه و الزامی قوانین در `CLAUDE.md` در ریشه‌ی مخزن است.

---

## ۱. پروژه چیست
- نسخه‌ی بومی iOS (SwiftUI، iOS 26) از وب‌اپ تک‌فایلی «دفتر حساب» (`app.html`، مرجع رفتار و ساختار داده).
- داده دقیقاً همان شکل JSON وب‌اپ است؛ پشتیبان iOS در وب باز می‌شود و برعکس.
- صاحب پروژه مک ندارد: ساخت، تست و امضا روی GitHub Actions انجام می‌شود و اپ از TestFlight نصب می‌شود.

## ۲. جاهایی که پروژه نگه داشته می‌شود
| چیز | کجا |
|---|---|
| کد و کل تاریخچه | GitHub: `moeinonex-tech/hesabdari-ios` (عمومی) + فایل `hesabdari-ios.bundle` در بسته‌ی پشتیبان |
| کلیدهای اپل | فقط در GitHub Secrets (نام‌ها در بخش ۴)؛ اصل فایل `.p8` نزد خودتان |
| اپ در اپل | App Store Connect → همان اپ «دفتر حساب» و TestFlight |
| iCloud | کانتینر iCloud روی همان Bundle ID (پشتیبان iCloud Drive) |
| داده‌ی واقعی شما | فقط روی گوشی و پشتیبان‌های خودتان — هرگز داخل مخزن نیست |

## ۳. ساختار کد
- `HesabCore/` بسته‌ی Swift بدون رابط کاربری، تمام منطق:
  - `Jalali`, `Money` (قالب مبلغ و حروف)، `Commission` (موتور کمیسیون با قواعد تأییدشده — README)
  - `LedgerOps`, `RecordOps`, `ReminderOps`, `AccountOps`, `SettingsOps`, `CategoryOps` — هر تغییری روی داده یک تابع است
    که state جدید برمی‌گرداند. اپ آن را با `AppModel.change(...)` اعمال می‌کند (ذخیره + «برگردان»).
  - `Learning` (پیشنهاد دسته/زیردسته)، `NotesImport` (ورود از یادداشت)، `QuoteBulk` (جمله‌های انگیزشی)، `ReportCharts`,
    `Export`/`BackupImport` (پشتیبان و Excel).
  - `HesabStore` — ذخیره‌ی همان JSON در SQLite (GRDB).
- `HesabCore/Tests` — ۵۸ تست (برابری با وب، کمیسیون، دسته‌ها، جمله‌ها …). `Goldens/` دست‌کاری نشود.
- `App/Sources` — SwiftUI:
  - `HesabdariApp.swift` مدل اصلی (`AppModel`)، `Screens.swift` (ریشه)، `HomeScreen.swift`، `LedgerScreen.swift`، `CardsScreen.swift`، `SettingsScreen.swift`، `Reports.swift` گزارش‌ها،
    `PersonalAndReminders.swift`, `Dock.swift` (داک و موج نئونی)، `CardDeck.swift` (کارت‌های جابه‌جاشدنی)،
    `ScrollKit.swift` + `Segmented.swift` (سوایپ صفحه‌ها)، `Motion.swift` (انیمیشن ورود، نوار نئونی، اعداد شمارنده)،
    `CardArt.swift` (طرح ۱۰ بانک)، `CategoryManager.swift` (مدیریت دسته‌ها)، `PDFReport.swift` (همه‌ی PDFها).
- `App/Report/` — `report.css` و `paginate.js`: موتور صفحه‌بندی خود اپ (هر صفحه یک جعبه‌ی دقیق A4، 1px = 1pt).
- `App/UITests/SmokeTests.swift` — تست خودکار روی شبیه‌ساز با داده‌ی ساختگی.
- `project.yml` — تعریف XcodeGen (پروژه‌ی Xcode در CI ساخته می‌شود). `MARKETING_VERSION` همین‌جاست.

## ۴. ساخت و انتشار (CI)
فایل: `.github/workflows/ios.yml` — با هر push روی `main`:
1. **HesabCore parity tests** — `swift test`.
2. **UI smoke test** — ساخت Debug برای شبیه‌ساز آیفون و اجرای `SmokeTests`: همه‌ی صفحه‌ها، حذف/جایگزینی دسته‌ها، باز شدن تنظیمات با ⚙︎،
   ثبت یک هزینه از فرم، ساخت PDF از کارت، و خروجی پشتیبان بخشی.
3. **Archive and upload to TestFlight** — آرشیو بدون امضا ← افزودن entitlements (iCloud) ← امضای ابری با کلید API ← آپلود.

Secrets لازم (Settings → Secrets and variables → Actions):
`APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (کل متن فایل p8).
Variables: `TESTFLIGHT_ENABLED=true`, `BUNDLE_ID` (همان Bundle ID اپ)، `ICLOUD_ENABLED=true`.
جزئیات ساخت کلید و Bundle ID: `docs/SETUP_FA.md`.

نکته‌ها:
- مخزن عمومی است تا دقیقه‌های macOS رایگان و نامحدود باشد. اگر خصوصی شود، دقیقه‌ها ۱۰ برابر حساب می‌شوند.
- اگر اجرا با «runner not acquired» گیر کرد: Re-run failed jobs، یا از تب Actions → iOS → Run workflow.
- شماره‌ی build = شماره‌ی اجرای CI؛ نسخه = `MARKETING_VERSION`.

## ۵. انتقال به حساب دیگر (گام‌به‌گام)
**GitHub جدید:**
1. مخزن تازه بسازید. از بسته‌ی پشتیبان: `git clone hesabdari-ios.bundle hesabdari-ios` سپس
   `git remote set-url origin https://github.com/<حساب-جدید>/hesabdari-ios.git` و `git push -u origin main --tags`.
   (یا در GitHub از Settings → Transfer ownership مخزن فعلی را منتقل کنید — ساده‌ترین راه.)
2. Secrets و Variables بخش ۴ را دوباره وارد کنید.

**اپل (فقط اگر حساب Apple Developer هم عوض شود):**
1. Bundle ID جدید + کانتینر iCloud جدید بسازید و در `BUNDLE_ID` بگذارید (کانتینر از روی آن ساخته می‌شود؛
   بخش `entitlements` در `project.yml` و مرحله‌ی Embed entitlements در workflow را ببینید).
2. اپ جدید در App Store Connect و کلید API جدید (Admin).
3. توجه: اپ با Bundle ID جدید، اپ دیگری است؛ داده را با «پشتیبان → بازیابی» منتقل کنید (فایل پشتیبان JSON/iCloud).

**Claude (یا هر دستیار دیگر):**
- مخزن را وصل کنید و بگویید «اول `CLAUDE.md` و `docs/HANDOFF_FA.md` را بخوان».
- برای PDF، فایل `app.html` (در بسته‌ی پشتیبان) مرجع رفتار وب است.

## ۶. روش کار و عیب‌یابی که استفاده شد
1. **منطق اول در HesabCore + تست.** هر قابلیت داده‌ای اول تابع خالص و تست می‌گیرد؛ CI آن را روی مک ابری اجرا می‌کند.
2. **خطای ساخت:** از annotationهای GitHub (`gh api .../check-runs/<id>/annotations`) — CI خطاهای Swift را با فایل و خط می‌نویسد.
3. **کرش و رفتار رابط:** تست شبیه‌ساز (`ui-smoke`) با داده‌ی ساختگی. سوییچ‌های فقط-Debug:
   - `UITEST_STATE` = JSON داده‌ی ساختگی (در حافظه، Face ID خاموش)
   - `UITEST_OPEN=categories` = باز کردن مستقیم مدیریت دسته‌ها
   - در صورت پیدا نشدن عنصر، درخت دسترسی‌پذیری در annotationها چاپ می‌شود.
4. **PDF:** نمونه‌سازی محلی با Chromium/Playwright و همان `paginate.js`/`report.css` (پوشه‌ی `tools/pdfproto` در بسته‌ی
   پشتیبان)، دیدن صفحه‌ها به صورت عکس، بعد انتقال به Swift. خروجی واقعی گوشی با PDFی که صاحب پروژه می‌فرستد چک می‌شود.
5. **داده‌ی واقعی** فقط محلی و فقط‌خواندنی برای آزمایش؛ هرگز commit نمی‌شود.

## ۷. تصمیم‌های مهم (چرا این‌طور است)
- **صفحه‌بندی PDF:** موتور چاپ iOS برش و فاصله‌ی نامنظم می‌داد ← موتور خود اپ (`paginate.js`)، هر صفحه جدا عکس‌برداری
  و با PDFKit ادغام می‌شود. متای viewport لازم است وگرنه WebKit صفحه را 980px می‌چیند.
- **گزارش دسته/زیردسته (0.36):** خلاصه + یک جدول تک‌ستونی؛ زیردسته‌ها زیر دسته‌ی خودشان؛ ۵ رنگ + خاکستری.
- **سوایپ صفحه‌ها:** UIKit pan با قفل جهت (`PagingPan`)؛ صفحه‌ها `VStack` (نه LazyVStack) چون ارتفاع کهنه می‌ماند.
- **تاریخ:** همه‌چیز با منطقه‌ی زمانی تهران (`Fmt.tehran`)، چون صاحب پروژه در انگلیس است ولی حساب‌ها ایرانی.
- **کمیسیون:** قواعد تأییدشده در README؛ درآمد کمیسیون در شخصی با دسته‌ی «مدیریت پیمان ساختمان».
- **دسته‌ها:** حذف دسته‌ی استفاده‌شده فقط با جایگزین؛ «کمیسیون» و «مدیریت پیمان ساختمان» قفل‌اند.
- **انیمیشن‌ها:** فقط اثر همان سبک؛ نمودار و عدد هیچ‌وقت بلور/درخشش ندارند (تار می‌شدند). نئون با ۵۰٪ شدت.
- **کارت بانکی:** شکل کارت از جعبه‌ی ثابت ۱٫۵۸۶ می‌آید؛ عکس بریده می‌شود. خروجی عکس بدون حاشیه، بدون نوع حساب/انقضا،
  ~۳۰۰۰px. طرح‌های بانک‌ها طراحی اختصاصی با رنگ هر بانک‌اند (کپی طرح چاپی بانک نیستند).

## ۸. کارهای باز / نکته‌های بررسی‌نشده روی گوشی
- خروجی PDF جدید دسته/زیردسته با داده‌ی واقعی هنوز روی گوشی دیده نشده.
- لوگوهای بانک ۱۴۴ پیکسلی‌اند؛ اگر نسخه‌ی باکیفیت‌تر برسد، در `App/Assets.xcassets/BankLogos` جایگزین شود.
- رتبه‌بندی «۱۰ بانک بزرگ» تقریبی است.

## ۹. تاریخچه‌ی تغییرات
فهرست کامل commitها: `docs/DEV_LOG.md` (و در خود git: `git log`).
