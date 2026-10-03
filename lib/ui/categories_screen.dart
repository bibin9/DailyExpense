import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/validation.dart';
import '../state/categories_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.controller});
  final CategoriesController controller;

  Future<void> _edit(BuildContext context, {Category? category}) async {
    final done = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(
        initial: category?.name ?? '',
        title: category == null ? 'Add category' : 'Rename category',
        save: (name) => category == null
            ? controller.add(name)
            : controller.rename(category.id, name),
      ),
    );
    if (done != null && context.mounted) {
      showMessage(
        context,
        category == null ? 'Category added' : 'Category renamed',
      );
    }
  }

  Future<void> _toggle(BuildContext context, Category c) async {
    if (c.isActive) {
      final used = controller.usage(c.id);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Turn off "${c.name}"?'),
          content: Text(
            'It will no longer appear when adding new expenses. '
            '${used == 0 ? 'It is not used yet.' : 'Its $used existing expense(s) keep it and still appear in reports.'} '
            'You can turn it back on any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final err = controller.setActive(c.id, !c.isActive);
    if (err != null && context.mounted) showMessage(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Categories')),
    floatingActionButton: controller.session.readOnly
        ? null
        : FloatingActionButton.extended(
            heroTag: 'fab-add-category',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const FabLabel('Add category'),
          ),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'These are the choices in the Description list. Turned-off '
              'categories stay on old expenses and in reports.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          for (final c in controller.all)
            ListTile(
              title: Text(
                c.name,
                style: TextStyle(
                  color: c.isActive ? AppColors.text : AppColors.muted,
                ),
              ),
              subtitle: Text(
                [
                  if (!c.isActive) 'Turned off',
                  if (c.requiresRemark) 'Remark required',
                ].join(' · '),
              ),
              leading: IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, category: c),
              ),
              trailing: Switch(
                value: c.isActive,
                onChanged: (_) => _toggle(context, c),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Owns its TextEditingController so the controller lives exactly as long
/// as the dialog (including its closing animation).
class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.initial,
    required this.title,
    required this.save,
  });

  final String initial;
  final String title;

  /// Returns null on success or an error message.
  final String? Function(String name) save;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final err = widget.save(_text.text);
    if (err == null) {
      Navigator.pop(context, 'saved');
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: maxCategoryNameLength,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Name',
        errorText: _error,
        errorMaxLines: 3,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
