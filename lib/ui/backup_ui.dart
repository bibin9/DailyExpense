import 'dart:io';

import 'package:flutter/material.dart';

import '../core/local_date.dart';
import '../core/money.dart';
import '../data/backup_service.dart';
import '../data/failures.dart';
import '../state/app_gate_controller.dart';
import 'theme.dart';
import 'widgets.dart';

String _backupFileName(DateTime now) =>
    'DailyExpenseTracker-backup-${LocalDate.fromDateTime(now).toIso()}.$backupFileExtension';

String _tmp(AppGateController gate, String name) =>
    '${gate.session!.dataDirPath}${Platform.pathSeparator}$name';

void _deleteQuietly(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } on Object {
    // Best effort; the folder is app-private and excluded from backups.
  }
}

/// Non-dismissible "working…" dialog. Returns a function that closes it.
Future<void Function()> _showBusy(BuildContext context, String text) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  // Let the dialog paint before synchronous database work starts.
  await Future<void>.delayed(const Duration(milliseconds: 120));
  return () {
    if (nav.canPop()) nav.pop();
  };
}

/// Settings / Home → "Create backup".
Future<void> startCreateBackup(
  BuildContext context,
  AppGateController gate,
) async {
  final password = await showDialog<String>(
    context: context,
    builder: (_) => const _CreatePasswordDialog(),
  );
  if (password == null || !context.mounted) return;

  final session = gate.session!;
  final tmp = _tmp(gate, 'backup-export.tmp');
  final close = await _showBusy(context, 'Creating encrypted backup…');
  BackupInfo? info;
  String? error;
  try {
    info = session.backups.createBackup(
      outPath: tmp,
      password: password,
      nowUtcMs: session.nowUtcMs(),
    );
  } on AppFailure catch (f) {
    error = f.userMessage;
  } on Object {
    error = 'The backup could not be created. Please try again.';
  } finally {
    close();
  }
  if (error != null) {
    _deleteQuietly(tmp);
    if (context.mounted) showMessage(context, error, error: true);
    return;
  }

  bool saved;
  try {
    saved = await session.platform.saveFileAs(
      sourcePath: tmp,
      fileName: _backupFileName(session.clock.now()),
    );
  } on Object {
    saved = false;
    error = 'The backup file could not be saved there. Try another place.';
  } finally {
    _deleteQuietly(tmp);
  }
  session.dataChanged(); // refresh "last backup" and the reminder
  if (!context.mounted) return;
  if (error != null) {
    showMessage(context, error, error: true);
  } else if (saved) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup saved'),
        content: Text(
          '${info!.expenseCount} expenses are in the backup file.\n\n'
          'Keep the file somewhere safe that is not this phone, and remember '
          'the password. Without the password nobody — not even your '
          'administrator — can open the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
    showMessage(context, 'Backup not saved.');
  }
}

/// Settings / Home (empty) → "Restore from backup".
Future<void> startRestore(BuildContext context, AppGateController gate) async {
  final session = gate.session!;
  if (session.expenses.count() > 0) {
    showMessage(
      context,
      'Restore is only available on a phone with no expenses yet.',
      error: true,
    );
    return;
  }
  final picked = _tmp(gate, 'backup-import.tmp');
  _deleteQuietly(picked);
  bool ok;
  try {
    ok = await session.platform.pickFile(destinationPath: picked);
  } on Object {
    ok = false;
    if (context.mounted) {
      showMessage(context, 'That file could not be opened.', error: true);
    }
  }
  if (!ok || !context.mounted) {
    _deleteQuietly(picked);
    return;
  }

  try {
    // Ask for the password until it opens the backup (or the user cancels).
    final unlocked = await showDialog<(String, BackupInfo)>(
      context: context,
      builder: (_) => _RestorePasswordDialog(path: picked),
    );
    if (unlocked == null || !context.mounted) return;
    final (password, info) = unlocked;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          [
            if (info.createdAtUtcMs > 0)
              'Backup made on ${formatDateLong(LocalDate.fromDateTime(DateTime.fromMillisecondsSinceEpoch(info.createdAtUtcMs)))}.',
            info.expenseCount == 1
                ? '1 expense'
                : '${info.expenseCount} expenses'
                      '${info.firstDate == null ? '' : ', ${formatDateLong(info.firstDate!)} – ${formatDateLong(info.lastDate!)}'}.',
            'Total ${formatAed(info.totalFils)} · ${info.categoryCount} categories.',
            '',
            'The categories on this phone will be replaced by the ones in '
                'the backup. This phone stays activated.',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final close = await _showBusy(context, 'Restoring your records…');
    String? error;
    try {
      await gate.restoreFromBackup(picked, password);
    } on AppFailure catch (f) {
      error = f.userMessage;
    } on Object {
      error = 'The backup could not be restored. Nothing was changed.';
    } finally {
      close();
    }
    // On success the main screen is rebuilt and shows the notice; on
    // failure the original (still empty) data is untouched.
    if (error != null && context.mounted) {
      showMessage(context, error, error: true);
    }
  } finally {
    _deleteQuietly(picked);
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.errorText,
    this.autofocus = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    onSubmitted: (_) => widget.onSubmitted?.call(),
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.errorText,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

class _CreatePasswordDialog extends StatefulWidget {
  const _CreatePasswordDialog();
  @override
  State<_CreatePasswordDialog> createState() => _CreatePasswordDialogState();
}

class _CreatePasswordDialogState extends State<_CreatePasswordDialog> {
  final _pw = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final err = validateBackupPassword(_pw.text, _again.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, _pw.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create backup'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a password for this backup (at least '
          '$minBackupPasswordLength characters). You will need it to restore '
          'on a new phone. If you forget it, the backup cannot be opened.',
        ),
        const SizedBox(height: 12),
        _PasswordField(
          controller: _pw,
          label: 'Backup password',
          autofocus: true,
        ),
        const SizedBox(height: 8),
        _PasswordField(
          controller: _again,
          label: 'Type it again',
          errorText: _error,
          onSubmitted: _submit,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}

class _RestorePasswordDialog extends StatefulWidget {
  const _RestorePasswordDialog({required this.path});
  final String path;
  @override
  State<_RestorePasswordDialog> createState() => _RestorePasswordDialogState();
}

class _RestorePasswordDialogState extends State<_RestorePasswordDialog> {
  final _pw = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    // Let the spinner paint; key derivation takes a moment by design.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    try {
      final info = BackupService.inspectBackup(widget.path, _pw.text);
      if (mounted) Navigator.pop(context, (_pw.text, info));
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.userMessage);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Backup password'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Type the password that was chosen when the backup was made.',
        ),
        const SizedBox(height: 12),
        _PasswordField(
          controller: _pw,
          label: 'Backup password',
          autofocus: true,
          errorText: _error,
          onSubmitted: _submit,
        ),
        if (_checking) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _checking ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _checking ? null : _submit,
        child: const Text('Open'),
      ),
    ],
  );
}

/// Home-screen reminder card.
class BackupReminderCard extends StatelessWidget {
  const BackupReminderCard({
    super.key,
    required this.onBackup,
    required this.onLater,
  });
  final VoidCallback onBackup;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Card(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.backup_outlined, color: Color(0xFF8A4B00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time for a backup',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'It has been over a month. If this phone is lost or replaced, '
              'a backup is the only way to get your records back.',
              style: TextStyle(color: AppColors.text),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onLater, child: const Text('Later')),
                TextButton(
                  onPressed: onBackup,
                  child: const Text('Back up now'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
