import 'package:flutter/material.dart';
import 'package:tidy/core/design/design.dart';
import 'package:tidy/core/feedback/feedback_tone.dart';
import 'package:tidy/core/widgets/ambient_background.dart';

/// One button on a toast. At most one — a toast with a choice in it is an
/// alert that has not admitted it yet.
@immutable
class ToastAction {
  const ToastAction({
    required this.label,
    required this.onPressed,
    this.dismissOnPressed = true,
  });

  final String label;
  final VoidCallback onPressed;

  /// Leave true for anything that opens something else. Set false only for an
  /// action the user might reasonably hit twice.
  final bool dismissOnPressed;
}

/// Everything one toast needs. Built by [TidyToaster.show]; call sites use the
/// `context.showToast` helpers below rather than constructing this by hand.
@immutable
class ToastSpec {
  const ToastSpec({
    required this.message,
    this.title,
    this.tone = FeedbackTone.neutral,
    this.icon,
    this.duration,
    this.action,
    this.dismissible = true,
  });

  /// The line that says what happened. Plain language, no jargon.
  final String message;

  /// Optional headline. Use it when the result has a figure in it worth
  /// reading first — “1.2 GB moved to Trash” over a line explaining the rest.
  final String? title;

  final FeedbackTone tone;

  /// Overrides the tone's glyph.
  final IconData? icon;

  /// Overrides [FeedbackToneTokens.defaultDuration]. `Duration.zero` pins the
  /// toast open until it is dismissed.
  final Duration? duration;

  final ToastAction? action;

  /// Whether the close button is offered. A pinned toast should keep it.
  final bool dismissible;

  Duration get effectiveDuration => duration ?? tone.defaultDuration;
}

/// A live toast, so a caller that showed one can take it down again.
class ToastHandle {
  const ToastHandle._(this._dismiss);

  final VoidCallback _dismiss;

  /// Plays the exit animation and removes the toast. Safe to call twice.
  void dismiss() => _dismiss();
}

/// The toast host.
///
/// **Every toast in the app appears in the bottom-right corner.** That is not a
/// default a call site can override — there is no alignment parameter, because
/// the only thing a per-call choice buys is toasts that arrive somewhere
/// different depending on which screen produced them, and the whole value of a
/// corner is that the user learns to glance at it.
///
/// Toasts live in the **root overlay**, not in the page, for two reasons: a
/// result that arrives while the user is navigating away should still be seen,
/// and a module page rebuilding its subtree should not take its own
/// confirmation down with it.
///
/// The layer is inserted on the first toast and removed again when the last
/// one leaves, so an idle window carries no extra overlay entry — and a dialog
/// opened afterwards is not sitting underneath an invisible layer.
class TidyToaster {
  const TidyToaster._();

  /// Beyond this the oldest toast is retired early. A column of six is a log,
  /// and nobody reads a log that is dismissing itself.
  static const int maxVisible = 3;

  static final Map<OverlayState, _ToastHost> _hosts = {};

  static ToastHandle show(BuildContext context, ToastSpec spec) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final host = _hosts.putIfAbsent(overlay, () => _ToastHost(overlay));
    // Captured here, not read inside the card: the toast layer lives in the
    // root overlay, above `AmbientBackground`, so it cannot see the module for
    // itself. A toast belongs to the module that produced it and keeps that
    // colour even if the user has since navigated somewhere else.
    return host.add(spec, ModuleTint.read(context));
  }

  /// Takes down everything on screen — for a page that is about to replace its
  /// own result, or a flow that has moved on.
  static void dismissAll(BuildContext context) {
    _hosts[Overlay.of(context, rootOverlay: true)]?.dismissAll();
  }
}

/// Convenience entry points. `context.toastSuccess('…')` reads at the call
/// site the way the result reads on screen.
extension TidyToastX on BuildContext {
  ToastHandle showToast({
    required String message,
    String? title,
    FeedbackTone tone = FeedbackTone.neutral,
    IconData? icon,
    Duration? duration,
    ToastAction? action,
    bool dismissible = true,
  }) => TidyToaster.show(
    this,
    ToastSpec(
      message: message,
      title: title,
      tone: tone,
      icon: icon,
      duration: duration,
      action: action,
      dismissible: dismissible,
    ),
  );

  ToastHandle toastSuccess(
    String message, {
    String? title,
    ToastAction? action,
    Duration? duration,
  }) => showToast(
    message: message,
    title: title,
    tone: FeedbackTone.success,
    action: action,
    duration: duration,
  );

