# Android: build, sign, install, distribute

## Toolchain used (2026-10-02)

| Tool | Version | Where (this PC) |
|---|---|---|
| Flutter / Dart | 3.47.6 stable / 3.13.5 | `C:\Bibin\_tools\flutter` |
| JDK | Microsoft OpenJDK 21.0.12 | `C:\Bibin\_tools\jdk21` |
| Android SDK | platform 36, build-tools 36.0.0, NDK 28.2.13676358 | `C:\Bibin\_tools\android-sdk` |
| Gradle / AGP / Kotlin | 9.3.1 / 9.1.0 / 2.4.0 (Flutter template defaults) | wrapper |

Nothing was installed system-wide. In each PowerShell window: `. C:\Bibin\_tools\env.ps1`.

App id `com.bcr.dailyexpense` · minSdk 24 (Android 7.0) · targetSdk 36.

## Debug build (development only)

```bash
flutter build apk --debug --dart-define-from-file=config/clients/dev.json
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Debug APKs are signed with a throwaway debug key, include `INTERNET` (Flutter tooling only) and are **not for distribution**.

Install on a phone with USB debugging enabled:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Release signing (one-time setup — keep this key forever)

Every future update **must** use the same app id and the same signing key. If the key or its password is lost, users cannot update; they would have to uninstall (losing all records) and install a newly signed app.

Create it once:

```powershell
powershell -ExecutionPolicy Bypass -File tool\android\create_release_key.ps1
```

- You type the password yourself, hidden. It is never stored in the project.
- The keystore goes to `%USERPROFILE%\.bcr-det\signing\bcr-release.keystore`: PKCS12, RSA 4096, valid about 27 years, owner `CN=BCR (BibinCutRiver), O=BCR, C=AE`.
- `android/key.properties` (git-ignored) gets only the keystore path and alias.
- The script prints the certificate SHA-256. Keep it for Android developer verification.
- It refuses to overwrite an existing keystore.

Then back up the keystore file to two safe offline places and store the password separately.

## Signed release build (each release)

```powershell
powershell -ExecutionPolicy Bypass -File tool\android\build_release.ps1 -Client insideout-casa
```

The script asks for the keystore password and builds. It then runs the release gate, which now also checks that the APK is signed with your release key and not the debug key. The result is copied to `dist\insideout-casa\DailyExpenseTracker-insideout-casa-<version>.apk` (git-ignored).

Without `key.properties` a release build **fails on purpose**. If a key exists but no password is supplied, it also fails. For a local check only, `-P allowDebugSigningForRelease=true` builds a debug-signed APK; the release gate rejects that APK.

## Private distribution of the signed APK

Send the signed release APK (for example through a company file share). On each phone:
1. Allow "Install unknown apps" for the app used to open the file (Files, Chrome, …), install, then you may turn the permission off again.
2. Open the app, set up/confirm a screen lock, unlock, then activate (`docs/ACTIVATION.md`).

Updates: build with a higher `version:` build number in `pubspec.yaml` (for example `1.0.1+2`), the same app id and the same key, and install over the old version. Data is kept.

## Android developer verification — action needed

Google's developer verification (checked 2026-10-02 at developer.android.com/developer-verification):

- **From 30 Sept 2026** it is enforced for apps installed from *participating stores* in Brazil, Indonesia, Singapore and Thailand on certified devices running Android 7+.
- **In 2027** it expands globally to all apps on certified Android devices, which will include sideloaded APKs like this one.
- Directly sideloaded APKs in the UAE are not blocked yet, but you should register before the 2027 global rollout.
- Developers distributing only outside Google Play register in the **Android Developer Console**:
  - A full distribution account has a US$25 fee.
  - Registering as an organisation needs a **D-U-N-S number**, which can take up to 28 days.
  - You then register the package name `com.bcr.dailyexpense` with your signing certificate.
- **Limited distribution accounts** (no ID, up to 20 devices) are aimed at students and hobbyists. Don't assume a commercial product qualifies.
- An `adb install` of a development build doesn't need verification. That is not a way to distribute to staff.
- After rollout, users can still install apps from unverified developers via a one-time "advanced flow", but that's not an acceptable route for a commercial product.

Enrolling, paying fees and registering are your decisions. Nothing was enrolled or uploaded.

## Manual checks still required on real phones

See `docs/TEST_REPORT.md` → "Device checks still required" (OEM backup behaviour, Keystore/StrongBox, biometric prompts, lockout, FLAG_SECURE in recents, storage-full behaviour).
