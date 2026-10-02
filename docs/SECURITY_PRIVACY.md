# Security and privacy

## Data at rest

| What | How | Where |
|---|---|---|
| Expenses, categories, activation token | SQLCipher 4.19 (AES-256 + HMAC), raw 256-bit random key; refuses to run if not SQLCipher | Android `/data/data/com.bcr.dailyexpense/files/det_data/` · iOS `Library/Application Support/det_data/` (app-private, durable, not cache) |
| DB key | flutter_secure_storage 11.2.0: Android AES-GCM value, AES key wrapped by Android Keystore RSA key · iOS Keychain, AfterFirstUnlock**ThisDeviceOnly**, non-synchronizable | Android app-private SharedPreferences · iOS Keychain |
| Installation activation key | Non-exportable P-256: Android Keystore (StrongBox if available, else TEE) · iOS Secure Enclave (fallback: device-only Keychain) | Hardware/OS keystore |

- SQLite runs with `secure_delete=ON`, `temp_store=MEMORY` (no temp files) and a rollback journal with `synchronous=FULL`. A full disk or a power cut during a write rolls back instead of corrupting the file.
- The key is never auto-reset. If it is missing or unreadable, the app stops with an explanation; it does not silently create an empty database. The only way forward is a deliberate "Start fresh", which keeps the unreadable file aside rather than deleting it.

## Backups and device transfer

- **Android:**
  - `allowBackup="false"`.
  - `fullBackupContent` rules for Android 6–11 and `dataExtractionRules` for 12+ exclude every domain from cloud backup **and** device-to-device transfer.
  - Even if an OEM tool copied the files anyway, the Keystore key never leaves the phone, so the copy would be unreadable.
- **iOS:**
  - The data folder and every file in it are marked `isExcludedFromBackup` on every launch.
  - Keychain items are ThisDeviceOnly, so they aren't restored to a different iPhone.
  - There are no iCloud or CloudKit capabilities.
- **Honest limit:** these settings follow the platforms' documented behaviour, but the app can't guarantee what every OEM tool, forensic tool or future OS version does. This must be checked on real devices (TEST_REPORT).

## Network

- No app code makes network calls (enforced by `test/privacy_static_test.dart`).
- No analytics, ads, crash reporting or cloud SDKs.
- **Android release:** `INTERNET` and `ACCESS_NETWORK_STATE` are removed from the merged manifest (`tools:node="remove"`), and `tool/release_check.dart` confirms this in the APK. Debug and profile builds keep `INTERNET` for Flutter tooling only.
- **iOS** has no per-app internet permission switch. The guarantee there rests on the code having no networking and the dependencies being reviewed:
  - `sqlite3` makes no runtime network calls.
  - `flutter_secure_storage`, `local_auth` and `path_provider` use local OS APIs only.
  - Runtime traffic should still be confirmed on a device (TEST_REPORT).
- **Build time** needs internet: Gradle, pub, and the `sqlite3` hook, which downloads a pinned, sha256-checked SQLCipher binary from GitHub releases. Installed expense functions work in airplane mode.

## Logs and keyboard

- No `print`/`log` in app code (static test).
- In release, framework error printing and `debugPrint` are disabled.
- SQLCipher's own logging is set to `NONE`.
- Native errors return only the exception class name.
- Amount, remarks and activation fields disable IME personalised learning (`enableIMEPersonalizedLearning: false`). The amount field also turns off autocorrect and suggestions. iOS has no equivalent per-field switch beyond autocorrect.

## Screen privacy

- **Android:** `FLAG_SECURE` is set in `onCreate` before the first frame. It blocks screenshots and screen recording and blanks the recent-apps preview.
- **iOS:** a cover view is shown on `sceneWillResignActive`, so the app-switcher snapshot shows the cover. iOS offers no universal screenshot-blocking API.
- **Both:** Flutter also draws a blue cover while the app is inactive.

## Authentication

- `local_auth` with `biometricOnly: false`: fingerprint or face, falling back to the phone PIN, pattern, password or passcode. There is no app PIN, and no shared or hard-coded PIN exists.
- **Missing screen lock:** the app refuses to open and explains how to set one up.
- **Cancel, lockout or unavailable:** the app stays locked, shows a clear message and offers an Unlock button.
- **Relock:** after 2 minutes in the background.

## Not protected against

- Rooted or jailbroken phones, malware with OS privileges, a modified and re-signed app, or someone watching over the user's shoulder.
- Loss of the phone, uninstalling the app or clearing its data: the records are gone and cannot be recovered.
