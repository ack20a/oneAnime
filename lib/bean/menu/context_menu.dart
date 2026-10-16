import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class ContextMenuAction {
  const ContextMenuAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;
}

/// Lets the long press that opened a menu keep steering it: sliding the
/// finger highlights actions, lifting it on one picks it (Telegram's
/// press-slide-release), lifting elsewhere leaves the menu open for taps.
class ContextMenuHandle {
  _ContextMenuPageState? _state;

  void hover(Offset globalPosition) => _state?._hover(globalPosition);

  void release() => _state?._release();
}

/// Telegram-style context menu: the pressed item lifts out of the page over a
/// blurred, dimmed backdrop and springs into place, with its actions growing
/// out from beside it.
///
/// [anchor] is the widget that was pressed; [preview] is drawn in its place,
/// at the same width.
ContextMenuHandle showContextMenu({
  required BuildContext anchor,
  required Widget preview,
  required List<ContextMenuAction> actions,
}) {
  final ContextMenuHandle handle = ContextMenuHandle();
  final RenderBox box = anchor.findRenderObject()! as RenderBox;
  final Rect rect = box.localToGlobal(Offset.zero) & box.size;
  HapticFeedback.mediumImpact();
  // An overlay entry rather than a route: pushing a route cancels the
  // pointer that is still down, which would end press-slide-release.
  final OverlayState overlay = Overlay.of(anchor, rootOverlay: true);
  final ModalRoute<Object?>? route = ModalRoute.of(anchor);
  late final OverlayEntry entry;
  LocalHistoryEntry? backEntry;
  bool removed = false;
  void remove() {
    if (removed) {
      return;
    }
    removed = true;
    entry.remove();
    final LocalHistoryEntry? back = backEntry;
    backEntry = null;
    if (back != null) {
      route?.removeLocalHistoryEntry(back);
    }
  }

  entry = OverlayEntry(
    builder: (context) => _ContextMenuPage(
      handle: handle,
      sourceRect: rect,
      preview: preview,
      actions: actions,
      onClosed: remove,
    ),
  );
  overlay.insert(entry);
  // The back button closes the menu instead of leaving the page.
  backEntry = LocalHistoryEntry(onRemove: () {
    backEntry = null;
    handle._state?._close();
  });
  route?.addLocalHistoryEntry(backEntry!);
  return handle;
}

/// A spring settling over the route's duration, as a [Curve]: Telegram
/// animates the lift with a slightly underdamped spring (damping 104 over
/// 0.42 s), which overshoots by a hair.
class _SpringCurve extends Curve {
  const _SpringCurve();

  static final SpringSimulation _sim = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 180, ratio: 0.78),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) => t >= 1 ? 1 : _sim.x(t * 0.42);
}

class _ContextMenuPage extends StatefulWidget {
  const _ContextMenuPage({
    required this.handle,
    required this.sourceRect,
    required this.preview,
    required this.actions,
    required this.onClosed,
  });

  final ContextMenuHandle handle;
  final VoidCallback onClosed;
  final Rect sourceRect;
  final Widget preview;
  final List<ContextMenuAction> actions;

  @override
  State<_ContextMenuPage> createState() => _ContextMenuPageState();
}

class _ContextMenuPageState extends State<_ContextMenuPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 200),
  );
  static const double _menuWidth = 240;
  static const double _actionHeight = 48;
  static const double _gap = 10;

  final List<GlobalKey> _actionKeys = [];
  int? _highlighted;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.handle._state = this;
    _actionKeys
        .addAll(List.generate(widget.actions.length, (_) => GlobalKey()));
    _controller.forward();
  }

  @override
  void dispose() {
    if (widget.handle._state == this) {
      widget.handle._state = null;
    }
    super.dispose();
  }

  int? _actionAt(Offset globalPosition) {
    for (int i = 0; i < _actionKeys.length; i++) {
      final RenderBox? box =
          _actionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        continue;
      }
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) {
        return i;
      }
    }
    return null;
  }

  void _hover(Offset globalPosition) {
    final int? index = _actionAt(globalPosition);
    if (index != _highlighted) {
      if (index != null) {
        HapticFeedback.selectionClick();
      }
      setState(() => _highlighted = index);
    }
  }

  void _release() {
    final int? index = _highlighted;
    if (index != null) {
      _pick(index);
    }
  }

  void _close() {
    if (_closing) {
      return;
    }
    _closing = true;
    _controller.reverse().whenComplete(widget.onClosed);
  }

  void _pick(int index) {
    _close();
    widget.actions[index].onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double menuHeight = widget.actions.length * _actionHeight;
    final Rect source = widget.sourceRect;

    // Keep the preview where it was, but shift it up (or down) just enough
    // for the actions to fit below it on screen.
    final double previewHeight = source.height
        .clamp(0.0, screen.height - padding.vertical - menuHeight - _gap - 32);
    final double minTop = padding.top + 16;
    final double maxTop =
        screen.height - padding.bottom - 16 - menuHeight - _gap - previewHeight;
    final double targetTop =
        source.top.clamp(minTop, maxTop < minTop ? minTop : maxTop);
    final double menuLeft = (source.center.dx > screen.width / 2
            ? source.right - _menuWidth
            : source.left)
        .clamp(12.0, screen.width - _menuWidth - 12);
    final Alignment menuOrigin = source.center.dx > screen.width / 2
        ? Alignment.topRight
        : Alignment.topLeft;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        final bool reversing = _controller.status == AnimationStatus.reverse;
        final double lift = reversing
            ? Curves.easeInOut.transform(t)
            : const _SpringCurve().transform(t);
        // Backdrop and actions fade quickly in, then hold.
        final double fade = Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0));
        final double top = lerpDouble(source.top, targetTop, lift)!;
        final double actionsScale =
            reversing ? 0.1 + 0.9 * t : 0.01 + 0.99 * lift;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: BackdropFilter(
                  filter:
                      ImageFilter.blur(sigmaX: 15 * fade, sigmaY: 15 * fade),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.4 * fade),
                  ),
                ),
              ),
            ),
            Positioned(
              left: source.left,
              top: top,
              width: source.width,
              height: previewHeight,
              child: IgnorePointer(
                child: Material(
                  color: scheme.surface,
                  elevation: 8 * fade,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: widget.preview,
                  ),
                ),
              ),
            ),
            Positioned(
              left: menuLeft,
              top: top + previewHeight + _gap,
              width: _menuWidth,
              child: Opacity(
                opacity: fade,
                child: Transform.scale(
                  scale: actionsScale,
                  alignment: menuOrigin,
                  child: _actionsCard(scheme),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionsCard(ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < widget.actions.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 0.5, thickness: 0.5, color: scheme.outlineVariant),
            _actionRow(i, scheme),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(int index, ColorScheme scheme) {
    final ContextMenuAction action = widget.actions[index];
    final Color color = action.destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      key: _actionKeys[index],
      onTap: () => _pick(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: _actionHeight - 0.5,
        color: _highlighted == index
            ? scheme.onSurface.withValues(alpha: 0.1)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                action.title,
                style: TextStyle(color: color, fontSize: 16),
              ),
            ),
            Icon(action.icon, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
