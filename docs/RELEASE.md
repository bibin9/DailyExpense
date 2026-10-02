# Release checklist

## Every release

1. `pubspec.yaml`: bump `version:`. The build number after `+` must be higher than the last installed release.
2. `dart format --output=none --set-exit-if-changed lib test tool admin_cli packages`
3. `flutter analyze`
4. `flutter test` and `cd packages/bcr_activation && dart test` and `cd admin_cli && dart test`
5. Android:
   ```bash
   flutter build apk --release --dart-define-from-file=config/clients/<client>.json
   dart run tool/release_check.dart --apk build/app/outputs/flutter-apk/app-release.apk --config config/clients/<client>.json
   ```
6. iOS (Mac): `flutter build ipa --release --export-method ad-hoc --dart-define-from-file=config/clients/<client>.json`
7. Install **over** the previous version on a test phone that has data. Confirm the records, categories and activation survive.
8. Run the device checklist in `TEST_REPORT.md` for anything touched.

Never pass `DET_DEV_BYPASS` or `DET_ALLOW_SCREENSHOTS` to a release build. Both are compiled out anyway, and the release check confirms it.

## Keep the signing identity

- **Android:**
  - The same `applicationId` (`com.bcr.dailyexpense`) and the same `.jks` key, for ever.
  - Keep the keystore and passwords outside the repo, backed up offline in two places.
  - Losing the key means users can't update without uninstalling, which loses their records.
- **iOS:**
  - The same bundle id and team.
  - Renew the certificate and profile before they expire.
  - Keychain items and app data survive updates that keep the same bundle id and team.

## Database migrations

- The current schema is v1 (`lib/data/migrations.dart`).
- To change the schema, **append** a step `2: _v2` and make it additive only: new tables, nullable or defaulted columns, new indexes. If you must reshape a table, copy the data into a new one within the same step.
- Never edit or delete a released step. Never add `DROP TABLE` or `DELETE FROM` to a migration; `test/privacy_static_test.dart` enforces this.
- Each step runs in a transaction together with the `user_version` bump.
- Before upgrading an existing database, the app keeps a still-encrypted copy, `expenses.db.pre-v<N>.bak`.
- A database from a newer app version is refused untouched.
- Add a test that opens a v(N-1) database file and checks the data after the migration.
- There is no destructive fallback in any build.

## Never commit

`android/key.properties`, `*.jks`/`*.keystore`, `*.p12`, `*.mobileprovision`, issuer `*.key.pem`, database files. `.gitignore` covers them, and a test scans for private keys.
