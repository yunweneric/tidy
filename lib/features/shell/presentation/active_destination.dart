import 'package:flutter/widgets.dart';
import 'package:tidy/features/shell/domain/app_destination.dart';

/// Which destination the shell is currently showing.
///
/// Branches of a `StatefulShellRoute.indexedStack` stay mounted when you
/// navigate away — that is the whole point, since it keeps a running scan
/// alive. The cost is that a page has no ordinary way to know it has stopped
/// being visible: `ModalRoute.isCurrent` is true for every branch, and an
/// `IndexedStack` does not disable its hidden children's tickers.
///
/// For a page that only reads and draws, that costs nothing. For one that polls
/// — Heavy Consumers samples every process on the Mac every two seconds — it is
/// the difference between a monitor and a background battery drain. So the
/// shell publishes the active destination and pages that do periodic work stop
/// when they are not it.
class ActiveDestination extends InheritedWidget {
  const ActiveDestination({
    super.key,
    required this.destination,
    required super.child,
  });

  final AppDestination destination;

  /// True when [destination] is the one on screen right now.
  ///
  /// Registers a dependency, so the caller rebuilds when the shell moves — an
  /// `findAncestorStateOfType` read of the navigation shell would not.
  static bool isVisible(BuildContext context, AppDestination destination) {
    final active = context
        .dependOnInheritedWidgetOfExactType<ActiveDestination>()
        ?.destination;
    // Outside the shell (tests, the menu-bar engine) nothing is hidden.
    return active == null || active == destination;
  }

  @override
  bool updateShouldNotify(ActiveDestination oldWidget) =>
      oldWidget.destination != destination;
}
