# Test report — Daily Expense Tracker 1.0.0+1

Date: 2026-10-02 · Machine: Windows 10 Enterprise 19045, i7-13700H, 16 GB · Flutter 3.47.6 / Dart 3.13.5 · JDK 21.0.12 · Android SDK 36

**Status: development build verified on Windows with automated tests and an Android build. Not tested on any phone, emulator, Mac or iPhone yet. Not production-ready until the device checks below pass.**

## Automated checks run here

| Check | Command | Result |
|---|---|---|
| Formatting | `dart format --output=none --set-exit-if-changed lib test tool admin_cli packages` | PASS (0 changes) |
| Static analysis | `flutter analyze` | PASS (no issues) |
| App tests (incl. real SQLCipher DB) | `flutter test` | PASS — 100 tests (incl. widget smoke test on a 360×640 screen) |
| Activation package | `cd packages/bcr_activation && dart test` | PASS — 15 tests |
| Admin utility | `cd admin_cli && dart test` | PASS — 3 tests |
| OpenSSL interop | manual (see ACTIVATION.md) | PASS — keys and signatures interoperate both ways with OpenSSL 3.2.4 |
| Android debug APK | `flutter build apk --debug --dart-define-from-file=config/clients/dev.json` | PASS |
| Release refuses to build without signing key | `flutter build apk --release …` (no key.properties) | PASS — fails with explanation |
| Release APK gate | `flutter build apk --release -P allowDebugSigningForRelease=true …` + `dart run tool/release_check.dart …` | PASS — 23/23 checks: no INTERNET/ACCESS_NETWORK_STATE, not debuggable, allowBackup=false, backup + data-extraction rules present, dev-bypass text absent from all 3 ABIs. The debug APK correctly FAILS the same gate. |

### What the tests cover (requirement → test)

| Requirement | Test file |
|---|---|
| Amount parsing/precision: fils integers, ≤ 2 decimals, > 0, ≤ 999,999.99, Arabic digits, comma decimal, exact 64-bit sums | `money_and_validation_test.dart` |
| Validation: mandatory category (no preselect), Other needs remark, 250 chars after trim (grapheme-aware) | `money_and_validation_test.dart` |
| AED 100 + 25 + 8 = AED 133, count 3, category totals | `repository_test.dart` |
| Category seed-once, add/rename, duplicates ignoring case/spaces (incl. inactive), deactivation keeps history and reports, blocks new use | `repository_test.dart` |
| Edit preserves capture date/time and creation time; delete permanent; totals update immediately | `repository_test.dart`, `expense_form_test.dart` |
| Duplicate-save protection (3 rapid taps → 1 record); success only after commit; form kept on failure; low storage fails safely | `expense_form_test.dart` |
| Report boundaries: Sun 23:59 vs Mon 00:00, month end, leap day 2028-02-29, year-end week, empty period | `report_boundaries_test.dart` |
| Travel/timezone: stored capture date used, not current timezone | `repository_test.dart` |
| Encryption: file has no SQLite header or plaintext; wrong key refused; newer schema refused untouched | `repository_test.dart` |
| Activation: valid device, different device, modified token, wrong issuer, `alg` swap, wrong client, expiry, copied data to another phone, key-possession proof, bypass rejected outside debug | `activation_token_test.dart`, `activation_service_test.dart` |
| Start-up: first launch, restart persistence, iOS-style reinstall (Keychain survives) vs upgrade, missing key = safe error, no screen lock, cancel/lockout, 2-min relock | `app_gate_test.dart` |
| No logs, no network code/deps, manifest INTERNET removal, backup rules, iOS entitlements, key store options, no destructive migrations, no committed secrets | `privacy_static_test.dart` |

### Bug found and fixed by the tests

The widget smoke test caught a crash when opening **Add Expense**: two floating action buttons (Home and Categories, both kept alive in the tab stack) shared Flutter's default Hero tag. Fixed with distinct `heroTag`s; the test now covers the full first-launch → activation → save → reports → settings path.

### Build outputs (development only — do not distribute)

| File | Size | Notes |
|---|---|---|
| `build/app/outputs/flutter-apk/app-debug.apk` | 191 MB | Debug, dev client config (`bcr-dev`), debug-signed, includes INTERNET for tooling. **Development only.** |
| `build/app/outputs/flutter-apk/app-release.apk` | 68 MB | Release code for InsideOut Casa but **signed with the debug key** (`-P allowDebugSigningForRelease=true`) solely to run the release gate. **Not for distribution** — rebuild with your release key. |

