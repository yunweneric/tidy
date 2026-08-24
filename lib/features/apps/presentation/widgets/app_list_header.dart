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
    this.onRefreshPressed,
    this.isRefreshing = false,
  });

  final String title;
  final int selectedCount;
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onRefreshPressed;
  final bool isRefreshing;

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
          Flexible(
            child: Text(
              title,
              style: AppTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Only meaningful once something is selected.
          if (selectedCount > 0) ...[
            const SizedBox(width: 16),
            AppPill(label: 'Selected: $selectedCount'),
          ],
          const Spacer(),
          Flexible(
            child: AppSearchField(
              hintText: searchHint,
              width: 280,
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          if (isRefreshing)
            const SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentBlue,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
              tooltip: 'Rescan applications',
              onPressed: onRefreshPressed,
            ),
          const SizedBox(width: 8),
          const AppAvatar(),
        ],
      ),
    );
  }
}
