import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/widgets/widgets.dart';
import 'package:tidy/core/models/clipboard_entry.dart';
import 'package:tidy/features/clipboard/logic/clipboard_state.dart';

/// The kind tabs, with counts.
///
/// Counts ignore the selected tab so they do not change when one is picked —
/// a tab that reads "Images 4" until you press it and then "Images 4, Text 0"
/// would be telling you about the filter rather than about the history.
class ClipboardFilterBar extends StatelessWidget {
  const ClipboardFilterBar({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final ClipboardState state;
  final ValueChanged<ClipboardKind?> onChanged;

  @override
  Widget build(BuildContext context) {
    const kinds = ClipboardKind.values;

    return Row(
      children: [
        SegmentedTabs(
          labels: ['All', for (final kind in kinds) kind.label],
          counts: [
            state.countFor(null),
            for (final kind in kinds) state.countFor(kind),
          ],
          selectedIndex:
              state.kind == null ? 0 : kinds.indexOf(state.kind!) + 1,
          onChanged: (index) =>
              onChanged(index == 0 ? null : kinds[index - 1]),
        ),
        const Spacer(),
        Text(
          'Click an item to copy it back · double-click to see all of it',
          style: context.text.caption,
        ),
      ],
    );
  }
}