## Storage sizing (measured)

`flutter test test/perf_10k_test.dart` writes `build/perf_report.txt`. On this PC:

| Measure | Result |
|---|---|
| 10,000 expenses, encrypted (SQLCipher 4.19.0), with indexes | **2.83 MB** (2,969,600 bytes) ≈ **297 bytes per expense** |
| Monthly report (732 entries) | 3.7 ms |
| Weekly / daily report | 0.8 ms / 0.2 ms |
| Home (today total + 40 newest) | 0.3 ms |
| Bulk insert of 10,000 in one transaction | 687 ms |

So the planning allowance of 2–5 KB per expense (20–50 MB per 10,000) is about 10× more than measured. These are desktop numbers. **Phone timings still need to be measured** on the agreed test devices. App binary, OS overhead and journal space come on top; receipts are not stored.

## Not possible on this machine (blocked)

| Item | Why | What to do |
|---|---|---|
| Android emulator | CPU virtualization is disabled in firmware and no hypervisor is present | Enable VT-x in BIOS + Windows Hypervisor Platform (your decision), or use a real phone: `adb install -r build/app/outputs/flutter-apk/app-debug.apk` |
| Physical Android device run | No device connected | As above |
| iOS simulator / device build | Requires macOS + Xcode | `docs/IOS_MAC.md`. Swift code is **unbuilt and unverified**. |
| Signed release APK | No production signing key (by design) | `docs/ANDROID.md` → Release signing |

## Device checks still required (manual)

Android (test at least one Samsung and one other OEM, Android 8/9 and 14+):
1. First launch in **airplane mode**: unlock → activation (paste code) → add/edit/delete → reports.
2. App lock: fingerprint, fallback to PIN, cancel, 5+ wrong attempts (lockout message), no screen lock set (blocking screen), relock after 2 min in background; not after 1 min.
3. Kill the app and restart: records, categories, activation still present.
4. Recent-apps shows blank/black preview; screenshots blocked (FLAG_SECURE).
5. Settings → Key protection shows TEE/StrongBox (hardware-backed).
6. Backup: Google One backup + "Copy data" to a new phone (Smart Switch on Samsung) — confirm the app's data is **not** restored/transferred, or is unreadable and the app asks to start fresh.
7. Fill storage to < 5 MB free → saving shows the storage message, nothing lost.
8. Large font / small screen (e.g. 5") / keyboard open: form scrolls, Save reachable.
9. Install a newer build over the old one → data kept. Uninstall/reinstall → starts clean, asks for activation.
10. Network: run with a traffic monitor (e.g. PCAPdroid) — expect zero app traffic. Release APK has no INTERNET permission.

iPhone (after Mac build):
1. Same flows 1–3, 8–9 with Face ID / Touch ID / passcode; Face ID permission text.
2. App switcher shows the black cover.
3. Settings → Key protection shows "Secure Enclave".
4. Backup exclusion: encrypted Finder/iTunes backup and iCloud backup → restore to another iPhone → data absent; check `isExcludedFromBackup` on the data folder and files.
5. Reinstall: delete app, reinstall → starts clean (stale Keychain items removed), asks for activation.
6. Quick Start device migration: confirm data/Keychain items do not arrive (ThisDeviceOnly), or the app safely asks to start fresh.
7. Network: confirm no traffic (e.g. Charles/Proxyman with no app requests).

Record results (device model, OS version, pass/fail, notes) in this file before any production rollout.

## Device results (owner's Android phone)

| Date | Build | Check | Result |
|---|---|---|---|
| 2026-10-02 | 1.0.0+1 (release-signed) | Install by APK, unlock, activation with admin-signed code, basic use | PASS (owner) |
| 2026-10-02 | 1.0.2+3 (release-signed) | Installed as an update over the earlier build; data and activation kept | PASS (owner) |
| 2026-10-02 | 1.0.2+3 | Settings → Create backup → saved via system picker | PASS (owner) |
| — | 1.0.2+3 | Restore on a second phone | Pending |
| — | 1.0.2+3 | Monkey stress, logcat privacy scan, kill/restart, network counters (needs USB debugging) | Pending |
