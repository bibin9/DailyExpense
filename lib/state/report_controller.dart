import 'package:flutter/foundation.dart';

import '../core/local_date.dart';
import '../domain/models.dart';
import 'app_session.dart';

class ReportController extends ChangeNotifier {
  ReportController(this.session) {
    period = ReportPeriod.daily(LocalDate.fromDateTime(session.clock.now()));
    session.revision.addListener(load);
    load();
  }

  final AppSession session;
  late ReportPeriod period;
  ReportData? data;
  String? error;

  LocalDate get today => LocalDate.fromDateTime(session.clock.now());

  void load() {
    try {
      data = session.expenses.report(period);
      error = null;
    } on Object {
      error = 'Could not build this report. Please try again.';
    }
    notifyListeners();
  }

  void setKind(ReportKind kind) {
    // Keep the user's place: switch to the period containing its start.
    final anchor = period.kind == kind ? period.start : _anchorFor(period);
    period = ReportPeriod.of(kind, anchor);
    load();
  }

  LocalDate _anchorFor(ReportPeriod p) => p.contains(today) ? today : p.start;

  void pick(LocalDate date) {
    period = ReportPeriod.of(period.kind, date);
    load();
  }

  void shift(int steps) {
    period = period.shift(steps);
    load();
  }

  bool get isCurrent => period.contains(today);

  @override
  void dispose() {
    session.revision.removeListener(load);
    super.dispose();
  }
}
