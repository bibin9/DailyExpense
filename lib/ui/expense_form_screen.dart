import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/capture.dart';
import '../core/local_date.dart';
import '../core/money.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import '../state/app_session.dart';
import '../state/expense_form_controller.dart';
import 'theme.dart';
import 'widgets.dart';

/// Add (existing == null) or edit an expense.
class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, required this.session, this.existing});
  final AppSession session;
  final Expense? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final ExpenseFormController c = ExpenseFormController(
    widget.session,
    existing: widget.existing,
  );
  Timer? _tick;
  late DateTime _now = widget.session.clock.now();

  @override
  void initState() {
    super.initState();
    if (!c.isEditing) {
      // Shows the phone clock live; the actual timestamp is taken at Save.
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = widget.session.clock.now());
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final outcome = await c.submit();
    if (!mounted) return;
    switch (outcome) {
      case SaveOutcome.saved:
        if (c.isEditing) {
          Navigator.of(context).pop();
          showMessage(context, 'Changes saved');
        } else {
          showMessage(context, 'Expense saved');
        }
      case SaveOutcome.failed:
        showMessage(
          context,
          c.failureMessage ?? 'Could not save.',
          error: true,
        );
      case SaveOutcome.invalid:
      case SaveOutcome.ignoredBusy:
        break;
    }
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          '${e.currentCategoryName} · ${formatAed(e.amountFils)}\n'
          '${formatDateLong(e.localDate)}, ${captureTimeLabel(ctx, e.captured)}\n\n'
          'This permanently removes it from this phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await c.delete();
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
      showMessage(context, 'Expense deleted');
    } else {
      showMessage(
        context,
        c.failureMessage ?? 'Could not delete.',
        error: true,
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!c.hasUnsavedChanges) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('What you typed has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Widget _dateTimeCard(BuildContext context) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final String title;
    final String value;
    if (c.isEditing) {
      final cap = widget.existing!.captured;
      title = 'Recorded on';
      value =
          '${formatDateLong(cap.localDate)}, '
          '${formatClock(cap.hour, cap.minute, use24h: use24)} (${cap.offsetLabel})';
    } else {
      final stamp = CaptureStamp.fromLocal(_now);
      title = 'Date and time (from your phone)';
      value =
          '${formatDateLong(stamp.localDate)}, '
          '${formatClock(stamp.hour, stamp.minute, use24h: use24)}';
    }
    return Card(
      color: AppColors.blueLight,
      child: ListTile(
        leading: const Icon(Icons.schedule, color: AppColors.blueDark),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        subtitle: Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        trailing: Tooltip(
          message: c.isEditing
              ? 'The original date and time cannot be changed.'
              : 'Taken from the phone clock when you tap Save. It cannot be edited.',
          child: const Icon(Icons.info_outline, color: AppColors.muted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.isEditing ? 'Edit expense' : 'Add expense'),
          actions: [
            if (c.isEditing)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: c.isSaving ? null : _delete,
              ),
          ],
        ),
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final cats = c.selectableCategories();
            final remarksLen = remarksLength(c.remarks.text);
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _dateTimeCard(context),
                  const SizedBox(height: 20),
                  if (cats.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'There are no categories turned on. Go to Categories '
                        'and turn one on or add one.',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  DropdownButtonFormField<int>(
                    key: ValueKey('cat-${c.categoryId}'),
                    initialValue: c.categoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Description *',
                      hintText: 'Select a category',
                      helperText: 'What was the money spent on?',
                      errorText: c.errors.category,
                      errorMaxLines: 3,
                    ),
                    items: [
                      for (final cat in cats)
                        DropdownMenuItem(
                          value: cat.id,
                          enabled: cat.isActive,
                          child: Text(
                            cat.isActive
                                ? cat.name
                                : '${cat.name} (turned off)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: c.isSaving ? null : c.selectCategory,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: c.amount,
                    enabled: !c.isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,٠-٩۰-۹٫]'),
                      ),
                      LengthLimitingTextInputFormatter(10),
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount *',
                      prefixText: 'AED  ',
                      hintText: '0.00',
                      helperText: 'Example: 25 or 25.50',
                      errorText: c.errors.amount,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: c.remarks,
                    enabled: !c.isSaving,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: _remarksRequired(cats)
                          ? 'Remarks *'
                          : 'Remarks (optional)',
                      alignLabelWithHint: true,
                      helperText: _remarksRequired(cats)
                          ? 'Required for this category'
                          : 'Any extra detail, e.g. vehicle number',
                      counterText: '$remarksLen / $maxRemarksLength',
                      errorText: c.errors.remarks,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: c.isSaving || cats.isEmpty ? null : _save,
                    icon: c.isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      c.isSaving
                          ? 'Saving…'
                          : (c.isEditing ? 'Save changes' : 'Save expense'),
                    ),
                  ),
                  if (c.failureMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      c.failureMessage!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _remarksRequired(List<Category> cats) {
    for (final cat in cats) {
      if (cat.id == c.categoryId) return cat.requiresRemark;
    }
    return false;
  }
}
