import 'package:flutter/foundation.dart';

import '../core/capture.dart';
import '../data/category_repository.dart';
import '../data/database.dart';
import '../data/expense_repository.dart';
import '../data/meta_repository.dart';
import '../platform/platform_services.dart';
import '../security/activation_service.dart';

/// Everything that exists once the encrypted database is open.
class AppSession {
  AppSession({
    required this.db,
    required this.platform,
    required this.clock,
    required this.dataDirPath,
  }) : expenses = ExpenseRepository(db),
       categories = CategoryRepository(db),
       meta = MetaRepository(db);

  final AppDatabase db;
  final PlatformServices platform;
  final Clock clock;
  final String dataDirPath;
  final ExpenseRepository expenses;
  final CategoryRepository categories;
  final MetaRepository meta;

  /// Bumped after every committed change so lists and reports refresh.
  final ValueNotifier<int> revision = ValueNotifier(0);

  void dataChanged() => revision.value++;

  int nowUtcMs() => clock.now().toUtc().millisecondsSinceEpoch;

  late final TokenStore tokenStore = _MetaTokenStore(meta);

  void close() {
    revision.dispose();
    db.close();
  }
}

class _MetaTokenStore implements TokenStore {
  _MetaTokenStore(this._meta);
  final MetaRepository _meta;
  static const _key = 'activation_token';

  @override
  String? readToken() => _meta.read(_key);

  @override
  void writeToken(String token) => _meta.write(_key, token);

  @override
  void deleteToken() => _meta.delete(_key);
}
