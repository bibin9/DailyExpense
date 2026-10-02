import 'package:daily_expense_tracker/core/money.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:daily_expense_tracker/domain/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAmount (integer fils, no floating point)', () {
    final ok = <String, int>{
      '25': 2500,
      '25.5': 2550,
      '25.50': 2550,
      '0.01': 1,
      '.5': 50,
      '7.': 700,
      '0.10': 10,
      '0.30': 30, // 0.1 + 0.2 style values stay exact
      '999999.99': 99999999,
      '000123.40': 12340,
      ' 12.34 ': 1234,
      '12,34': 1234, // comma decimal keypads
      '١٢٫٥٠': 1250, // Arabic-Indic digits + Arabic decimal separator
      '۲۵': 2500, // Eastern Arabic-Indic
      '100': 10000,
    };
    ok.forEach((input, fils) {
      test('"$input" → $fils fils', () {
        final r = parseAmount(input);
        expect(r.error, isNull);
        expect(r.fils, fils);
      });
    });

    final bad = <String, AmountError>{
      '': AmountError.empty,
      '   ': AmountError.empty,
      '0': AmountError.zero,
      '0.00': AmountError.zero,
      '.': AmountError.invalidFormat,
      '-5': AmountError.invalidFormat,
      '+5': AmountError.invalidFormat,
      '1,000.00': AmountError.invalidFormat,
      '1e3': AmountError.invalidFormat,
      'abc': AmountError.invalidFormat,
      '1.2.3': AmountError.invalidFormat,
      '12.345': AmountError.tooManyDecimals,
      '0.001': AmountError.tooManyDecimals,
      '1000000': AmountError.tooLarge,
      '999999.999': AmountError.tooManyDecimals,
      '1000000.00': AmountError.tooLarge,
      '99999999999999999999999': AmountError.tooLarge,
    };
    bad.forEach((input, err) {
      test('"$input" → $err', () => expect(parseAmount(input).error, err));
    });
  });

  group('formatting', () {
    test('always AED with two decimals', () {
      expect(formatAed(13300), 'AED 133.00');
      expect(formatAed(1), 'AED 0.01');
      expect(formatAed(0), 'AED 0.00');
      expect(formatAed(99999999), 'AED 999,999.99');
      expect(formatAed(123456789012), 'AED 1,234,567,890.12');
      expect(filsToInputText(2550), '25.50');
    });

    test('sum of 10,000 max-value entries stays exact in 64-bit ints', () {
      var total = 0;
      for (var i = 0; i < 10000; i++) {
        total += maxAmountFils;
      }
      expect(formatAed(total), 'AED 9,999,999,900.00');
    });
  });

  group('expense validation', () {
    const food = Category(
      id: 2,
      name: 'Food',
      isActive: true,
      requiresRemark: false,
      sortOrder: 20,
    );
    const other = Category(
      id: 8,
      name: 'Other',
      isActive: true,
      requiresRemark: true,
      sortOrder: 80,
    );
    const off = Category(
      id: 5,
      name: 'Carwash',
      isActive: false,
      requiresRemark: false,
      sortOrder: 50,
    );

    test('category is mandatory (nothing preselected)', () {
      final r = validateExpenseInput(
        category: null,
        amountText: '5',
        remarksText: '',
      );
      expect(r.draft, isNull);
      expect(r.errors.category, isNotNull);
    });

    test('valid input produces a trimmed draft', () {
      final r = validateExpenseInput(
        category: food,
        amountText: '12.5',
        remarksText: '  lunch  ',
      );
      expect(r.draft!.amountFils, 1250);
      expect(r.draft!.remarks, 'lunch');
      expect(r.draft!.categoryId, 2);
    });

    test('empty remarks become null', () {
      final r = validateExpenseInput(
        category: food,
        amountText: '1',
        remarksText: '   ',
      );
      expect(r.draft!.remarks, isNull);
    });

    test('Other requires a remark', () {
      expect(
        validateExpenseInput(
          category: other,
          amountText: '1',
          remarksText: '  ',
        ).errors.remarks,
        isNotNull,
      );
      expect(
        validateExpenseInput(
          category: other,
          amountText: '1',
          remarksText: 'stamps',
        ).draft,
        isNotNull,
      );
    });

    test('remarks max 250 characters after trimming, counted as visible characters', () {
      final exact = 'a' * 250;
      expect(
        validateExpenseInput(
          category: food,
          amountText: '1',
          remarksText: '  $exact  ',
        ).draft,
        isNotNull,
      );
      expect(
        validateExpenseInput(
          category: food,
          amountText: '1',
          remarksText: '${exact}b',
        ).errors.remarks,
        isNotNull,
      );
      final emoji = '👍' * 250; // 500 UTF-16 units, 250 characters
      expect(
        validateExpenseInput(
          category: food,
          amountText: '1',
          remarksText: emoji,
        ).draft,
        isNotNull,
      );
    });

    test(
      'inactive category rejected for new expenses, allowed when kept on edit',
      () {
        expect(
          validateExpenseInput(
            category: off,
            amountText: '1',
            remarksText: '',
          ).errors.category,
          isNotNull,
        );
        expect(
          validateExpenseInput(
            category: off,
            amountText: '1',
            remarksText: '',
            allowInactiveCategory: true,
          ).draft,
          isNotNull,
        );
      },
    );

    test('category name normalisation ignores case and spaces', () {
      expect(categoryNameKey('  Car   Parking FEE '), 'car parking fee');
      expect(cleanCategoryName('  Car   Parking FEE '), 'Car Parking FEE');
    });
  });
}
