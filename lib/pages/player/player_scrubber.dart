import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:oneanime/utils/utils.dart';

/// Fine scrubbing as Telegram does it: the further the finger strays
/// vertically from where the drag began, the slower the scrub. Telegram only
/// counts downward travel, but its scrubber sits mid-screen; ours hugs the
/// bottom edge in fullscreen, so either direction counts here.
class ScrubSpeed {
  static double multiplierFor(double verticalDistance) {
    final double d = verticalDistance.abs();
    if (d > 150) {
      return 0.01;
    }
    if (d > 100) {
      return 0.25;
    }
    if (d > 50) {
      return 0.5;
    }
    return 1;
  }

  /// Hint text for a slowed scrub, empty at full speed.
  static String labelFor(double multiplier) {
    if (multiplier >= 1) {
      return '';
    }
    if (multiplier >= 0.5) {
      return '半速拖动';
    }
    if (multiplier >= 0.25) {
      return '¼ 速拖动';
    }
    return '精细拖动';
  }
}

/// Seek bar modelled on Telegram's media scrubber:
/// - the played part advances smoothly between the player's position reports
/// - the buffered range animates instead of jumping
/// - the thumb springs up while held, and the touch target is much taller
///   than the 3 pt track
/// - dragging away vertically slows the scrub down (see [ScrubSpeed])
/// - a time bubble follows the thumb, and only releasing seeks; the scrubbed
///   value is held until the player catches up, so the thumb never snaps back
class PlayerScrubber extends StatefulWidget {
  const PlayerScrubber({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.playing,
    required this.rate,
    required this.color,
    required this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  final Duration position;
  final Duration buffered;
  final Duration duration;
  final bool playing;
  final double rate;
  final Color color;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  @override
  State<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<PlayerScrubber>
    with TickerProviderStateMixin {
  static const double _trackHeight = 3;
  static const double _thumbRadius = 7;
  static const double _hitHeight = 36;

  /// Player positions arrive every ~200 ms; extrapolate at most this far.
  static const Duration _maxExtrapolation = Duration(milliseconds: 400);

  late final Ticker _ticker;
  final ValueNotifier<double> _playedFraction = ValueNotifier(0);
  late final AnimationController _thumb;

  Duration _lastPosition = Duration.zero;
  final Stopwatch _sinceLastPosition = Stopwatch();

  bool _scrubbing = false;
  Duration _scrubValue = Duration.zero;
  double _anchorX = 0;
  Duration _anchorValue = Duration.zero;
  double _startY = 0;
  double _multiplier = 1;

  /// After a seek, the target shown until the player reports a nearby
  /// position, or [_holdUntil] passes.
  Duration? _heldValue;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _thumb = AnimationController.unbounded(vsync: this, value: 0);
    _ticker = createTicker((_) => _tick())..start();
    _lastPosition = widget.position;
    _sinceLastPosition.start();
  }

  @override
  void didUpdateWidget(PlayerScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) {
      _lastPosition = widget.position;
      _sinceLastPosition
        ..reset()
        ..start();
      final Duration? held = _heldValue;
      if (held != null &&
          (widget.position - held).inMilliseconds.abs() < 1500) {
        _heldValue = null;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _thumb.dispose();
    _playedFraction.dispose();
    super.dispose();
  }

  double _fractionOf(Duration value) {
    final int total = widget.duration.inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (value.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _tick() {
    Duration shown;
    if (_scrubbing) {
      shown = _scrubValue;
    } else if (_heldValue != null && DateTime.now().isBefore(_holdUntil)) {
      shown = _heldValue!;
    } else {
      _heldValue = null;
      shown = _lastPosition;
      if (widget.playing) {
        Duration ahead = _sinceLastPosition.elapsed * widget.rate;
        if (ahead > _maxExtrapolation) {
          ahead = _maxExtrapolation;
        }
        shown += ahead;
      }
    }
    _playedFraction.value = _fractionOf(shown);
  }

  void _springThumb(double target) {
    _thumb.animateWith(SpringSimulation(
      // Telegram: 0.65 s spring with damping 80 on press, 120 on release.
      SpringDescription.withDampingRatio(
          mass: 1, stiffness: 600, ratio: target > 0 ? 0.6 : 0.9),
      _thumb.value,
      target,
      0,
    ));
  }

  Duration _valueAt(double dx, double width) {
    final int total = widget.duration.inMilliseconds;
    final double delta = (dx - _anchorX) / width * total * _multiplier;
    final int ms =
        (_anchorValue.inMilliseconds + delta).round().clamp(0, total);
    return Duration(milliseconds: ms);
  }

  void _start(Offset local, double width) {
    if (widget.duration <= Duration.zero) {
      return;
    }
    // A press that turns into a drag starts twice: tap-down, then drag.
    if (!_scrubbing) {
      widget.onScrubStart?.call();
      _springThumb(1);
      HapticFeedback.selectionClick();
    }
    _scrubbing = true;
    _multiplier = 1;
    _startY = local.dy;
    // Grabbing anywhere on the bar jumps there first, like a tap would.
    _anchorX = local.dx;
    _anchorValue = Duration(
        milliseconds:
            (local.dx / width * widget.duration.inMilliseconds).round());
    _scrubValue = _valueAt(local.dx, width);
    setState(() {});
  }

  void _update(Offset local, double width) {
    if (!_scrubbing) {
      return;
    }
    final double multiplier = ScrubSpeed.multiplierFor(local.dy - _startY);
    if (multiplier != _multiplier) {
      // Re-anchor at the current value so changing speed never jumps.
      _anchorValue = _scrubValue;
      _anchorX = local.dx;
      _multiplier = multiplier;
      HapticFeedback.lightImpact();
    }
    setState(() => _scrubValue = _valueAt(local.dx, width));
  }

  void _end({required bool commit}) {
    if (!_scrubbing) {
      return;
    }
    _scrubbing = false;
    _springThumb(0);
    if (commit) {
      _heldValue = _scrubValue;
      _holdUntil = DateTime.now().add(const Duration(seconds: 1));
      widget.onSeek(_scrubValue);
    }
    widget.onScrubEnd?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _start(d.localPosition, width),
        onHorizontalDragUpdate: (d) => _update(d.localPosition, width),
        onHorizontalDragEnd: (_) => _end(commit: true),
        onHorizontalDragCancel: () => _end(commit: false),
        onTapDown: (d) => _start(d.localPosition, width),
        onTapUp: (_) => _end(commit: true),
        onTapCancel: () {
          // A tap that turns into a drag is cancelled here and carried on
          // by the drag callbacks.
        },
        child: SizedBox(
          height: _hitHeight,
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _fractionOf(widget.buffered)),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut,
                  builder: (context, buffered, _) {
                    return CustomPaint(
                      painter: _ScrubberPainter(
                        played: _playedFraction,
                        thumb: _thumb,
                        buffered: buffered,
                        color: widget.color,
                        trackHeight: _trackHeight,
                        thumbRadius: _thumbRadius,
                      ),
                    );
                  },
                ),
              ),
              if (_scrubbing) _bubble(width),
            ],
          ),
        ),
      );
    });
  }

  Widget _bubble(double width) {
    const double bubbleWidth = 120;
    final double x = _fractionOf(_scrubValue) * width;
    final double left =
        (x - bubbleWidth / 2).clamp(-10.0, width - bubbleWidth + 10);
    final String label = ScrubSpeed.labelFor(_multiplier);
    return Positioned(
      left: left,
      bottom: _hitHeight - 4,
      width: bubbleWidth,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                Utils.durationToString(_scrubValue),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.played,
    required this.thumb,
    required this.buffered,
    required this.color,
    required this.trackHeight,
    required this.thumbRadius,
  }) : super(repaint: Listenable.merge([played, thumb]));

  final ValueNotifier<double> played;
  final Animation<double> thumb;
  final double buffered;
  final Color color;
  final double trackHeight;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double cy = size.height / 2;
    final double grow = thumb.value.clamp(0.0, 1.5);
    // The track thickens a little while held.
    final double h = trackHeight + grow * 2;
    final Radius r = Radius.circular(h / 2);
    RRect bar(double fraction) => RRect.fromLTRBR(
        0, cy - h / 2, size.width * fraction.clamp(0.0, 1.0), cy + h / 2, r);

    canvas.drawRRect(bar(1), Paint()..color = Colors.white24);
    canvas.drawRRect(bar(buffered), Paint()..color = Colors.white38);
    canvas.drawRRect(bar(played.value), Paint()..color = color);

    // Telegram grows the thumb from 0.1875 to full size while it is held.
    final double radius = thumbRadius * (0.55 + 0.45 * grow);
    final Offset center = Offset(size.width * played.value, cy);
    if (grow > 0.01) {
      canvas.drawCircle(center, radius * 2.2,
          Paint()..color = color.withValues(alpha: 0.2 * grow.clamp(0.0, 1.0)));
    }
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.buffered != buffered || old.color != color;
}
