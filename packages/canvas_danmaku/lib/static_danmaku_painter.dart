import 'package:canvas_danmaku/base_danmaku_painter.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/models/danmaku_item.dart';
import 'package:canvas_danmaku/models/danmaku_option.dart';
import 'package:flutter/material.dart';

final class StaticDanmakuPainter extends CustomPainter {
  final int length;
  final List<DanmakuItem> danmakuItems;
  final double staticDurationInMilliseconds;
  final DanmakuOption option;
  final double devicePixelRatio;
  final int tick;

  StaticDanmakuPainter({
    required this.length,
    required this.danmakuItems,
    required this.staticDurationInMilliseconds,
    required this.option,
    required this.devicePixelRatio,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var item in danmakuItems) {
      item
        ..drawTick ??= tick
        ..drawParagraphIfNeeded(option, devicePixelRatio)
        ..xPosition = (size.width - item.width) / 2;

      BaseDanmakuPainter.paintImg(
        canvas,
        item,
        item.xPosition,
        item.content.type == DanmakuItemType.bottom
            ? size.height - item.yPosition - item.height
            : item.yPosition,
        devicePixelRatio,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaticDanmakuPainter oldDelegate) =>
      oldDelegate.length != length ||
      !identical(oldDelegate.option, option) ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
