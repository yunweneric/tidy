import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tidy/core/design/design.dart';

/// A monospace command with a copy button.
class CopyBlock extends StatefulWidget {
  const CopyBlock({super.key, required this.command, this.label});

  final String command;
  final String? label;

  @override
  State<CopyBlock> createState() => _CopyBlockState();
}

class _CopyBlockState extends State<CopyBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.command));
    if (!mounted) return;
    setState(() => _copied = true);
    // Long enough to read, short enough that the button is not stuck saying
    // "Copied" when the visitor comes back to it.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: context.text.overline),
          const SizedBox(height: AppSpacing.sm),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadii.mdAll,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    widget.command,
                    style: context.text.mono.copyWith(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _copy,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceHover,
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? AppIcons.check : AppIcons.copy,
                          size: 14,
                          color: _copied ? colors.safe : colors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: context.text.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _copied ? colors.safe : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
