import 'package:flutter/material.dart';
import 'package:mac_uninstaller/core/design/design.dart';

/// The page frame every module wears.
///
/// Seven modules built independently would drift on title size, gutter width and
/// where the actions sit. Routing them all through one frame is what makes them
/// read as one app.
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.scrollable = true,
    this.contentPadding,
  });

  final String title;

  /// One non-technical line under the title.
  final String? subtitle;

  /// Right-aligned header controls (search, refresh, primary action).
  final List<Widget> actions;

  /// Sits between the header and the content — permission prompts, warnings.
  final Widget? banner;

  final Widget child;

  /// False when the module owns its own scrolling (tables, virtualised lists).
  final bool scrollable;

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final padding = contentPadding ??
        const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          0,
          AppSpacing.xxl,
          AppSpacing.xxl,
        );

    final content = Padding(
      padding: padding,
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: title, subtitle: subtitle, actions: actions),
        if (banner != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: banner,
          ),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(child: content)
              : content,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleL),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: context.text.bodyM),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
