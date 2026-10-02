/// AED amounts are handled as integer fils (1 AED = 100 fils) everywhere.
/// Parsing works on the text itself, never through `double`, so values such
/// as 0.1 + 0.2 or 999999.99 are exact.
library;

const int filsPerDirham = 100;
const int maxAmountFils = 99999999; // AED 999,999.99

enum AmountError { empty, invalidFormat, tooManyDecimals, zero, tooLarge }

extension AmountErrorMessage on AmountError {
  String get message => switch (this) {
    AmountError.empty => 'Enter the amount.',
    AmountError.invalidFormat => 'Use numbers only, for example 25 or 25.50.',
    AmountError.tooManyDecimals => 'Use at most 2 decimal places (fils).',
    AmountError.zero => 'Amount must be greater than zero.',
    AmountError.tooLarge => 'Amount cannot be more than AED 999,999.99.',
  };
}

class AmountParseResult {
  const AmountParseResult._(this.fils, this.error);
  const AmountParseResult.ok(int fils) : this._(fils, null);
  const AmountParseResult.fail(AmountError error) : this._(null, error);

  final int? fils;
  final AmountError? error;
  bool get isValid => fils != null;
}

const _arabicIndicZero = 0x0660; // ٠
const _easternArabicIndicZero = 0x06F0; // ۰ (Persian/Urdu keyboards)

/// Converts Arabic-Indic digits and the Arabic decimal separator to ASCII so
/// users with Arabic keyboards can type amounts.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= _arabicIndicZero && rune <= _arabicIndicZero + 9) {
      out.writeCharCode(0x30 + rune - _arabicIndicZero);
    } else if (rune >= _easternArabicIndicZero &&
        rune <= _easternArabicIndicZero + 9) {
      out.writeCharCode(0x30 + rune - _easternArabicIndicZero);
    } else if (rune == 0x066B) {
      out.write('.'); // ٫ Arabic decimal separator
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

final _amountPattern = RegExp(r'^(\d*)(?:[.,](\d*))?$');

/// Parses user text into fils. Accepts "25", "25.5", "25.50", ".5", "25."
/// and a comma as decimal separator (some numeric keypads only offer ",").
/// Rejects grouping separators, signs, exponents and more than 2 decimals.
AmountParseResult parseAmount(String input) {
  final text = normalizeDigits(input).trim();
  if (text.isEmpty) return const AmountParseResult.fail(AmountError.empty);
  final m = _amountPattern.firstMatch(text);
  if (m == null) {
    return const AmountParseResult.fail(AmountError.invalidFormat);
  }
  final whole = m.group(1)!;
  final frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) {
    return const AmountParseResult.fail(AmountError.invalidFormat);
  }
  if (frac.length > 2) {
    return const AmountParseResult.fail(AmountError.tooManyDecimals);
  }
  final wholeDigits = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  // More than 6 integer digits is always above the maximum; checking the
  // length first also keeps int parsing far away from overflow.
  if (wholeDigits.length > 6) {
    return const AmountParseResult.fail(AmountError.tooLarge);
  }
  final dirhams = wholeDigits.isEmpty ? 0 : int.parse(wholeDigits);
  final fils = dirhams * filsPerDirham + int.parse(frac.padRight(2, '0'));
  if (fils == 0) return const AmountParseResult.fail(AmountError.zero);
  if (fils > maxAmountFils) {
    return const AmountParseResult.fail(AmountError.tooLarge);
  }
  return AmountParseResult.ok(fils);
}

/// "1,234.50" — always two decimals, comma thousands separators.
String formatFilsNumber(int fils) {
  final negative = fils < 0;
  final abs = negative ? -fils : fils;
  final whole = (abs ~/ filsPerDirham).toString();
  final frac = (abs % filsPerDirham).toString().padLeft(2, '0');
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped.$frac';
}

/// "AED 1,234.50"
String formatAed(int fils) => 'AED ${formatFilsNumber(fils)}';

/// Plain editable text for a stored amount, e.g. 2550 → "25.50".
String filsToInputText(int fils) =>
    '${fils ~/ filsPerDirham}.${(fils % filsPerDirham).toString().padLeft(2, '0')}';
