import '../core/capture.dart';
import '../core/local_date.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.isActive,
    required this.requiresRemark,
    required this.sortOrder,
  });

  /// Stable id; expenses and reports refer to categories by this.
  final int id;
  final String name;
  final bool isActive;

  /// True for "Other": a remark is mandatory.
  final bool requiresRemark;
  final int sortOrder;
}

class Expense {
  const Expense({
    required this.id,
    required this.categoryId,
    required this.categoryLabelSnapshot,
    required this.currentCategoryName,
    required this.categoryIsActive,
    required this.amountFils,
    required this.remarks,
    required this.captured,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });

  final String id;
  final int categoryId;

  /// Category name at the time the expense was saved or last re-categorised.
  final String categoryLabelSnapshot;

  /// Current name of the category (follows renames). Falls back to the
  /// snapshot if the category row is ever missing.
  final String currentCategoryName;
  final bool categoryIsActive;
  final int amountFils;
  final String? remarks;
  final CaptureStamp captured;
  final int createdAtUtcMs;
  final int updatedAtUtcMs;

  LocalDate get localDate => captured.localDate;
}

/// Values the user edits. Capture date/time is never part of a draft.
class ExpenseDraft {
  const ExpenseDraft({
    required this.categoryId,
    required this.amountFils,
    required this.remarks,
  });

  final int categoryId;
  final int amountFils;

  /// Already trimmed; null when empty.
  final String? remarks;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.isActive,
    required this.count,
    required this.totalFils,
  });

  final int categoryId;
  final String name;
  final bool isActive;
  final int count;
  final int totalFils;
}

class ReportData {
  const ReportData({
    required this.period,
    required this.entries,
    required this.count,
    required this.totalFils,
    required this.byCategory,
  });

  final ReportPeriod period;

  /// Newest first.
  final List<Expense> entries;
  final int count;
  final int totalFils;
  final List<CategoryTotal> byCategory;

  bool get isEmpty => count == 0;
}

class DaySummary {
  const DaySummary({required this.count, required this.totalFils});
  final int count;
  final int totalFils;
}
