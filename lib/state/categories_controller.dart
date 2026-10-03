import 'package:flutter/foundation.dart' hide Category;

import '../data/failures.dart';
import '../domain/models.dart';
import 'app_session.dart';

class CategoriesController extends ChangeNotifier {
  CategoriesController(this.session) {
    load();
  }

  final AppSession session;
  List<Category> all = const [];

  void load() {
    all = session.categories.all();
    notifyListeners();
  }

  /// Returns null on success or a user-facing error message.
  String? _run(void Function() action) {
    if (session.readOnly) return AppSession.readOnlyMessage;
    try {
      action();
      session.dataChanged();
      load();
      return null;
    } on AppFailure catch (f) {
      return f.userMessage;
    }
  }

  String? add(String name) =>
      _run(() => session.categories.add(name, nowUtcMs: session.nowUtcMs()));

  String? rename(int id, String name) => _run(
    () => session.categories.rename(id, name, nowUtcMs: session.nowUtcMs()),
  );

  String? setActive(int id, bool active) => _run(
    () =>
        session.categories.setActive(id, active, nowUtcMs: session.nowUtcMs()),
  );

  int usage(int id) => session.categories.usageCount(id);
}
