import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/theme/app_theme.dart';
import 'package:mac_uninstaller/core/widgets/widgets.dart';

/// Page header with title, selection pill, search, and trailing actions.
class AppListHeader extends StatelessWidget {
  const AppListHeader({
    super.key,
    required this.title,
    this.selectedCount = 0,
    this.searchHint = 'Filter apps...',
    this.onSearchChanged,
    this.onNotificationsPressed,
  });

  final String title;
  final int selectedCount;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundPrimary,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(title, style: AppTheme.titleLarge),
          const SizedBox(width: 20),
          AppPill(label: 'Selected: $selectedCount'),
          const Spacer(),
          AppSearchField(
            hintText: searchHint,
            width: 280,
            onChanged: onSearchChanged,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppTheme.textSecondary),
            onPressed: onNotificationsPressed,
          ),
          const SizedBox(width: 8),
          const AppAvatar(),
        ],
      ),
    );
  }
}
