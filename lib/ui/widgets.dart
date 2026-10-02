import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/capture.dart';
import '../core/local_date.dart';
import '../core/money.dart';
import '../domain/models.dart';
import 'theme.dart';

/// "Daily Expense Tracker · Crafted by BCR"
class BcrSignature extends StatelessWidget {
  const BcrSignature({super.key, this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      '${Product.name} · ${Product.signature}',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.3,
        color: light ? Colors.white70 : AppColors.muted,
      ),
    ),
  );
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * 0.24),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.receipt_long_rounded,
      size: size * 0.6,
      color: AppColors.blue,
      semanticLabel: Product.name,
    ),
  );
}

/// Full-screen blue panel used by lock / activation / error screens.
class BrandedPanel extends StatelessWidget {
  const BrandedPanel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.blue,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo()),
                const SizedBox(height: 16),
                const Text(
                  Product.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                ...children,
                const SizedBox(height: 16),
                const BcrSignature(light: true),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
  });
  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 48, color: AppColors.blue.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ],
    ),
  );
}

String captureTimeLabel(BuildContext context, CaptureStamp c) => formatClock(
  c.hour,
  c.minute,
  use24h: MediaQuery.alwaysUse24HourFormatOf(context),
);

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    this.onTap,
    this.showDate = false,
  });
  final Expense expense;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final when = showDate
        ? '${formatDateShort(e.localDate)}, ${captureTimeLabel(context, e.captured)}'
        : captureTimeLabel(context, e.captured);
    final renamed = e.categoryLabelSnapshot != e.currentCategoryName;
    final subtitle = [
      when,
      if (!e.categoryIsActive) 'category turned off',
      if (renamed) 'recorded as ${e.categoryLabelSnapshot}',
      if (e.remarks != null) e.remarks!,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.blueLight,
        foregroundColor: AppColors.blueDark,
        child: Text(
          e.currentCategoryName.isEmpty
              ? '?'
              : e.currentCategoryName[0].toUpperCase(),
        ),
      ),
      title: Text(
        e.currentCategoryName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: AmountLabel(e.amountFils),
    );
  }
}

/// Floating-button label whose font scaling is capped at 1.3× so the button
/// never grows wider than a small phone's screen at large accessibility
/// font sizes (the rest of the app scales fully).
class FabLabel extends StatelessWidget {
  const FabLabel(this.text, {super.key, this.fontSize});
  final String text;
  final double? fontSize;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: Text(text, style: TextStyle(fontSize: fontSize)),
  );
}

/// An AED amount for the trailing side of a list row. Never wider than
/// ~38% of the screen; shrinks to fit on small phones / large fonts instead
/// of squeezing out the row's title (which breaks ListTile layout).
class AmountLabel extends StatelessWidget {
  const AmountLabel(this.fils, {super.key, this.fontSize = 15});
  final int fils;
  final double fontSize;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.38,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        formatAed(fils),
        maxLines: 1,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: fontSize),
      ),
    ),
  );
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}
