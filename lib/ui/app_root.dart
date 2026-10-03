import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/app_gate_controller.dart';
import 'app_scope.dart';
import 'app_shell.dart';
import 'gate_screens.dart';
import 'theme.dart';
import 'widgets.dart';

class DailyExpenseApp extends StatefulWidget {
  const DailyExpenseApp({super.key, required this.gate});
  final AppGateController gate;

  @override
  State<DailyExpenseApp> createState() => _DailyExpenseAppState();
}

class _DailyExpenseAppState extends State<DailyExpenseApp> {
  AppGateController get gate => widget.gate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(gate);
    gate.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(gate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    gate: gate,
    child: MaterialApp(
      title: Product.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: gate,
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(child: _screenFor(gate)),
            // App-switcher privacy cover while not in the foreground.
            if (gate.obscured && gate.session != null)
              const Positioned.fill(child: _PrivacyCover()),
          ],
        ),
      ),
    ),
  );

  Widget _screenFor(AppGateController g) => switch (g.phase) {
    GatePhase.starting => const StartingScreen(),
    GatePhase.noDeviceSecurity => NoDeviceSecurityScreen(gate: g),
    GatePhase.locked => LockScreen(gate: g),
    GatePhase.startupError => StartupErrorScreen(gate: g),
    GatePhase.needsActivation => ActivationScreen(gate: g),
    // Keyed by session so a restore rebuilds every screen on the new data.
    GatePhase.ready => AppShell(key: ObjectKey(g.session), gate: g),
  };
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.ink,
    child: Center(child: AppLogo(size: 96)),
  );
}
