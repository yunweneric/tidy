import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/features/clipboard/data/models/clipboard_entry.dart';
import 'package:tidy/features/clipboard/data/services/clipboard_service.dart';

/// Column geometry, shared by the header and every row.
///
/// One spec used by both, for the reason `AppTableLayout` exists: a header that
/// declares its own widths ends up with labels that do not sit above their data.
@immutable
class ClipboardTableLayout {
  const ClipboardTableLayout._();

  /// Fixed: these are short and predictable, and letting them flex shifts the
  /// columns every time the list is filtered.
  static const double from = 140;
  static const double copies = 72;
  static const double when = 116;
  static const double actions = 128;

  static const int contentFlex = 5;

  static const double rowHeight = 56;
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
  );
}

/// One entry in the history.
///
/// Tapping the row copies it back, because that is what someone opening this
/// page came to do. Everything else — pin, remove, reveal — is on hover, so a
/// list of two hundred rows is two hundred previews rather than six hundred
/// buttons.
class ClipboardRow extends StatefulWidget {
  const ClipboardRow({
    super.key,
    required this.entry,
    required this.revealed,
    required this.busy,
    required this.onCopy,
    required this.onTogglePin,
    required this.onDelete,
    required this.onReveal,
    required this.onOpen,
    required this.service,
    this.isLast = false,
  });

  final ClipboardEntry entry;

  /// False for a sensitive entry the user has not asked to see.
  final bool revealed;
  final bool busy;

  final VoidCallback onCopy;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  /// Un-blurs a sensitive row, or shows a copied file in Finder.
  final VoidCallback onReveal;

  /// Opens the full preview.
  final VoidCallback onOpen;

  /// Only for the image thumbnail, which loads itself.
  final ClipboardService service;

  final bool isLast;

  @override
  State<ClipboardRow> createState() => _ClipboardRowState();
}

