# Daily Expense Tracker

**A BCR product** — Crafted by BCR (BibinCutRiver).
First client: **InsideOut Casa** (insideoutuae.com). Built to be licensed to other companies without code changes.

An offline Android and iPhone app where each person records **their own** daily work expenses in AED on **their own phone** and sees daily, weekly and monthly totals. There is no server, account, cloud, sync or sharing — every installation is independent (“Option A”).

> **Data-loss warning (also shown in Settings).** Records exist only on the phone. If the phone is lost, reset or replaced, or the app is removed or its data cleared, anything recorded since the last **backup** is gone permanently. Users make password-protected backup files themselves (Settings → Create backup); the app reminds them monthly.

---

## What it does

| Area | Behaviour |
|---|---|
| Add expense | Date/time from the phone clock, captured at Save (read-only) · Description dropdown (nothing preselected) · Amount in AED (> 0, ≤ 999,999.99, max 2 decimals) · Remarks (optional, ≤ 250 chars; required for **Other**) |
| Storage | Encrypted SQLite (SQLCipher, AES-256), amounts stored as integer **fils** |
| Edit / delete | Description, amount, remarks editable; capture date/time never changes · delete after confirmation (permanent) |
| Categories | Seeded once: Petrol, Food, Labor, Salik, Carwash, Vehicle Maintenance, Car Parking Fee, Other · add / rename / turn off · duplicates blocked ignoring case and spaces |
| Reports | Daily (default today) · Weekly (Mon–Sun) · Monthly (calendar month) — entries newest first, count, total, per-category subtotals |
| Design | Black-and-white: white screens, near-black text and buttons, black Today card and lock screen, black app icon; red only for errors and Delete |
| Security | Device unlock (biometric with PIN/passcode fallback), relock after 2 min in background, screenshot block (Android), app-switcher cover (both), no backups, no network |
| Licensing | Per client, either **company licence** (pre-activated build: install and use, optional end date, then read-only) or **per-phone activation** (request code bound to a hardware key). InsideOut Casa: company licence, no end date. |
| Backup / new phone | Settings → **Create backup**: one encrypted file (SQLCipher, user password ≥ 8 chars) saved wherever the user chooses via the phone's own file picker · new phone: activate, then **Restore** (only into an empty app) · monthly reminder on Home · activation never travels in a backup |

Not included (by design): cloud, sync, shared reports, receipts/OCR, VAT, reimbursements, bank links, GPS, other currencies, CSV/PDF export, charts.

## Repository layout

```
lib/
  core/        money (fils), dates/periods, capture stamp, UUID
  domain/      models + validation rules
  data/        SQLCipher database, migrations, repositories
  platform/    native bridge interface, DB-key store, file layout
  security/    device authentication, activation service
  state/       ChangeNotifier controllers (gate, home, form, reports, categories)
  ui/          screens and widgets
packages/bcr_activation/   pure-Dart activation format (shared by app + admin tool)
admin_cli/                 det_admin: issuer keys + signing activation requests
config/clients/            per-client build config (PUBLIC keys only)
android/  ios/             platform projects (Kotlin/Swift bridge in MainActivity.kt / AppDelegate.swift)
tool/release_check.dart    release APK gate
test/                      unit, repository, controller, gate, privacy and 10k-record tests
docs/                      ANDROID, IOS_MAC, ACTIVATION, SECURITY_PRIVACY, RELEASE, TEST_REPORT
```

## Architecture in one paragraph

UI → controllers → repositories → SQLite. **State management:** plain Flutter `ChangeNotifier` controllers passed down through one small `InheritedWidget` (`AppScope`) and rebuilt with `ListenableBuilder` — no third-party state package, so there is nothing extra to learn or keep updated. The `AppGateController` runs start-up as a state machine: *install check → device security → unlock → open encrypted DB → activation → ready*. Every committed change bumps a revision counter so Home and Reports refresh immediately. Lists page through the database (40 at a time, keyset paging); reports aggregate in SQL over indexed `local_date` ranges.

## Dependencies (resolved 2026-10-02 against Flutter 3.47.6 / Dart 3.13.5)

| Package | Why | Verified |
|---|---|---|
| `sqlite3` 3.7.0 (`hooks: source: sqlcipher`) | SQLCipher build for Android + iOS | App refuses to start if `PRAGMA cipher_version` is empty; tests prove the file is unreadable without the key |
| `flutter_secure_storage` 11.2.0 | Holds the random DB key | Android Keystore-wrapped; `resetOnError: false` (default would erase the key) · iOS `first_unlock_this_device`, `synchronizable: false` |
| `local_auth` 3.0.2 | Biometric + device credential | `biometricOnly: false`; all `LocalAuthExceptionCode`s handled |
| `path_provider` 2.1.6 | App-private durable directory | `getApplicationSupportDirectory()` (not cache) |
| `pointycastle` 4.0.0 | ECDSA P-256 verification in Dart | Interop with OpenSSL 3.2.4 proven both ways |
| `androidx.appcompat` 1.8.0 | AppCompat theme required by local_auth on Android ≤ 8 | Google Maven stable |

The lockfiles (`pubspec.lock`, `admin_cli/pubspec.lock`, `packages/bcr_activation/pubspec.lock`) are committed.

## Quick start (development)

Prerequisites: Flutter 3.47.x stable, JDK 17+ (21 used here), Android SDK 36. On this PC everything is user-local in `C:\Bibin\_tools`; load it per terminal with `. C:\Bibin\_tools\env.ps1`.

```bash
flutter pub get
flutter test                                   # all tests incl. 10k-record measurement
flutter build apk --debug --dart-define-from-file=config/clients/dev.json
```

Debug builds still require activation. Sign a dev token with the admin tool (`docs/ACTIVATION.md`), or — **debug builds only** — add `--dart-define=DET_DEV_BYPASS=true`. Release builds compile the bypass out and `tool/release_check.dart` verifies it.

Build for a client:

```bash
flutter build apk --release --dart-define-from-file=config/clients/insideout-casa.json
dart run tool/release_check.dart --apk build/app/outputs/flutter-apk/app-release.apk --config config/clients/insideout-casa.json
```

## Selling to another client

1. `dart run admin_cli/bin/det_admin.dart init-issuer --client acme-trading`
2. `dart run admin_cli/bin/det_admin.dart write-config --client acme-trading --name "ACME Trading" --out config/clients/acme-trading.json`
3. Build with `--dart-define-from-file=config/clients/acme-trading.json`.

Same app id and signing key for all clients; each client has its own issuer key, so a token for one company never activates another company’s build.

## Documentation

- [docs/ANDROID.md](docs/ANDROID.md) — build, signing, install, Android developer verification
- [docs/PHONE_TESTING.md](docs/PHONE_TESTING.md) — install on a phone, activate it, 23-step test script
- [docs/IOS_MAC.md](docs/IOS_MAC.md) — exact Mac/Xcode steps, Ad Hoc pilot, ongoing distribution
- [docs/ACTIVATION.md](docs/ACTIVATION.md) — admin utility, key formats, procedures, limits
- [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md) — what is protected and what is not
- [docs/RELEASE.md](docs/RELEASE.md) — release checklist, keeping signing identity and migrations safe
- [docs/TEST_REPORT.md](docs/TEST_REPORT.md) — what was verified, measured, and what still needs devices

---

© 2026 BCR (BibinCutRiver). All rights reserved. Third-party licences: in-app under Settings → About → Open-source licences.
