import 'package:flutter/widgets.dart';

import '../state/app_gate_controller.dart';
import '../state/app_session.dart';

/// State management: plain Flutter `ChangeNotifier` controllers, handed down
/// through this one InheritedWidget and rebuilt with `ListenableBuilder`.
/// No third-party state package.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.gate, required super.child});

  final AppGateController gate;

  static AppGateController gateOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.gate;

  static AppSession sessionOf(BuildContext context) => gateOf(context).session!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => gate != oldWidget.gate;
}
