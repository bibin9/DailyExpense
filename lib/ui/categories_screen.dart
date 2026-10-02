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
    final text = TextEditingController(text: category?.name ?? '');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            final err = category == null
                ? controller.add(text.text)
                : controller.rename(category.id, text.text);
            if (err == null) {
              Navigator.pop(ctx);
              showMessage(
                context,
                category == null ? 'Category added' : 'Category renamed',
              );
            } else {
              setState(() => error = err);
            }
          }

          return AlertDialog(
            title: Text(category == null ? 'Add category' : 'Rename category'),
            content: TextField(
              controller: text,
              autofocus: true,
              maxLength: maxCategoryNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    text.dispose();
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
    floatingActionButton: FloatingActionButton.extended(
      heroTag: 'fab-add-category',
      onPressed: () => _edit(context),
      icon: const Icon(Icons.add),
      label: const Text('Add category'),
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
