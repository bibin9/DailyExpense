import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// QA: every query on a hot path must use an index (no full table scan or
/// temp-table sort), so screens stay fast as records grow.
void main() {
  test('hot-path queries use indexes', () {
    final t = TestDb.create();
    String plan(String sql, List<Object?> args) => t.db.raw
        .select('EXPLAIN QUERY PLAN $sql', args)
        .map((r) => r['detail'] as String)
        .join(' | ');

    const from =
        'SELECT e.*, c.name FROM expenses e LEFT JOIN categories c ON c.id = e.category_id';
    final plans = {
      'home first page': plan(
        '$from ORDER BY e.captured_at_utc_ms DESC, e.id DESC LIMIT 40',
        [],
      ),
      'home older page': plan(
        '$from WHERE (e.captured_at_utc_ms, e.id) < (?, ?) '
        'ORDER BY e.captured_at_utc_ms DESC, e.id DESC LIMIT 40',
        [1, 'x'],
      ),
      'today summary': plan(
        'SELECT COUNT(*), SUM(amount_fils) FROM expenses WHERE local_date = ?',
        ['2026-10-02'],
      ),
      'report entries': plan(
        '$from WHERE e.local_date BETWEEN ? AND ? '
        'ORDER BY e.captured_at_utc_ms DESC, e.id DESC',
        ['2026-10-01', '2026-10-31'],
      ),
    };
    for (final entry in plans.entries) {
      // ignore: avoid_print
      print('${entry.key}: ${entry.value}');
      expect(
        entry.value,
        isNot(matches(RegExp(r'SCAN e(?! USING)|SCAN expenses(?! USING)'))),
        reason: '${entry.key} does a full table scan',
      );
    }
    expect(plans['home first page'], isNot(contains('TEMP B-TREE')));
    expect(plans['home older page'], isNot(contains('TEMP B-TREE')));
    t.dispose();
  });
}
