import 'package:flutter/material.dart';

import '../core/local_date.dart';
import '../core/money.dart';
import '../state/report_controller.dart';
import 'home_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.controller});
  final ReportController controller;

  Future<void> _pick(BuildContext context) async {
    final p = controller.period;
    if (p.kind == ReportKind.monthly) {
      final picked = await showDialog<LocalDate>(
        context: context,
        builder: (_) => _MonthPicker(
          initial: p.start,
          latestYear: controller.today.year + 1,
        ),
      );
      if (picked != null) controller.pick(picked);
      return;
    }
    final d = await showDatePicker(
      context: context,
      initialDate: p.start.toDateTime(),
      firstDate: DateTime(2000),
      lastDate: DateTime(controller.today.year + 1, 12, 31),
      helpText: p.kind == ReportKind.weekly
          ? 'Pick any day in the week'
          : 'Pick a date',
    );
    if (d != null) controller.pick(LocalDate.fromDateTime(d));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final p = controller.period;
          final data = controller.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              SegmentedButton<ReportKind>(
                segments: const [
                  ButtonSegment(value: ReportKind.daily, label: Text('Daily')),
                  ButtonSegment(
                    value: ReportKind.weekly,
                    label: Text('Weekly'),
                  ),
                  ButtonSegment(
                    value: ReportKind.monthly,
                    label: Text('Monthly'),
                  ),
                ],
                selected: {p.kind},
                showSelectedIcon: false,
                onSelectionChanged: (s) => controller.setKind(s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => controller.shift(-1),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _pick(context),
                      child: Text(
                        formatPeriodLabel(p),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => controller.shift(1),
                  ),
                ],
              ),
              if (!controller.isCurrent)
                Center(
                  child: TextButton(
                    onPressed: () => controller.pick(controller.today),
                    child: const Text('Back to today'),
                  ),
                ),
              const SizedBox(height: 8),
              if (controller.error != null)
                EmptyState(icon: Icons.error_outline, title: controller.error!)
              else if (data != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(color: AppColors.muted),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  formatAed(data.totalFils),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.blueDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Entries',
                              style: TextStyle(color: AppColors.muted),
                            ),
                            Text(
                              '${data.count}',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (data.isEmpty)
                  const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No expenses in this period',
                    body: 'Try another date, or add an expense from Home.',
                  )
                else ...[
                  const _Heading('By category'),
                  Card(
                    child: Column(
                      children: [
                        for (final c in data.byCategory)
                          ListTile(
                            title: Text(
                              c.isActive ? c.name : '${c.name} (turned off)',
                            ),
                            subtitle: Text(
                              c.count == 1 ? '1 entry' : '${c.count} entries',
                            ),
                            trailing: Text(
                              formatAed(c.totalFils),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const _Heading('Entries (newest first)'),
                  Card(
                    child: Column(
                      children: [
                        for (final e in data.entries)
                          ExpenseTile(
                            expense: e,
                            showDate: p.kind != ReportKind.daily,
                            onTap: () =>
                                openExpenseForm(context, controller.session, e),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.muted,
      ),
    ),
  );
}

class _MonthPicker extends StatefulWidget {
  const _MonthPicker({required this.initial, required this.latestYear});
  final LocalDate initial;
  final int latestYear;
  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int year = widget.initial.year;
  late int month = widget.initial.month;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose month'),
    content: Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButton<int>(
            isExpanded: true,
            value: month,
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(monthNames[m - 1])),
            ],
            onChanged: (v) => setState(() => month = v!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButton<int>(
            isExpanded: true,
            value: year,
            items: [
              for (var y = widget.latestYear; y >= 2000; y--)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => year = v!),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, LocalDate(year, month, 1)),
        child: const Text('Show'),
      ),
    ],
  );
}
