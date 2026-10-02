import 'package:characters/characters.dart';

import '../core/money.dart';
import 'models.dart';

const int maxRemarksLength = 250;
const int maxCategoryNameLength = 40;

/// Remarks length is counted in user-visible characters after trimming, so
/// an emoji or an Arabic letter with marks counts as one.
int remarksLength(String text) => text.trim().characters.length;

String? normalizeRemarks(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}

/// Category names are compared ignoring case and surrounding/multiple spaces.
String categoryNameKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String cleanCategoryName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ');

class ExpenseFormErrors {
  const ExpenseFormErrors({this.category, this.amount, this.remarks});
  final String? category;
  final String? amount;
  final String? remarks;
  bool get isEmpty => category == null && amount == null && remarks == null;
}

/// Validates raw form input. Returns either a draft or field errors.
({ExpenseDraft? draft, ExpenseFormErrors errors}) validateExpenseInput({
  required Category? category,
  required String amountText,
  required String remarksText,
  bool allowInactiveCategory = false,
}) {
  String? categoryError;
  if (category == null) {
    categoryError = 'Choose what this expense was for.';
  } else if (!category.isActive && !allowInactiveCategory) {
    categoryError =
        '"${category.name}" is no longer available. Choose another.';
  }

  final amount = parseAmount(amountText);
  final amountError = amount.error?.message;

  String? remarksError;
  final len = remarksLength(remarksText);
  if (len > maxRemarksLength) {
    remarksError =
        'Remarks can be at most $maxRemarksLength characters '
        '(currently $len).';
  } else if (category != null && category.requiresRemark && len == 0) {
    remarksError =
        'Please describe the expense when choosing "${category.name}".';
  }

  final errors = ExpenseFormErrors(
    category: categoryError,
    amount: amountError,
    remarks: remarksError,
  );
  if (!errors.isEmpty) return (draft: null, errors: errors);
  return (
    draft: ExpenseDraft(
      categoryId: category!.id,
      amountFils: amount.fils!,
      remarks: normalizeRemarks(remarksText),
    ),
    errors: errors,
  );
}
