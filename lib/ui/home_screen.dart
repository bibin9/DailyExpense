import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/local_date.dart';
import '../core/money.dart';
import '../domain/models.dart';
import '../state/app_session.dart';
import '../state/home_controller.dart';
import 'app_scope.dart';
import 'backup_ui.dart';
import 'expense_form_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the add/edit form. A confirmation returned by the form ("Changes
/// saved", "Expense deleted") is shown by the calling screen's Scaffold, so
/// a floating message is placed above that screen's Add button.
Future<void> openExpenseForm(
  BuildContext context,
  AppSession session, [
  Expense? e,
]) async {
  final message = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => ExpenseFormScreen(session: session, existing: e),
    ),
  );
  if (message != null && context.mounted) showMessage(context, message);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.clientName,
  });
  final HomeController controller;
  final String clientName;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(Product.name),
            Text(
              clientName,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
      floatingActionButton: session.readOnly
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab-add-expense',
              onPressed: () => openExpenseForm(context, session),
              icon: const Icon(Icons.add),
              label: const FabLabel('Add Expense', fontSize: 17),
            ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.error != null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: controller.error!,
            );
          }
          final items = controller.items;
          // Group the paged list by capture date.
          final rows = <Object>[];
          LocalDate? last;
          for (final e in items) {
            if (e.localDate != last) {
              rows.add(e.localDate);
              last = e.localDate;
            }
            rows.add(e);
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: rows.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodayCard(controller: controller),
                    if (session.readOnly) const _LicenceEndedCard(),
                    if (controller.showBackupReminder)
                      BackupReminderCard(
                        onBackup: () => startCreateBackup(
                          context,
                          AppScope.gateOf(context),
                        ),
                        onLater: controller.snoozeBackupReminder,
                      ),
                  ],
                );
              }
              if (i == rows.length + 1) {
                if (items.isEmpty) {
                  return Column(
                    children: [
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No expenses yet',
                        body: 'Tap Add Expense to record your first one.',
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            startRestore(context, AppScope.gateOf(context)),
                        icon: const Icon(Icons.restore),
                        label: const Text(
                          'Moving from another phone? Restore a backup',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }
                return controller.hasMore
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton(
                          onPressed: controller.loadMore,
                          child: const Text('Show older expenses'),
                        ),
                      )
                    : const BcrSignature();
              }
              final row = rows[i - 1];
              if (row is LocalDate) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                  child: Text(
                    row == controller.today ? 'Today' : formatDateLong(row),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                );
              }
              final e = row as Expense;
              return ExpenseTile(
                expense: e,
                onTap: () => openExpenseForm(context, session, e),
              );
            },
          );
        },
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.controller});
  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.todaySummary;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.blue, AppColors.blueDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today · ${formatDateLong(controller.today)}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatAed(s.totalFils),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            s.count == 1 ? '1 entry' : '${s.count} entries',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _LicenceEndedCard extends StatelessWidget {
  const _LicenceEndedCard();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Card(
      color: Color(0xFFFFF4E5),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Color(0xFF8A4B00)),
            SizedBox(width: 10),
            Expanded(child: Text(AppSession.readOnlyMessage)),
          ],
        ),
      ),
    ),
  );
}
