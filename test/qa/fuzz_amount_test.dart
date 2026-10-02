import 'dart:math';

import 'package:daily_expense_tracker/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA fuzzing of the amount parser against an independent reference written
/// differently (character scan + BigInt), plus format/parse round-trips over
/// the whole value range.
void main() {
  /// Reference: returns fils or null. Deliberately not sharing code with
  /// parseAmount.
  int? reference(String raw) {
    final s = normalizeDigits(raw).trim();
    if (s.isEmpty) return null;
    var seps = 0;
    for (final ch in s.split('')) {
      if (ch == '.' || ch == ',') {
        seps++;
      } else if (!'0123456789'.contains(ch)) {
        return null;
      }
    }
    if (seps > 1) return null;
    final parts = s.split(RegExp('[.,]'));
    final whole = parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    if (whole.isEmpty && frac.isEmpty) return null;
    if (frac.length > 2) return null;
    final value =
        BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(100) +
        BigInt.parse(frac.padRight(2, '0'));
    if (value <= BigInt.zero || value > BigInt.from(maxAmountFils)) {
      return null;
    }
    return value.toInt();
  }

  test('random typed input: parser agrees with reference (50,000 cases)', () {
    final rnd = Random(20261002);
    const alphabet = '0123456789.,-+ e٠١٢٣٤٥٦٧٨٩٫۰۵a';
    var valid = 0;
    for (var i = 0; i < 50000; i++) {
      final len = rnd.nextInt(12);
      final s = List.generate(
        len,
        (_) => alphabet[rnd.nextInt(alphabet.length)],
      ).join();
      final got = parseAmount(s);
      final want = reference(s);
      expect(got.fils, want, reason: 'input "$s"');
      if (want == null) expect(got.error, isNotNull, reason: 'input "$s"');
      if (want != null) valid++;
    }
    expect(valid, greaterThan(500)); // the fuzz really exercises valid paths
  });

  test('random digit strings near the limits', () {
    final rnd = Random(7);
    for (var i = 0; i < 20000; i++) {
      final whole = rnd.nextInt(1200000);
      final fracDigits = rnd.nextInt(4);
      final frac = List.generate(fracDigits, (_) => rnd.nextInt(10)).join();
      final s = fracDigits == 0 ? '$whole' : '$whole.$frac';
      expect(parseAmount(s).fils, reference(s), reason: s);
    }
  });

  test('every fils value round-trips through display and edit text', () {
    final rnd = Random(99);
    final samples = <int>[
      1, 9, 10, 99, 100, 101, 999, 1000, 99999, 100000, 99999999, //
      for (var i = 0; i < 20000; i++) 1 + rnd.nextInt(maxAmountFils),
    ];
    for (final fils in samples) {
      final shown = formatAed(fils);
      expect(shown, matches(RegExp(r'^AED \d{1,3}(,\d{3})*\.\d{2}$')));
      final typed = shown.substring(4).replaceAll(',', '');
      expect(parseAmount(typed).fils, fils, reason: shown);
      expect(parseAmount(filsToInputText(fils)).fils, fils);
    }
  });

  test('no input can make the parser throw', () {
    final rnd = Random(3);
    for (var i = 0; i < 20000; i++) {
      final s = String.fromCharCodes(
        List.generate(rnd.nextInt(30), (_) => rnd.nextInt(0xFFFF)),
      );
      expect(() => parseAmount(s), returnsNormally);
    }
    expect(parseAmount('9' * 5000).error, AmountError.tooLarge);
  });
}
