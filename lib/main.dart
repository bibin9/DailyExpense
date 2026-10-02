import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config/app_config.dart';
import 'core/capture.dart';
import 'platform/db_key_store.dart';
import 'platform/platform_services.dart';
import 'security/device_auth.dart';
import 'state/app_gate_controller.dart';
import 'ui/app_root.dart';

/// Daily Expense Tracker — a BCR (BibinCutRiver) product.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never print framework errors (which can include widget state) to the
  // system log in release builds.
  if (kReleaseMode) {
    FlutterError.onError = (_) {};
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'SQLCipher',
    ], await rootBundle.loadString('assets/licenses/sqlcipher.txt'));
    yield LicenseEntryWithLineBreaks([
      'OpenSSL (used by SQLCipher on Android)',
    ], await rootBundle.loadString('assets/licenses/openssl_apache2.txt'));
  });

  final platform = MethodChannelPlatformServices();
  // Android FLAG_SECURE is already set natively before Flutter starts; this
  // only allows turning it off for debug screenshots when explicitly asked.
  const allowScreenshots =
      kDebugMode && bool.fromEnvironment('DET_ALLOW_SCREENSHOTS');
  try {
    await platform.setSecureScreen(!allowScreenshots);
  } on Object {
    // Not fatal: native side defaults to secure.
  }

  final gate = AppGateController(
    config: AppConfig.fromEnvironment,
    platform: platform,
    keyStore: SecureDbKeyStore(),
    auth: LocalAuthAuthenticator(),
    clock: const DeviceClock(),
  );
  runApp(DailyExpenseApp(gate: gate));
}
