import 'package:flutter/foundation.dart';

import '../core/local_date.dart';
import '../data/backup_service.dart';
import '../data/expense_repository.dart';
import '../domain/models.dart';
import 'app_session.dart';

/// Today's total plus a newest-first list loaded a page at a time, so the
/// home screen never loads the whole database.
class HomeController extends ChangeNotifier {
  HomeController(this.session) {
    session.revision.addListener(refresh);
    refresh();
  }

  final AppSession session;
  static const pageSize = 40;

  late LocalDate today;
  DaySummary todaySummary = const DaySummary(count: 0, totalFils: 0);
  final List<Expense> items = [];
  bool hasMore = false;
  String? error;
  bool showBackupReminder = false;

  void refresh() {
    try {
      today = LocalDate.fromDateTime(session.clock.now());
      todaySummary = session.expenses.summaryFor(today);
      final first = session.expenses.recent(limit: pageSize);
      items
        ..clear()
        ..addAll(first);
      hasMore = first.length == pageSize;
      showBackupReminder = shouldRemindBackup(
        expenseCount: first.length,
        lastBackupUtcMs: int.tryParse(
          session.meta.read(metaLastBackupAt) ?? '',
        ),
        firstExpenseCreatedUtcMs: session.expenses.firstCreatedAtUtcMs(),
        snoozedUntilUtcMs: int.tryParse(
          session.meta.read(metaBackupReminderSnoozedUntil) ?? '',
        ),
        nowUtcMs: session.nowUtcMs(),
      );
      error = null;
    } on Object {
      error = 'Could not load your expenses. Please restart the app.';
    }
    notifyListeners();
  }

  void loadMore() {
    if (!hasMore || items.isEmpty) return;
    final last = items.last;
    final next = session.expenses.recent(
      limit: pageSize,
      after: ExpenseCursor(last.captured.instantUtcMs, last.id),
    );
    items.addAll(next);
    hasMore = next.length == pageSize;
    notifyListeners();
  }

  /// "Later" on the reminder: hide it for a week.
  void snoozeBackupReminder() {
    session.meta.write(
      metaBackupReminderSnoozedUntil,
      '${session.nowUtcMs() + const Duration(days: 7).inMilliseconds}',
    );
    showBackupReminder = false;
    notifyListeners();
  }

  @override
  void dispose() {
    session.revision.removeListener(refresh);
    super.dispose();
  }
}
