import 'package:bcr_activation/bcr_activation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/local_date.dart';
import '../data/backup_service.dart';
import '../security/activation_service.dart';
import '../state/app_gate_controller.dart';
import 'backup_ui.dart';
import 'theme.dart';
import 'widgets.dart';

String _bytes(int? b) {
  if (b == null) return 'unknown';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.gate,
    required this.onOpenCategories,
  });
  final AppGateController gate;
  final VoidCallback onOpenCategories;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _free;
  String? _keyProtection;

  @override
  void initState() {
    super.initState();
    final s = widget.gate.session!;
    s.platform.freeBytes(s.dataDirPath).then((v) {
      if (mounted) setState(() => _free = v);
    });
    s.platform.installationKeyProtection().then((v) {
      if (mounted) setState(() => _keyProtection = v);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final gate = widget.gate;
    final s = gate.session!;
    final act = gate.activation;
    final claims = act?.claims;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Important: your records are kept only on this phone',
            icon: Icons.warning_amber_rounded,
            highlight: true,
            children: const [
              Text(
                'There is no cloud copy or sync. If the phone is lost, reset, '
                'or the app is removed or its data cleared, records since your '
                'last backup are gone permanently — not even your '
                'administrator or BCR can recover them. Make a backup '
                'regularly and keep the file somewhere other than this phone.',
              ),
            ],
          ),
          ListenableBuilder(
            listenable: s.revision,
            builder: (context, _) {
              final last = int.tryParse(s.meta.read(metaLastBackupAt) ?? '');
              final empty = s.expenses.count() == 0;
              return _Section(
                title: 'Backup and moving to a new phone',
                icon: Icons.backup_outlined,
                children: [
                  _kv(
                    'Last backup',
                    last == null
                        ? 'Never'
                        : formatDateLong(
                            LocalDate.fromDateTime(
                              DateTime.fromMillisecondsSinceEpoch(last),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A backup is one encrypted file protected by a password '
                    'you choose. Save it to Google Drive, a computer or a USB '
                    'stick. On a new phone, install the app, activate it, '
                    'then use Restore.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => startCreateBackup(context, gate),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Create backup'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: empty ? () => startRestore(context, gate) : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore from backup'),
                  ),
                  if (!empty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Restore is available only on a phone with no '
                        'expenses yet (for example, a new phone).',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                ],
              );
            },
          ),
          _Section(
            title: 'App lock',
            icon: Icons.lock_outline,
            children: [
              Text(
                'The app asks for your fingerprint, face or phone PIN when it '
                'opens, and again after ${gate.relockAfter.inMinutes} minutes in '
                'the background.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: gate.lockNow,
                icon: const Icon(Icons.lock),
                label: const Text('Lock now'),
              ),
            ],
          ),
          _Section(
            title: 'Categories',
            icon: Icons.category_outlined,
            children: [
              const Text(
                'Add, rename or turn off the choices in the Description list.',
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: widget.onOpenCategories,
                child: const Text('Manage categories'),
              ),
            ],
          ),
          _Section(
            title: 'Licence',
            icon: Icons.verified_user_outlined,
            children: [
              _kv('Company', gate.config.displayClientName),
              if (act?.companyLicence != null)
                _kv(
                  'Valid until',
                  act!.companyLicence!.expiresAt == null
                      ? 'No end date'
                      : formatDateLong(
                          LocalDate.fromDateTime(
                            act.companyLicence!.expiresAt!.toLocal().subtract(
                              const Duration(minutes: 1),
                            ),
                          ),
                        ),
                ),
              _kv('Status', switch (act?.phase) {
                ActivationPhase.activated when act?.companyLicence != null =>
                  'Company licence — active',
                ActivationPhase.licenceExpired => 'Licence ended — read-only',
                ActivationPhase.activated => 'Activated',
                ActivationPhase.devBypass =>
                  AppConfig.devBypassActive
                      ? 'DEVELOPMENT BYPASS – NOT FOR RELEASE'
                      : 'Not activated',
                _ => 'Not activated',
              }),
              if (claims != null) ...[
                _kv(
                  'Activated on',
                  formatDateLong(
                    LocalDate.fromDateTime(claims.issuedAt.toLocal()),
                  ),
                ),
                if (claims.label != null) _kv('Phone label', claims.label!),
                _kv(
                  'Expires',
                  claims.expiresAt == null
                      ? 'Never'
                      : formatDateLong(
                          LocalDate.fromDateTime(claims.expiresAt!.toLocal()),
                        ),
                ),
              ],
              if (act?.fingerprint != null)
                _kv('Fingerprint', groupForDisplay(act!.fingerprint!)),
            ],
          ),
          _Section(
            title: 'Storage on this phone',
            icon: Icons.storage_outlined,
            children: [
              _kv('Expenses saved', '${s.expenses.count()}'),
              _kv('Database size', _bytes(s.db.fileSizeBytes())),
              _kv('Free space', _bytes(_free)),
              _kv('Encryption', 'SQLCipher ${s.db.cipherVersion()} (AES-256)'),
              _kv('Key protection', _keyProtection ?? '…'),
            ],
          ),
          _Section(
            title: 'About',
            icon: Icons.info_outline,
            children: [
              _kv('App', '${Product.name} ${Product.version}'),
              _kv('Licensed to', gate.config.displayClientName),
              _kv('Made by', '${Product.vendorShort} (${Product.vendorLong})'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: Product.name,
                  applicationVersion:
                      '${Product.version} · ${Product.signature}',
                ),
                child: const Text('Open-source licences'),
              ),
            ],
          ),
          const BcrSignature(),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(k, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.highlight = false,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      color: highlight ? AppColors.notice : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    ),
  );
}
