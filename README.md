# دفتر حساب — iOS

The native SwiftUI port of the web app «دفتر حساب». Builds run in the cloud (GitHub Actions `macos-26`), so no Mac is required. Setup steps are in [docs/SETUP_FA.md](docs/SETUP_FA.md).

| Path | Contents |
|---|---|
| `HesabCore/` | Swift package with the domain logic: Jalali calendar, money format, commission engine (approved rules). It has no UI. |
| `HesabCore/Tests/…/Goldens/` | Copies of the Phase 1 goldens. **They are generated outside this repo, so don't edit them by hand.** |
| `App/` | SwiftUI app. It is currently only a shell to verify the pipeline. |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated in CI. |
| `.github/workflows/ios.yml` | Runs the core tests on every push or PR. Archives and uploads to TestFlight only when `TESTFLIGHT_ENABLED=true`. |

## Golden provenance

| File | Source | md5 |
|---|---|---|
| `commission_corrected.json` | phase1 `model/build_expected.js`. In web mode the model matches the real web app 1326/1326. The approved-rule values were checked by hand. | `2162b4a219301bf4535346da3172fe84` |
| `commission_scenarios.json` | phase1 scenarios G01–G22 | `8d9bb7dabbc6eda082f0069333348683` |
| `jalali_days.csv` | The web app's own functions for 1990–2060. 0 mismatches against ICU. | `47a3749ea9ed39b134b1f1486d672587` |

Reference web app: `app.html`, md5 `80e0be42399b1410a518d4c43a8deb72`.

## Commission rules (approved)

1. **Coverage:** a payment covers every expense entered before it (entry order). The financial date never moves an expense between stages.
2. **Running balance:** `due = commission of newly covered expenses + previous balance`; `balanceAfter = due − paid`.
   - Debt carries forward to the next commission.
   - Overpayment becomes credit that reduces the next commission.
   - A full settlement leaves the balance at 0.
   - The balance is stored as a delta in `remainingForStage`, so the web app shows the same balance when it restores an iOS backup.
3. **D16 (approved):** editing a payment amount recomputes the balance of that payment and every later one. `calculatedAmount` is kept.

## Open decisions

D1–D4, D9 and D14 are listed in phase1 `DECISIONS.md`. They affect import of existing data, not this engine.
