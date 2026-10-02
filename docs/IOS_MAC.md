# iPhone: Mac-side steps and distribution

> **Status: UNBUILT AND UNVERIFIED.** The iOS project, the Swift bridge (`ios/Runner/AppDelegate.swift`) and the app-switcher cover (`ios/Runner/SceneDelegate.swift`) were written on Windows. iOS cannot be compiled or signed on Windows. Nothing here has run on a simulator or an iPhone yet.

## What is already configured

- Bundle id `com.bcr.dailyexpense`; iPhone only (`TARGETED_DEVICE_FAMILY = 1`); portrait; deployment target iOS 15.0 (Flutter template).
- `NSFaceIDUsageDescription` set.
- No entitlements file: no iCloud Documents, CloudKit, Keychain sharing or App Groups. **Keep it that way** — don't add capabilities in Xcode.
- DB key: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `synchronizable = false` (via flutter_secure_storage 11.2.0).
- Installation key: P-256 in the Secure Enclave (device-only Keychain fallback, used on the simulator).
- Data folder `Library/Application Support/det_data` and each file in it get `isExcludedFromBackup = true` on every launch, so the flag is re-applied after SQLite or a migration replaces a file.
- App-switcher snapshot is covered while the app is inactive. **iOS has no general API to block screenshots**, and the app doesn't claim to.

## Exact steps on a Mac

Needs a Mac with the Xcode version Flutter 3.47 supports (`flutter doctor` reports it) and Flutter 3.47.x.

```bash
git clone <repo> && cd daily-expense-tracker
flutter --version              # 3.47.x
flutter doctor -v              # Xcode + CocoaPods/SwiftPM OK
flutter pub get
flutter test                   # same suite as on Windows
flutter build ios --simulator --debug --dart-define-from-file=config/clients/dev.json
open ios/Runner.xcworkspace
```

In Xcode:
1. Runner target → Signing & Capabilities: choose your team. Confirm **no capabilities** are listed.
2. Fix any compile errors in `AppDelegate.swift` / `SceneDelegate.swift` (written blind, so expect small API nits).
3. Run on a simulator, then on a registered iPhone.

Physical-device checks: see `docs/TEST_REPORT.md` (Face ID/passcode, lockout, cancel, app-switcher cover, Secure Enclave key, backup exclusion, reinstall with surviving Keychain items).

Verify the backup exclusion on device (debug build, Xcode → Devices → download container, or with a breakpoint):

```swift
try URL(fileURLWithPath: path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
```

## Ad Hoc pilot (registered devices)

Requirements (checked on developer.apple.com, 2026-10-02):
- An **Apple Developer Program** membership (paid annually). Use an organisation membership in BCR's name if you will sell to clients.
- A **distribution certificate**, an **App ID** `com.bcr.dailyexpense`, and each pilot iPhone's **UDID registered** in Certificates, Identifiers & Profiles.
- **Limit: 100 iPhones per membership year.** Disabling a device does not free its slot. Slots can only be reset at the start of the next membership year.
- An **Ad Hoc provisioning profile** listing those devices. Every newly registered phone needs a new profile and a new build.

Build:

```bash
flutter build ipa --release --export-method ad-hoc --dart-define-from-file=config/clients/insideout-casa.json
```

Install through Apple Configurator, Xcode Devices, or an internal web page with an `itms-services` manifest (HTTPS).

**Who is responsible for what:**
- BCR (the account holder):
  - Renews the membership, certificate and profile before they expire. The expiry dates are shown in the developer account.
  - When the profile or certificate expires, or the membership lapses, installed Ad Hoc builds **stop launching** until a re-signed build is installed.
  - Keeps the device list up to date.
- Users: install updates when asked. A reinstall can lose data, so always install **over** the existing app; never delete it first.

Ad Hoc and TestFlight are **pilot routes, not permanent, maintenance-free installations**. TestFlight builds expire after a limited period and require App Store Connect upload and review. Sending someone an unsigned or self-made IPA does **not** work: iPhones only run apps signed by Apple-issued certificates and profiles.

## Ongoing private distribution (to assess separately)

For more than a pilot, the usual route for a business app sold to specific companies is **Custom Apps through Apple Business Manager**:
- Private App Store distribution to named organisations, so there's no UDID list and no 100-device cap.
- Requires App Review, and each client needs an Apple Business Manager account.
- An **Unlisted App Store** link is the other option.

Both involve uploading to Apple and answering export-compliance questions. SQLCipher uses standard AES encryption, so you must answer those questions yourself. `ITSAppUsesNonExemptEncryption` is deliberately **not** pre-filled. Apple Developer Enterprise Program in-house distribution is **not** for apps sold to other companies.

No Apple account was enrolled, nothing was uploaded and no MDM was configured.
