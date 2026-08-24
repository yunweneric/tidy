import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/models/clipboard_entry.dart';
import 'package:tidy/features/clipboard/data/services/clipboard_service.dart';
import 'package:tidy/features/clipboard/presentation/widgets/clipboard_row.dart';

/// The whole of one entry, for when the single preview line is not enough.
///
/// The list deliberately shows one collapsed line per row; this is where the
/// rest of a long paste, or the actual pixels of a screenshot, live.
class ClipboardPreviewDialog extends StatelessWidget {
  const ClipboardPreviewDialog({
    super.key,
    required this.entry,
    required this.service,
    required this.onCopy,
  });

  final ClipboardEntry entry;
  final ClipboardService service;
  final VoidCallback onCopy;

  /// Opens the preview for [entry].
  static Future<void> show(
    BuildContext context, {
    required ClipboardEntry entry,
    required ClipboardService service,
    required VoidCallback onCopy,
  }) {
    return showTidyDialog<void>(
      context,
      builder: (_) => ClipboardPreviewDialog(
        entry: entry,
        service: service,
        onCopy: onCopy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TidyDialog(
      title: entry.kind.label,
      subtitle: _subtitle(),
      width: 620,
      maxContentHeight: 420,
      actions: [
        TidyDialogAction(
          label: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        TidyDialogAction(
          label: 'Copy',
          style: TidyActionStyle.primary,
          icon: AppIcons.copy,
          onPressed: entry.isEmptied
              ? null
              : () {
                  Navigator.of(context).maybePop();
                  onCopy();
                },
        ),
      ],
      child: _body(context),
    );
  }

  String _subtitle() {
    final parts = <String>[
      if (entry.sourceAppName != null) 'From ${entry.sourceAppName}',
      relativeTime(entry.lastCopiedAt),
      if (entry.copyCount > 1) 'copied ${entry.copyCount} times',
      if (entry.kind == ClipboardKind.image && entry.pixelWidth > 0)
        '${entry.pixelWidth} × ${entry.pixelHeight}',
      if (entry.byteCount > 0) formatBytes(entry.byteCount),
    ];
    return parts.join(' · ');
  }

  Widget _body(BuildContext context) {
    if (entry.isEmptied) {
      return Text(
        'The contents of this item are no longer stored — it was either larger '
        'than the size limit or cleared to keep the history under it. The row '
        'is kept so you can still see that you copied it.',
        style: context.text.bodyM,
      );
    }

    if (entry.kind == ClipboardKind.image) return _image(context);
    if (entry.kind == ClipboardKind.files) return _files(context);
    return _text(context);
  }

  Widget _image(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: service.imageBytes(entry),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Text('That image could not be read back.', style: context.text.bodyM);
        }
        return ClipRRect(
          borderRadius: AppRadii.mdAll,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      },
    );
  }

  Widget _files(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final path in entry.paths)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(path, style: context.text.mono),
          ),
      ],
    );
  }

  Widget _text(BuildContext context) {
    return FutureBuilder<String?>(
      future: service.fullText(entry),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final text = snapshot.data;
        if (text == null || text.isEmpty) {
          return Text('That text could not be read back.', style: context.text.bodyM);
        }
        return SelectableText(
          text,
          // Monospace throughout: this view is where people come to check an
          // exact string, and proportional type hides a doubled space.
          style: context.text.mono,
        );
      },
    );
  }
}