  ToastHandle toastWarning(
    String message, {
    String? title,
    ToastAction? action,
    Duration? duration,
  }) => showToast(
    message: message,
    title: title,
    tone: FeedbackTone.warning,
    action: action,
    duration: duration,
  );

  ToastHandle toastError(
    String message, {
    String? title,
    ToastAction? action,
    Duration? duration,
  }) => showToast(
    message: message,
    title: title,
    tone: FeedbackTone.danger,
    action: action,
    duration: duration,
  );

  ToastHandle toastInfo(
    String message, {
    String? title,
    ToastAction? action,
    Duration? duration,
  }) => showToast(
    message: message,
    title: title,
    tone: FeedbackTone.info,
    action: action,
    duration: duration,
  );
}

// ─── Host ──────────────────────────────────────────────────────────────────

/// One overlay's worth of toasts.
///
/// The queue lives here rather than in the layer's `State` so [TidyToaster.show]
/// can add to it synchronously — the layer's state does not exist until the
/// frame after the entry is inserted.
class _ToastHost {
  _ToastHost(this._overlay) {
    _entry = OverlayEntry(builder: (_) => _ToastLayer(host: this));
    _overlay.insert(_entry);
  }

  final OverlayState _overlay;
  late final OverlayEntry _entry;

  final ValueNotifier<List<_LiveToast>> toasts = ValueNotifier(const []);

  int _nextId = 0;
  bool _disposed = false;

  ToastHandle add(ToastSpec spec, ModulePalette? palette) {
    final toast = _LiveToast(_nextId++, spec, palette);
    final next = [...toasts.value, toast];

    // Retire from the top rather than refusing the new one: the most recent
    // result is the one the user is waiting on.
    for (var i = 0; i < next.length - TidyToaster.maxVisible; i++) {
      next[i].close();
    }
    toasts.value = next;

    return ToastHandle._(toast.close);
  }

  void dismissAll() {
    for (final toast in toasts.value) {
      toast.close();
    }
  }

  /// Called by a card once its exit animation has finished.
  void remove(_LiveToast toast) {
    if (_disposed) return;
    toasts.value = [...toasts.value]..remove(toast);
    if (toasts.value.isEmpty) _scheduleTeardown();
  }

  /// Post-frame: `remove` runs from an animation callback, and mutating the
  /// overlay mid-frame is not allowed.
  ///
  /// The notifiers are left to the collector rather than disposed. The layer
  /// they feed is still mounted for one more frame after `remove()`, and a
  /// `ValueListenableBuilder` reading a disposed notifier is an assertion, not
  /// a warning.
  void _scheduleTeardown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || toasts.value.isNotEmpty) return;
      _disposed = true;
      TidyToaster._hosts.remove(_overlay);
      _entry.remove();
    });
  }
}

class _LiveToast {
  _LiveToast(this.id, this.spec, this.palette);

  final int id;
  final ToastSpec spec;

  /// The module this toast came from, captured when it was shown.
  final ModulePalette? palette;

  /// Flipped to true to ask the card to play its exit and then report back.
  final ValueNotifier<bool> closing = ValueNotifier(false);

  void close() => closing.value = true;
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer({required this.host});

