import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';

/// GitHub release notes, set in the app's own type.
///
/// This used to be a bare [Text] on the raw body, on the reasoning that release
/// notes were a handful of bullet points and a markdown renderer to set them in
/// bold would be a dependency bigger than the feature it served. The first half
/// of that stopped being true: the notes are a whole document now — a heading,
/// a download table, a quoted warning, bullets, inline code and links — and a
/// reader who is shown `## 🧹 Tidy v1.0.13` and `| --- | --- |` is being handed
/// the source of a page rather than the page.
///
/// The second half still holds, which is why this is ~200 lines rather than a
/// package. It renders **exactly** the subset the notes are written in, and
/// anything outside that subset falls through as its own plain text rather than
/// disappearing — a notes viewer that silently drops what it cannot parse is
/// worse than one that shows an asterisk.
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(notes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].spaceAbove),
          blocks[i].build(context),
        ],
      ],
    );
  }
}

// Compiled once at load rather than per line. `_parse` walks every line of the
// document against all three, and building them inside the loop meant compiling
// a hundred and eighty regexes to read sixty lines.
final _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
final _rulePattern = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
final _bulletPattern = RegExp(r'^[-*+]\s+(.*)$');
final _cellRulePattern = RegExp(r'^:?-{2,}:?$');

/// `**bold**`, `` `code` ``, `[text](url)` and `*italic*`, in one pass.
final _inlinePattern = RegExp(
  r'\*\*(.+?)\*\*'
  r'|`([^`]+)`'
  r'|\[([^\]]+)\]\(([^)]*)\)'
  r'|(?<![*\w])\*([^*\n]+)\*(?![*\w])',
);

/// One rendered block, and how much air it wants above it.
class _Block {
  const _Block(this.build, {this.spaceAbove = AppSpacing.sm});

  final Widget Function(BuildContext context) build;
  final double spaceAbove;
}

List<_Block> _parse(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];

  // A paragraph runs until a blank line, so soft-wrapped prose is re-joined
  // rather than broken at whatever column the author happened to wrap it.
  final paragraph = <String>[];
  final quote = <String>[];
  final table = <List<String>>[];

  // A bullet, and the wrapped lines under it. Markdown indents the rest of a
  // long bullet; kept in a buffer like the paragraph above so it comes out as
  // one flowing sentence rather than re-broken at whatever column the author
  // happened to wrap it at, which is a different width from the one it is
  // being read at.
  final bullet = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join(' ');
    paragraph.clear();
    blocks.add(_Block((context) => _paragraph(context, text)));
  }

  void flushBullet() {
    if (bullet.isEmpty) return;
    final text = bullet.join(' ');
    bullet.clear();
    blocks.add(
      _Block((context) => _bullet(context, text), spaceAbove: AppSpacing.xs),
    );
  }

  void flushQuote() {
    if (quote.isEmpty) return;
    final text = quote.join(' ');
    quote.clear();
    blocks.add(_Block((context) => _quote(context, text)));
  }

  void flushTable() {
    if (table.isEmpty) return;
    final rows = List<List<String>>.of(table);
    table.clear();
    blocks.add(_Block((context) => _table(context, rows)));
  }

  void flushAll() {
    flushBullet();
    flushParagraph();
    flushQuote();
    flushTable();
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushAll();
      continue;
    }

    if (trimmed.startsWith('|')) {
      flushBullet();
      flushParagraph();
      flushQuote();
      final cells = _cells(trimmed);
      // `| --- | --- |` is scaffolding for a renderer that draws rules. This one
      // does not, so the separator has nothing to say.
      if (!cells.every(_isRule)) table.add(cells);
      continue;
    }
    flushTable();

    if (trimmed.startsWith('>')) {
      flushBullet();
      flushParagraph();
      quote.add(trimmed.substring(1).trim());
      continue;
    }
    flushQuote();

    final heading = _headingPattern.firstMatch(trimmed);
    if (heading != null) {
      flushBullet();
      flushParagraph();
      final level = heading.group(1)!.length;
      final text = heading.group(2)!.trim();
      blocks.add(
        _Block(
          (context) => _heading(context, text, level),
          // More air above a heading than between paragraphs, which is what
          // makes the sections read as sections rather than as more prose.
          spaceAbove: AppSpacing.lg,
        ),
      );
      continue;
    }

    if (_rulePattern.hasMatch(trimmed)) {
      flushBullet();
      flushParagraph();
      blocks.add(
        _Block(
          (context) => Divider(height: 1, color: context.colors.border),
          spaceAbove: AppSpacing.lg,
        ),
      );
      continue;
    }

    final marker = _bulletPattern.firstMatch(trimmed);
    if (marker != null) {
      flushBullet();
      flushParagraph();
      bullet.add(marker.group(1)!);
      continue;
    }

    // An indented line under an open bullet is the rest of that bullet, not a
    // new paragraph hanging beneath the list with no marker of its own.
    if (bullet.isNotEmpty && raw.startsWith('  ')) {
      bullet.add(trimmed);
      continue;
    }
    flushBullet();

    paragraph.add(trimmed);
  }

  flushAll();
  return blocks;
}