class _ClipboardRowState extends State<ClipboardRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onCopy,
        onDoubleTap: widget.onOpen,
        child: AnimatedContainer(
          duration: context.motion.fast,
          height: ClipboardTableLayout.rowHeight,
          padding: ClipboardTableLayout.rowPadding,
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : Colors.transparent,
            border: widget.isLast
                ? null
                : Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: ClipboardTableLayout.contentFlex,
                child: _content(context),
              ),
              SizedBox(
                width: ClipboardTableLayout.from,
                child: Text(
                  entry.sourceAppName ?? 'Unknown app',
                  style: context.text.bodyM.copyWith(
                    color: entry.sourceAppName == null
                        ? colors.textMuted
                        : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: ClipboardTableLayout.copies,
                child: Text(
                  entry.copyCount > 1 ? '×${entry.copyCount}' : '—',
                  textAlign: TextAlign.right,
                  style: context.text.bodyM.copyWith(
                    color: entry.copyCount > 1
                        ? colors.textPrimary
                        : colors.textMuted,
                    fontWeight:
                        entry.copyCount > 1 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              SizedBox(
                width: ClipboardTableLayout.when,
                child: Text(
                  relativeTime(entry.lastCopiedAt),
                  textAlign: TextAlign.right,
                  style: context.text.bodyM.copyWith(color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: ClipboardTableLayout.actions,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _actions(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final entry = widget.entry;

    return Row(
      children: [
        _glyph(context),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _preview(context),
              const SizedBox(height: 1),
              Text(
                entry.isEmptied
                    ? '${entry.kind.label} · contents no longer stored'
                    : (entry.detail.isEmpty ? entry.kind.label : entry.detail),
                style: context.text.caption,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The preview, blurred when the guard flagged it.
  ///
  /// A blur rather than a row of asterisks: it says "there is something here
  /// and it is being kept from you", which is the honest description, and it
  /// still shows the shape and length so the row is recognisable.
  Widget _preview(BuildContext context) {
    final entry = widget.entry;
    final style = entry.prefersMono ? context.text.mono : context.text.titleS;

    final text = Text(
      entry.preview,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (widget.revealed) return text;

    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
        child: text,
      ),
    );
  }

  Widget _glyph(BuildContext context) {
    final entry = widget.entry;

    // A screenshot is far easier to recognise by sight than by "1280 × 800",
    // so an image row shows itself where every other row shows a glyph.
    if (entry.kind == ClipboardKind.image && entry.hasBlob) {
      return _Thumbnail(
        entry: entry,
        service: widget.service,
        blurred: !widget.revealed,
        fallback: _glyphTile(context),
      );
    }

    return _glyphTile(context);
  }

  Widget _glyphTile(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.mdAll,
      ),
      child: Icon(
        entry.sensitive ? AppIcons.locked : entry.kind.icon,
        size: 16,
        color: entry.sensitive ? colors.review : colors.textSecondary,
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A pinned row keeps its pin visible; everything else earns its buttons
        // on hover.
        if (entry.pinned || _hovered)
          _IconAction(
            icon: entry.pinned ? AppIcons.unpin : AppIcons.pin,
            tooltip: entry.pinned ? 'Unpin' : 'Pin so it is never cleared',
            color: entry.pinned ? colors.accent : colors.textSecondary,
            onPressed: widget.busy ? null : widget.onTogglePin,
          )
        else
          const SizedBox(width: 30),
        if (_hovered && entry.sensitive && !widget.revealed)
          _IconAction(
            icon: AppIcons.reveal,
            tooltip: 'Show this once',
            color: colors.review,
            onPressed: widget.onReveal,
          )
        else if (_hovered && entry.kind == ClipboardKind.files)
          _IconAction(
            icon: AppIcons.revealInFinder,
            tooltip: 'Show in Finder',
            color: colors.textSecondary,
            onPressed: widget.onReveal,
          )
        else
          const SizedBox(width: 30),
        if (_hovered)
          _IconAction(
            icon: AppIcons.copy,
            tooltip: 'Copy back to the clipboard',
            color: colors.textSecondary,
            onPressed: widget.busy || entry.isEmptied ? null : widget.onCopy,
          )
        else
          const SizedBox(width: 30),
        if (_hovered)
          _IconAction(
            icon: AppIcons.delete,
            tooltip: 'Remove from the history',
            color: colors.risky,
            onPressed: widget.busy ? null : widget.onDelete,
          )
        else
          const SizedBox(width: 30),
      ],
    );
  }
}

/// The image itself, at row size.
///
/// Loads once per entry and keeps what it got: the row rebuilds on every hover,
/// and re-reading a PNG off disk for a mouse moving across the list would be
/// the most expensive thing on the page.
class _Thumbnail extends StatefulWidget {
  const _Thumbnail({
    required this.entry,
    required this.service,
    required this.blurred,
    required this.fallback,
  });

  final ClipboardEntry entry;
  final ClipboardService service;
  final bool blurred;

  /// Shown while it loads, and instead of it if the bytes have gone.
  final Widget fallback;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Thumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await widget.service.imageBytes(widget.entry);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return widget.fallback;

    return ClipRRect(
      borderRadius: AppRadii.mdAll,
      child: SizedBox(
        width: 34,
        height: 30,
        child: ImageFiltered(
          enabled: widget.blurred,
          imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}

/// Plain language over a timestamp: "3 minutes ago" is what someone scanning
/// for the thing they copied a moment ago is actually looking for.
String relativeTime(DateTime at) {
  final elapsed = DateTime.now().difference(at);
  if (elapsed.inSeconds < 45) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  if (elapsed.inDays == 1) return 'Yesterday';
  if (elapsed.inDays < 30) return '${elapsed.inDays} days ago';
  if (elapsed.inDays < 60) return 'Last month';
  if (elapsed.inDays < 365) return '${(elapsed.inDays / 30).floor()} months ago';
  return 'Over a year ago';
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 17),
      color: color,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
