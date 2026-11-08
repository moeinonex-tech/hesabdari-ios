# CLAUDE.md — instructions for whoever continues this project (human or AI)

Read `docs/HANDOFF_FA.md` first (full handoff, Persian). This file is the short, binding version.

## Owner and communication
- The owner writes Persian and wants replies **in Persian only**, plain and colloquial. Never answer in English.
- The owner has **no Mac**. Everything is built and tested on GitHub Actions (`macos-26`) and installed from TestFlight.
- Report honestly what was and was not verified (CI vs. real device). Don't guess, don't claim things you didn't check.

## Hard rules
1. **Never change financial logic or data** (amounts, commission maths, balances) unless the owner explicitly asks.
   «در ماهیت ابزارها دخل و تصرف نکن» — fix structure/bugs, keep what tools do.
2. **Never commit or publish real user data.** The repo is PUBLIC. Use synthetic fixtures only (see `App/UITests/SmokeTests.swift`).
   The owner's real backup JSON may be used only locally, read-only.
3. **Never ask for or print secrets** (App Store Connect key, Issuer ID, Key ID, .p8). They live only in GitHub Secrets.
4. CVV is never stored or exported.
5. PDF output is the most critical feature: exact A4 (595.28×841.89 pt), nothing cut, no big gaps, table header only on
   page 1, no pay-method legend. Pages are built by `App/Report/paginate.js`; keep the viewport meta in every report HTML.
6. UI consistency: all header buttons use `HeaderIconButton` (same size); one confirm control (✓ in the header).
7. Bump `MARKETING_VERSION` in `project.yml` for every user-visible change; the build number = CI run number.

## Build / test / ship
- Every push to `main` runs `.github/workflows/ios.yml`:
  1. `core-tests` — `swift test --package-path HesabCore` (domain logic, parity with the web app).
  2. `ui-smoke` — XcodeGen + `xcodebuild test` on an iPhone simulator with a synthetic state (Debug-only switches
     `UITEST_STATE`, `UITEST_OPEN`; see `HesabdariApp.swift` / `Screens.swift`). Catches crashes.
  3. `testflight` — unsigned archive → embed entitlements → export with cloud signing (ASC key) → upload.
- Read CI errors via annotations: `gh api repos/<owner>/hesabdari-ios/check-runs/<job-id>/annotations`.
- Commits: `git -c user.name="hesabdari" -c user.email="noreply@anthropic.com" commit` (+ the session's attribution lines).

## Where things are
- `HesabCore/Sources/HesabCore` — pure Swift domain logic, state is web-shaped JSON (`JSONValue`). All changes to data go
  through `*Ops` functions that return a new state; the app applies them with `AppModel.change(...)` (undo built in).
- `HesabCore/Sources/HesabStore` — GRDB/SQLite storage of that JSON.
- `App/Sources` — SwiftUI. Big files: `Screens.swift` (home, ledger, cards, settings hub), `Reports.swift`, `PDFReport.swift`.
- `App/Report` — `report.css` + `paginate.js` (own A4 page engine). Prototype & preview locally with Playwright (see HANDOFF).