Widget _heading(BuildContext context, String text, int level) => Text.rich(
  TextSpan(children: _inline(context, text, context.text.titleS)),
  style: (level <= 2 ? context.text.titleM : context.text.titleS).copyWith(
    color: context.colors.textPrimary,
  ),
);

Widget _paragraph(BuildContext context, String text) =>
    Text.rich(TextSpan(children: _inline(context, text, _body(context))));

Widget _bullet(BuildContext context, String text) {
  final body = _body(context);

  return Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•', style: body),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text.rich(TextSpan(children: _inline(context, text, body))),
        ),
      ],
    ),
  );
}

/// A quoted warning, with the rule down its left that quotes have everywhere
/// else — the shape is what marks it as an aside before the words are read.
Widget _quote(BuildContext context, String text) {
  final colors = context.colors;

  return Container(
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: AppRadii.smAll,
      border: Border(left: BorderSide(color: colors.review, width: 2)),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    child: Text.rich(
      TextSpan(children: _inline(context, text, _body(context))),
    ),
  );
}

/// Two columns, because that is the only shape a table takes in these notes and
/// a general one would need horizontal scrolling inside a 240-point box.
///
/// A wider table is not dropped: everything past the second cell is folded into
/// the second column rather than lost.
Widget _table(BuildContext context, List<List<String>> rows) {
  final body = _body(context);
  final label = body.copyWith(color: context.colors.textPrimary);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text.rich(
                  TextSpan(
                    children: _inline(
                      context,
                      rows[i].first,
                      i == 0 ? label : body,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: _inline(
                      context,
                      rows[i].skip(1).join(' · '),
                      i == 0 ? label : body,
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

List<String> _cells(String row) {
  var text = row;
  if (text.startsWith('|')) text = text.substring(1);
  if (text.endsWith('|')) text = text.substring(0, text.length - 1);
  return [for (final cell in text.split('|')) cell.trim()];
}

bool _isRule(String cell) => _cellRulePattern.hasMatch(cell);

TextStyle _body(BuildContext context) => context.text.bodyS.copyWith(
  color: context.colors.textSecondary,
  height: 1.5,
);

/// The inline marks, resolved against [base].
///
/// A link renders as its text alone: nothing in the app can open a URL — there
/// is no `url_launcher` here — and a blue word that does nothing when clicked
/// promises more than a plain one.
List<InlineSpan> _inline(BuildContext context, String text, TextStyle base) {
  final colors = context.colors;
  final pattern = _inlinePattern;

  final spans = <InlineSpan>[];
  var at = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > at) {
      spans.add(TextSpan(text: text.substring(at, match.start), style: base));
    }

    if (match.group(1) != null) {
      spans.add(
        TextSpan(
          text: match.group(1),
          style: base.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      );
    } else if (match.group(2) != null) {
      spans.add(
        TextSpan(
          text: match.group(2),
          style: context.text.mono.copyWith(
            fontSize: base.fontSize,
            height: base.height,
            color: colors.textPrimary,
          ),
        ),
      );
    } else if (match.group(3) != null) {
      // Through `_inline` again rather than laid down as plain text: the notes
      // link commits as [`e5f8016`](url), and the label is marked up in its own
      // right — set flat it comes out with its backticks showing.
      spans.add(
        TextSpan(
          children: _inline(
            context,
            match.group(3)!,
            base.copyWith(color: colors.textPrimary),
          ),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: match.group(5),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }

    at = match.end;
  }

  if (at < text.length) {
    spans.add(TextSpan(text: text.substring(at), style: base));
  }
  return spans;
}
