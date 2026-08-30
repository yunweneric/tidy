import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback.dart';
import 'package:tidy/core/utils/byte_format.dart';
import 'package:tidy/core/utils/home_dir.dart';
import 'package:tidy/core/models/launch_item.dart';

/// Confirms removing one launch item, and says what removal actually means.
///
/// Disabling and removing are not the same decision. Disabling is reversible
/// from this page; removing puts the file in the Trash and, if the owning app
/// is still installed, it may well write the file back the next time it runs.
/// Saying so up front is cheaper than a confused bug report afterwards.
///
/// A broken item is the one case with no real warning to give, so it does not
/// get one — an alert that cries wolf on the safe case is ignored on the
/// dangerous one.
Future<bool> showRemoveLaunchItemDialog(BuildContext context, LaunchItem item) {
  final broken = item.health == LaunchItemHealth.broken;

  return TidyAlert.confirm(
    context,
    tone: broken ? FeedbackTone.info : FeedbackTone.warning,
    icon: broken ? AppIcons.nothingFound : AppIcons.trash,
    title: 'Remove ${item.name}?',
    message:
        broken
            ? 'This cannot start anything — the program it points at is gone, '
                'or the file is empty. Removing it changes nothing except '
                'tidying up after whatever left it here.'
            : 'This stops the item and moves its settings file to the Trash. '
                'If the app it belongs to is still installed, it may put the '
                'file back the next time it runs — turning it off instead is '
                'the change that sticks.',
    details: [
      AlertDetail(title: collapseHome(item.path, kHomeDir)),
      if (item.removalNeedsAuthorization)
        AlertDetail(
          title: 'macOS will ask for your password',
          detail:
              'This one is set up for every account on this Mac. Tidy moves it '
              'to the Trash rather than deleting it, so you can put it back if '
              'you need to.',
          tone: FeedbackTone.warning,
          monospace: false,
        ),
    ],
    confirmLabel: 'Move to Trash',
    destructive: true,
  );
}
