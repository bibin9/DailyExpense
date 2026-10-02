import 'package:bcr_activation/bcr_activation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/failures.dart';
import '../security/activation_service.dart';
import '../state/app_gate_controller.dart';
import 'theme.dart';
import 'widgets.dart';

const _onBlue = TextStyle(color: Colors.white, fontSize: 16, height: 1.4);

ButtonStyle _whiteButton() => FilledButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: AppColors.blueDark,
);

class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});
  @override
  Widget build(BuildContext context) => const BrandedPanel(
    children: [Center(child: CircularProgressIndicator(color: Colors.white))],
  );
}

class LockScreen extends StatelessWidget {
  const LockScreen({super.key, required this.gate});
  final AppGateController gate;

  @override
  Widget build(BuildContext context) => BrandedPanel(
    children: [
      const Icon(Icons.lock_outline, color: Colors.white, size: 40),
      const SizedBox(height: 12),
      const Text(
        'Locked. Use your fingerprint, face or phone PIN to continue.',
        textAlign: TextAlign.center,
        style: _onBlue,
      ),
      if (gate.message != null) ...[
        const SizedBox(height: 16),
        Text(
          gate.message!,
          textAlign: TextAlign.center,
          style: _onBlue.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        style: _whiteButton(),
        onPressed: gate.unlock,
        icon: const Icon(Icons.fingerprint),
        label: const Text('Unlock'),
      ),
    ],
  );
}

class NoDeviceSecurityScreen extends StatelessWidget {
  const NoDeviceSecurityScreen({super.key, required this.gate});
  final AppGateController gate;

  @override
  Widget build(BuildContext context) => BrandedPanel(
    children: [
      const Icon(Icons.phonelink_lock, color: Colors.white, size: 40),
      const SizedBox(height: 12),
      const Text(
        'Set up a screen lock first',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Your expenses are protected by your phone\'s own lock. Please add a '
        'PIN, pattern, password or passcode in your phone Settings '
        '(Security / Face ID & Passcode), then come back and tap Check again.',
        textAlign: TextAlign.center,
        style: _onBlue,
      ),
      const SizedBox(height: 24),
      FilledButton(
        style: _whiteButton(),
        onPressed: gate.start,
        child: const Text('Check again'),
      ),
    ],
  );
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.gate});
  final AppGateController gate;

  bool get _dataUnreadable =>
      gate.failure?.kind == FailureKind.keyUnavailable ||
      gate.failure?.kind == FailureKind.wrongKeyOrCorrupt;

  Future<void> _confirmStartFresh(BuildContext context) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Start with an empty record book?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your old records cannot be opened on this phone. The '
                'unreadable file will be kept aside (not deleted), but the app '
                'will start empty.\n\nType START FRESH to confirm.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typed,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: typed.text.trim() == 'START FRESH'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Start fresh'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok == true) await gate.setAsideUnreadableDataAndRestart();
  }

  @override
  Widget build(BuildContext context) => BrandedPanel(
    children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 40),
      const SizedBox(height: 12),
      Text(
        gate.message ?? 'The app could not start.',
        textAlign: TextAlign.center,
        style: _onBlue,
      ),
      const SizedBox(height: 24),
      FilledButton(
        style: _whiteButton(),
        onPressed: gate.start,
        child: const Text('Try again'),
      ),
      if (_dataUnreadable) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white70),
          ),
          onPressed: () => _confirmStartFresh(context),
          child: const Text('Start fresh (keep old file aside)'),
        ),
      ],
    ],
  );
}

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.gate});
  final AppGateController gate;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.gate.submitActivation(_token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.ok ? null : r.message;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _token.text = data!.text!.trim();
  }

  @override
  Widget build(BuildContext context) {
    final gate = widget.gate;
    final state = gate.activation;
    if (state?.phase == ActivationPhase.notConfigured) {
      return const BrandedPanel(
        children: [
          Text(
            'This copy of the app has not been set up for a company yet. '
            'Please install the copy provided by your administrator.',
            textAlign: TextAlign.center,
            style: _onBlue,
          ),
        ],
      );
    }
    final code = state?.requestCode ?? '';
    final fp = state?.fingerprint ?? '';
    return BrandedPanel(
      children: [
        Text(
          'Activate this phone for ${gate.config.displayClientName}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '1. Send the request code below to your administrator.\n'
          '2. Paste the activation code they send back, then tap Activate.\n'
          'No internet is needed.',
          style: _onBlue,
        ),
        if (state?.problem != null) ...[
          const SizedBox(height: 12),
          Text(
            state!.problem!,
            style: _onBlue.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Request code',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Phone fingerprint: ${groupForDisplay(fp)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: code.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: code));
                          showMessage(context, 'Request code copied');
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy request code'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _token,
                  minLines: 3,
                  maxLines: 5,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(
                    labelText: 'Activation code',
                    errorText: _error,
                    errorMaxLines: 4,
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _paste,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _activate,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Activate'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
