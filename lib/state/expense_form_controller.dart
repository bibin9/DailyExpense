import 'package:flutter/widgets.dart';

import '../core/capture.dart';
import '../core/money.dart';
import '../data/failures.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import 'app_session.dart';

enum SaveOutcome { saved, invalid, failed, ignoredBusy }

/// Minimum free space before a write is attempted. Expense rows are tiny;
/// this margin keeps the OS and SQLite journal healthy.
const int minFreeBytesForWrite = 5 * 1024 * 1024;

class ExpenseFormController extends ChangeNotifier {
  ExpenseFormController(this.session, {this.existing}) {
    final e = existing;
    if (e != null) {
      categoryId = e.categoryId;
      amount.text = filsToInputText(e.amountFils);
      remarks.text = e.remarks ?? '';
    }
    amount.addListener(_clearAmountError);
    remarks.addListener(_onRemarksChanged);
  }

  final AppSession session;

  /// Null when adding a new expense.
  final Expense? existing;

  bool get isEditing => existing != null;

  final TextEditingController amount = TextEditingController();
  final TextEditingController remarks = TextEditingController();

  /// No category is preselected for new expenses.
  int? categoryId;
  ExpenseFormErrors errors = const ExpenseFormErrors();
  String? failureMessage;
  bool _saving = false;
  bool get isSaving => _saving;

  void _clearAmountError() {
    if (errors.amount != null) {
      errors = ExpenseFormErrors(
        category: errors.category,
        remarks: errors.remarks,
      );
      notifyListeners();
    }
  }

  void _onRemarksChanged() => notifyListeners(); // live character counter

  /// Categories the user may pick. When editing an expense whose category
  /// has since been deactivated, that category is included (so the entry
  /// still shows it) but no other inactive ones.
  List<Category> selectableCategories() {
    final active = session.categories.active();
    final e = existing;
    if (e != null && !active.any((c) => c.id == e.categoryId)) {
      final current = session.categories.byId(e.categoryId);
      if (current != null) return [current, ...active];
    }
    return active;
  }

  void selectCategory(int? id) {
    categoryId = id;
    errors = ExpenseFormErrors(amount: errors.amount);
    notifyListeners();
  }

  bool get hasUnsavedChanges {
    final e = existing;
    if (e == null) {
      return categoryId != null ||
          amount.text.trim().isNotEmpty ||
          remarks.text.trim().isNotEmpty;
    }
    return categoryId != e.categoryId ||
        parseAmount(amount.text).fils != e.amountFils ||
        normalizeRemarks(remarks.text) != e.remarks;
  }

  /// Validates and saves. Repeated taps while a save is running are ignored,
  /// so one tap = at most one record. Success is reported only after the
  /// database transaction has committed.
  Future<SaveOutcome> submit() async {
    if (_saving) return SaveOutcome.ignoredBusy;
    if (session.readOnly) {
      failureMessage = AppSession.readOnlyMessage;
      notifyListeners();
      return SaveOutcome.failed;
    }
    _saving = true;
    failureMessage = null;
    notifyListeners();
    try {
      final category = categoryId == null
          ? null
          : session.categories.byId(categoryId!);
      final keepingInactive =
          isEditing && category != null && category.id == existing!.categoryId;
      final result = validateExpenseInput(
        category: category,
        amountText: amount.text,
        remarksText: remarks.text,
        allowInactiveCategory: keepingInactive,
      );
      errors = result.errors;
      if (result.draft == null) return SaveOutcome.invalid;

      final free = await session.platform.freeBytes(session.dataDirPath);
      if (free != null && free < minFreeBytesForWrite) {
        throw const AppFailure(
          FailureKind.storageFull,
          'Your phone is almost out of storage. Free up some space and try '
          'again. Nothing was saved.',
        );
      }

      final now = session.nowUtcMs();
      if (isEditing) {
        session.expenses.update(existing!.id, result.draft!, nowUtcMs: now);
      } else {
        // The date/time is captured here, at the moment Save is processed.
        final stamp = CaptureStamp.fromLocal(session.clock.now());
        session.expenses.insert(result.draft!, stamp, nowUtcMs: now);
        _clear();
      }
      session.dataChanged();
      return SaveOutcome.saved;
    } on AppFailure catch (f) {
      failureMessage = f.userMessage;
      return SaveOutcome.failed;
    } on Object {
      failureMessage = 'Something went wrong while saving. Nothing was saved. Please try again.';
      return SaveOutcome.failed;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  void _clear() {
    categoryId = null;
    amount.clear();
    remarks.clear();
    errors = const ExpenseFormErrors();
  }

  Future<bool> delete() async {
    final e = existing;
    if (e == null || _saving) return false;
    if (session.readOnly) {
      failureMessage = AppSession.readOnlyMessage;
      notifyListeners();
      return false;
    }
    _saving = true;
    notifyListeners();
    try {
      final ok = session.expenses.delete(e.id);
      session.dataChanged();
      return ok;
    } on AppFailure catch (f) {
      failureMessage = f.userMessage;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    amount.dispose();
    remarks.dispose();
    super.dispose();
  }
}
