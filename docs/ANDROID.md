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

Every future update **must** use the same app id and the same signing key. If the key is lost, users cannot update; they must uninstall (losing all records) and install a newly signed app.

1. Create the upload/signing key **outside the repository** (choose your own strong passwords):

   ```bash
   keytool -genkeypair -v -keystore C:\Users\<you>\.bcr-det\signing\bcr-release.jks -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 -alias bcr-release
   ```

2. Create `android/key.properties` (git-ignored):

   ```properties
   storeFile=C:\\Users\\<you>\\.bcr-det\\signing\\bcr-release.jks
   storePassword=<store password>
   keyAlias=bcr-release
   keyPassword=<key password>
   ```

3. Back up the `.jks` file and both passwords offline (two separate safe places). Record the certificate SHA-256 (`keytool -list -v -keystore …`) — you need it for developer verification.

Without `key.properties` a release build **fails on purpose**. For a local release check only, you can pass `-PallowDebugSigningForRelease=true` (debug-signed; never distribute that APK).

## Release build + gate

```bash
flutter build apk --release --dart-define-from-file=config/clients/insideout-casa.json
dart run tool/release_check.dart --apk build/app/outputs/flutter-apk/app-release.apk --config config/clients/insideout-casa.json
```

The release check fails if the APK requests `INTERNET`/`ACCESS_NETWORK_STATE`, is debuggable, allows backup, lacks backup/data-extraction rules, still contains development-bypass code, or if the config is incomplete or is the dev client.

To inspect the merged manifest yourself:

```bash
%ANDROID_HOME%\build-tools\36.0.0\aapt2 dump permissions build\app\outputs\flutter-apk\app-release.apk
```

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