  final _ToastHost host;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Align(
            alignment: Alignment.bottomRight,
            child: ValueListenableBuilder<List<_LiveToast>>(
              valueListenable: host.toasts,
              builder: (context, toasts, _) {
                // Newest nearest the bottom edge, so the eye lands on it
                // without following the stack up.
                final ordered = toasts.reversed.toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final toast in ordered)
                      _ToastCard(
                        key: ValueKey(toast.id),
                        toast: toast,
                        onGone: () => host.remove(toast),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Card ──────────────────────────────────────────────────────────────────

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.toast, required this.onGone});

  final _LiveToast toast;
  final VoidCallback onGone;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard> with TickerProviderStateMixin {
  /// Enter and exit. Runs forward on insert, reverse on dismiss.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: Duration.zero,
    reverseDuration: Duration.zero,
  );

  /// Counts out the toast's lifetime, and draws the hairline underneath it.
  /// Paused while the pointer is over the card — a toast that vanishes while
  /// you are reading it is worse than no toast.
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  /// Enter/exit eased with the motion tokens. Built once in
  /// `didChangeDependencies` — a `CurvedAnimation` per build would pile
  /// listeners onto `_enter`.
  CurvedAnimation? _curve;

  bool _started = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.toast.closing.addListener(_onCloseRequested);
    _life.addStatusListener((status) {
      if (status == AnimationStatus.completed) _leave();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final motion = context.motion;
    _enter.duration = motion.normal;
    _enter.reverseDuration = motion.fast;
    _curve = CurvedAnimation(
      parent: _enter,
      curve: motion.standard,
      reverseCurve: Curves.easeInCubic,
    );

    // Controllers do not honour Reduce Motion on their own — a zero duration
    // still schedules a tick. Land on the end value instead.
    if (motion.reduced) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }

    final life = widget.toast.spec.effectiveDuration;
    if (life > Duration.zero) {
      _life.duration = life;
      _life.forward();
    }
  }

  @override
  void dispose() {
    widget.toast.closing.removeListener(_onCloseRequested);
    _curve?.dispose();
    _enter.dispose();
    _life.dispose();
    super.dispose();
  }

  void _onCloseRequested() {
    if (widget.toast.closing.value) _leave();
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _life.stop();
    if (context.motion.reduced) {
      _enter.value = 0;
    } else {
      await _enter.reverse();
    }
    if (mounted) widget.onGone();
  }

  void _hover(bool hovering) {
    if (_leaving || widget.toast.spec.effectiveDuration == Duration.zero) {
      return;
    }
    if (hovering) {
      _life.stop();
    } else {
      _life.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final spec = widget.toast.spec;
    final tone = spec.tone.color(colors);

    final curved = _curve ?? kAlwaysDismissedAnimation;

    // The overlay sits outside any Scaffold, so there is no Material above
    // this — and the close button's ink response needs one.
    final card = Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 300),
          decoration: BoxDecoration(
            borderRadius: AppRadii.lgAll,
            // The one place a shadow is right: a toast floats free over the
            // window with no border of the page to sit against.
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadii.lgAll,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Floats over the window, so it is opaque — a sheer toast over a
                // table of file paths cannot be read.
                color: colors.surfaceOpaque,
                border: Border.all(color: colors.border),
                borderRadius: AppRadii.lgAll,
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: _content(colors, tone, spec),
                  ),
                  // The rail carries the tone at full strength. Everything else
                  // on the card stays neutral, so one glance is enough.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: tone),
                  ),
                  if (spec.effectiveDuration > Duration.zero && !motion.reduced)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _LifeBar(life: _life, tone: tone),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return SizeTransition(
      sizeFactor: curved,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          // Rises into place from below, which is where it lives.
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(curved),
          child: Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: card),
        ),
      ),
    );
  }

  Widget _content(AppColorTokens colors, Color tone, ToastSpec spec) {
    final hasTitle = spec.title != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.14),
            borderRadius: AppRadii.mdAll,
          ),
          child: Icon(spec.icon ?? spec.tone.icon, size: 17, color: tone),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTitle) Text(spec.title!, style: context.text.titleS),
                if (hasTitle) const SizedBox(height: AppSpacing.xxs),
                Text(
                  spec.message,
                  style: hasTitle ? context.text.bodyS : context.text.bodyM,
                ),
                if (spec.action != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ToastActionButton(
                    action: spec.action!,
                    onDone: () {
                      if (spec.action!.dismissOnPressed) _leave();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        if (spec.dismissible)
          IconButton(
            icon: const Icon(AppIcons.close, size: 14),
            color: colors.textMuted,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            onPressed: _leave,
          )
        else
          const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

/// The lifetime hairline. Drains left to right, and freezes on hover.
class _LifeBar extends StatelessWidget {
  const _LifeBar({required this.life, required this.tone});

  final Animation<double> life;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: AnimatedBuilder(
        animation: life,
        builder: (context, _) {
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (1 - life.value).clamp(0.0, 1.0),
              child: ColoredBox(color: tone.withValues(alpha: 0.45)),
            ),
          );
        },
      ),
    );
  }
}

/// The toast's one button: a neutral translucent pill.
///
/// Not tinted, and never a gradient — the rail already says what kind of news
/// this is, and a coloured button next to a coloured rail is two signals
/// competing for the same glance.
class _ToastActionButton extends StatefulWidget {
  const _ToastActionButton({required this.action, required this.onDone});

  final ToastAction action;
  final VoidCallback onDone;

  @override
  State<_ToastActionButton> createState() => _ToastActionButtonState();
}

class _ToastActionButtonState extends State<_ToastActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          widget.action.onPressed();
          widget.onDone();
        },
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: context.motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm - 2,
          ),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surfaceRaised,
            borderRadius: AppRadii.smAll,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            widget.action.label,
            style: context.text.label.copyWith(color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}
