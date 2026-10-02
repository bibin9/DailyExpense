import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../core/capture.dart';
import '../data/database.dart';
import '../data/failures.dart';
import '../platform/db_key_store.dart';
import '../platform/platform_services.dart';
import '../platform/storage_layout.dart';
import '../security/activation_service.dart';
import '../security/device_auth.dart';
import 'app_session.dart';

enum GatePhase {
  starting,
  noDeviceSecurity,
  locked,
  startupError,
  needsActivation,
  ready,
}

/// Start-up and lock state machine:
/// install check → device security → unlock → open encrypted database →
/// activation → ready. Relocks after [relockAfter] in the background.
class AppGateController extends ChangeNotifier with WidgetsBindingObserver {
  AppGateController({
    required this.config,
    required this.platform,
    required this.keyStore,
    required this.auth,
    required this.clock,
    Future<StorageLayout> Function()? resolveLayout,
    this.relockAfter = const Duration(minutes: 2),
  }) : _resolveLayout = resolveLayout ?? StorageLayout.resolve;

  final AppConfig config;
  final PlatformServices platform;
  final DbKeyStore keyStore;
  final DeviceAuthenticator auth;
  final Clock clock;
  final Duration relockAfter;
  final Future<StorageLayout> Function() _resolveLayout;

  GatePhase phase = GatePhase.starting;
  String? message;
  AppFailure? failure;
  AppSession? session;
  ActivationState? activation;
  ActivationService? activationService;
  StorageLayout? layout;

  /// True while the app is not in the foreground: the UI shows a cover so
  /// the app-switcher snapshot does not reveal expenses.
  bool obscured = false;

  bool _authInProgress = false;
  DateTime? _backgroundedAt;

  void _set(GatePhase p, {String? msg}) {
    phase = p;
    message = msg;
    notifyListeners();
  }

  Future<void> start() async {
    _set(GatePhase.starting);
    failure = null;
    try {
      layout ??= await _resolveLayout();
      await _installCheck(layout!);
      if (!await auth.hasDeviceSecurity()) {
        _set(GatePhase.noDeviceSecurity);
        return;
      }
      _set(GatePhase.locked);
      await unlock();
    } on AppFailure catch (f) {
      _fail(f);
    } on Object {
      _fail(
        const AppFailure(
          FailureKind.unknown,
          'The app could not start. Please close it and open it again.',
        ),
      );
    }
  }

  void _fail(AppFailure f) {
    failure = f;
    _set(GatePhase.startupError, msg: f.userMessage);
  }

  /// Distinguishes a fresh install from a normal start/upgrade.
  ///
  /// App-private files are removed on uninstall on both platforms, but iOS
  /// Keychain items can survive. No marker + no database = fresh install,
  /// so stale Keychain items from an earlier installation are removed.
  /// If the database exists (an upgrade), nothing is deleted.
  Future<void> _installCheck(StorageLayout l) async {
    if (l.installMarker.existsSync()) return;
    final dbExists = File(l.databasePath).existsSync();
    if (!dbExists) {
      await keyStore.delete();
      await platform.deleteInstallationKey();
    }
    l.dataDir.createSync(recursive: true);
    l.installMarker.writeAsStringSync(
      clock.now().toUtc().toIso8601String(),
      flush: true,
    );
    await _excludeFromBackup(l);
  }

  Future<void> _excludeFromBackup(StorageLayout l) async {
    for (final p in l.allPaths()) {
      await platform.excludeFromBackup(p);
    }
  }

  Future<void> unlock() async {
    if (_authInProgress) return;
    if (phase != GatePhase.locked) return;
    _authInProgress = true;
    message = null;
    notifyListeners();
    try {
      final outcome = await auth.authenticate(
        'Unlock ${Product.name} to see your expenses',
      );
      if (outcome == AuthOutcome.noDeviceSecurity) {
        _set(GatePhase.noDeviceSecurity);
        return;
      }
      if (outcome != AuthOutcome.success) {
        _set(GatePhase.locked, msg: describeAuthOutcome(outcome));
        return;
      }
      if (session == null) {
        await _openSession();
      } else {
        _set(_afterUnlockPhase());
      }
    } on AppFailure catch (f) {
      _fail(f);
    } finally {
      _authInProgress = false;
    }
  }

  GatePhase _afterUnlockPhase() => switch (activation?.phase) {
    ActivationPhase.activated || ActivationPhase.devBypass => GatePhase.ready,
    _ => GatePhase.needsActivation,
  };

  Future<void> _openSession() async {
    final l = layout!;
    l.dataDir.createSync(recursive: true);
    final path = l.databasePath;
    final dbExists = File(path).existsSync();

    Uint8List? key;
    try {
      key = await keyStore.read();
    } on PlatformException {
      throw const AppFailure(
        FailureKind.keyUnavailable,
        'The security key that protects your expenses could not be read on '
        'this phone.',
      );
    }
    if (key == null) {
      if (dbExists) {
        throw const AppFailure(
          FailureKind.keyUnavailable,
          'The security key that protects your expenses is missing on this '
          'phone, so the saved records cannot be opened.',
        );
      }
      final fresh = generateDbKey();
      await keyStore.write(fresh);
      final readBack = await keyStore.read();
      if (readBack == null || !listEquals(readBack, fresh)) {
        throw const AppFailure(
          FailureKind.keyUnavailable,
          'This phone could not store the security key. The app cannot '
          'store expenses safely.',
        );
      }
      key = fresh;
    }

    final db = AppDatabase.open(
      path: path,
      key: key,
      nowUtcMs: clock.now().toUtc().millisecondsSinceEpoch,
    );
    // Re-apply on every start: covers files created or replaced by SQLite
    // (journal) and by migrations (pre-migration copy).
    await _excludeFromBackup(l);

    final s = AppSession(
      db: db,
      platform: platform,
      clock: clock,
      dataDirPath: l.dataDir.path,
    );
    session = s;
    activationService = ActivationService(
      config: config,
      platform: platform,
      tokens: s.tokenStore,
      now: clock.now,
    );
    await refreshActivation();
  }

  Future<void> refreshActivation() async {
    activation = await activationService!.check();
    _set(_afterUnlockPhase());
  }

  Future<({bool ok, String message})> submitActivation(String token) async {
    final r = await activationService!.submit(token);
    if (r.ok) await refreshActivation();
    return r;
  }

  void lockNow() {
    if (session == null) return;
    _set(GatePhase.locked);
  }

  /// Only offered when existing data is already unreadable (missing key or
  /// wrong key). The unreadable file is kept, renamed, never deleted.
  Future<void> setAsideUnreadableDataAndRestart() async {
    final l = layout!;
    final db = File(l.databasePath);
    if (db.existsSync()) {
      final stamp = clock.now().toUtc().millisecondsSinceEpoch;
      db.renameSync('${l.databasePath}.unreadable-$stamp');
    }
    await keyStore.delete();
    await start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        obscured = true;
        notifyListeners();
      case AppLifecycleState.paused:
        obscured = true;
        _backgroundedAt ??= clock.now();
        notifyListeners();
      case AppLifecycleState.resumed:
        obscured = false;
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            session != null &&
            !_authInProgress &&
            (phase == GatePhase.ready || phase == GatePhase.needsActivation) &&
            clock.now().difference(since) >= relockAfter) {
          _set(GatePhase.locked);
          unlock();
        } else {
          notifyListeners();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    session?.close();
    super.dispose();
  }
}
