import 'dart:math';
import 'dart:ui' as ui;

import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/models/danmaku_option.dart';
import 'package:flutter/material.dart';

abstract final class DmUtils {
  static final Random random = Random();

  static const maxRasterizeSize = 8192.0;

  static String generateRandomString(int length) {
    const characters = '0123456789abcdefghijklmnopqrstuvwxyz';

    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => characters.codeUnitAt(random.nextInt(characters.length)),
      ),
    );
  }

  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.green;

  static void updateSelfSendPaint(double strokeWidth) {
    _selfSendPaint.strokeWidth = strokeWidth;
  }

  /// 深色弹幕使用浅色边框, 否则黑色描边会让文字糊成一团
  static bool _isDark(Color color) => color.computeLuminance() < 0.12;

  static Color outlineColorOf(Color color) =>
      _isDark(color) ? const Color(0xFFF2F2F2) : const Color(0xFF000000);

  /// 文字四周为边框样式预留的空间
  static EdgeInsets decorationInsets(DanmakuOption option, double fontSize) {
    final sw = option.strokeWidth;
    switch (option.borderStyle) {
      case DanmakuBorderStyle.none:
        return EdgeInsets.zero;
      case DanmakuBorderStyle.stroke:
        return EdgeInsets.all(sw / 2);
      case DanmakuBorderStyle.shadow:
        final d = _shadowOffset(sw);
        return EdgeInsets.fromLTRB(sw / 2, sw / 2, d + sw, d + sw);
      case DanmakuBorderStyle.glow:
        return EdgeInsets.all(sw * 2.5 + 1);
      case DanmakuBorderStyle.background:
        return EdgeInsets.symmetric(
          horizontal: fontSize * 0.3,
          vertical: fontSize * 0.06 + 1,
        );
    }
  }

  static double _shadowOffset(double strokeWidth) =>
      max(1.0, strokeWidth * 0.8);

  static List<Shadow>? _textShadows(Color color, DanmakuOption option) {
    final sw = option.strokeWidth;
    final outline = outlineColorOf(color);
    switch (option.borderStyle) {
      case DanmakuBorderStyle.shadow:
        final d = _shadowOffset(sw);
        return [
          Shadow(
            color: outline.withValues(alpha: 0.9),
            offset: Offset(d, d),
            blurRadius: sw * 0.6,
          ),
        ];
      case DanmakuBorderStyle.glow:
        // 叠加两层模糊阴影, 让光晕在亮色画面上也足够浓
        final shadow = Shadow(
          color: outline.withValues(alpha: 0.85),
          blurRadius: sw * 1.5 + 0.5,
        );
        return [shadow, shadow];
      default:
        return null;
    }
  }

  /// 弹幕图片的逻辑尺寸
  static Size danmakuSize(
    ui.Paragraph paragraph,
    DanmakuContentItem content,
    DanmakuOption option, {
    double? fontSize,
  }) {
    final insets = decorationInsets(option, fontSize ?? option.fontSize);
    return Size(
      paragraph.maxIntrinsicWidth +
          insets.horizontal +
          (content.selfSend ? 4.0 : 0.0),
      paragraph.height + insets.vertical,
    );
  }

  static ui.Paragraph generateParagraph({
    required DanmakuContentItem content,
    required DanmakuOption option,
    double? fontSize,
  }) {
    final size = fontSize ?? option.fontSize;
    final fontFamily = option.fontFamily;
    final shadows = _textShadows(content.color, option);
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[option.fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
      fontFamily: fontFamily,
    ));

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          color: content.color,
          fontSize: size * 0.6,
          fontFamily: fontFamily,
          shadows: shadows,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(
        color: content.color,
        fontSize: size,
        fontFamily: fontFamily,
        shadows: shadows,
      ))
      ..addText(content.text);

    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static ui.Image recordDanmakuImage({
    required ui.Paragraph contentParagraph,
    required DanmakuContentItem content,
    required DanmakuOption option,
    required double devicePixelRatio,
  }) {
    final fontSize = option.fontSize;
    final fontFamily = option.fontFamily;
    final strokeWidth = option.strokeWidth;
    final insets = decorationInsets(option, fontSize);
    final size = danmakuSize(contentParagraph, content, option);
    double w = size.width;
    final double h = size.height;

    final offset = Offset(
      insets.left + (content.selfSend ? 2.0 : 0.0),
      insets.top,
    );

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..scale(devicePixelRatio);

    if (option.borderStyle == DanmakuBorderStyle.background) {
      final dark = _isDark(content.color);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          Radius.circular(h * 0.3),
        ),
        Paint()
          ..color = dark ? const Color(0x99FFFFFF) : const Color(0x73000000),
      );
    }

    if (option.borderStyle == DanmakuBorderStyle.stroke && strokeWidth != 0) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontWeight: FontWeight.values[option.fontWeight],
        textDirection: TextDirection.ltr,
        maxLines: 1,
        fontFamily: fontFamily,
      ));
      final Paint strokePaint = Paint()
        ..shader = content.isColorful
            ? const LinearGradient(
                    colors: [Color(0xFFF2509E), Color(0xFF308BCD)])
                .createShader(Rect.fromLTWH(0, 0, w, h))
            : null
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth;

      if (!content.isColorful) {
        strokePaint.color = outlineColorOf(content.color);
      }

      if (content.count case final count?) {
        builder
          ..pushStyle(ui.TextStyle(
            fontSize: fontSize * 0.6,
            foreground: strokePaint,
            fontFamily: fontFamily,
          ))
          ..addText('($count)')
          ..pop();
      }

      builder
        ..pushStyle(ui.TextStyle(
            fontSize: fontSize,
            foreground: strokePaint,
            fontFamily: fontFamily))
        ..addText(content.text);

      final strokeParagraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));

      canvas.drawParagraph(strokeParagraph, offset);
      strokeParagraph.dispose();
    }

    canvas.drawParagraph(contentParagraph, offset);

    if (content.selfSend) {
      canvas.drawRect(Rect.fromLTRB(0, 0, w, h), _selfSendPaint);
    }

    final pic = rec.endRecording();
    final img = pic.toImageSync(
      (w * devicePixelRatio).ceil(),
      (h * devicePixelRatio).ceil(),
    );
    pic.dispose();
    return img;
  }

  static ui.Image recordSpecialDanmakuImg({
    required SpecialDanmakuContentItem content,
    required DanmakuOption option,
    required double devicePixelRatio,
  }) {
    final strokeWidth = option.strokeWidth;
    final fontFamily = option.fontFamily;
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[option.fontWeight],
      textDirection: TextDirection.ltr,
      fontSize: content.fontSize,
      fontFamily: fontFamily,
    ))
      ..pushStyle(ui.TextStyle(
        color: content.color,
        fontSize: content.fontSize,
        fontFamily: fontFamily,
        shadows: content.hasStroke
            ? [Shadow(color: Colors.black, blurRadius: strokeWidth)]
            : null,
      ))
      ..addText(content.text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final strokeOffset = strokeWidth / 2;
    final totalWidth = paragraph.maxIntrinsicWidth + strokeWidth;
    final totalHeight = paragraph.height + strokeWidth;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);

    final Rect rect;
    double adjustDevicePixelRatio = devicePixelRatio;

    if (content.rotateZ != 0 || content.matrix != null) {
      rect = _calculateRotatedBounds(
        totalWidth,
        totalHeight,
        content.rotateZ,
        content.matrix,
      );

      final imgLongestSide = rect.size.longestSide * devicePixelRatio;
      if (imgLongestSide > maxRasterizeSize) {
        // force resize
        adjustDevicePixelRatio = maxRasterizeSize / imgLongestSide;
      }
      canvas
        ..scale(adjustDevicePixelRatio)
        ..translate(strokeOffset - rect.left, strokeOffset - rect.top);

      if (content.matrix case final matrix?) {
        canvas.transform(matrix.storage);
      } else {
        canvas.rotate(content.rotateZ);
      }
      canvas.drawParagraph(paragraph, Offset.zero);
    } else {
      rect = Rect.fromLTRB(0, 0, totalWidth, totalHeight);

      final imgLongestSide = max(totalWidth, totalHeight) * devicePixelRatio;
      if (imgLongestSide > maxRasterizeSize) {
        final scale = maxRasterizeSize / imgLongestSide;
        adjustDevicePixelRatio = scale;
      }
      canvas
        ..scale(adjustDevicePixelRatio)
        ..drawParagraph(paragraph, Offset(strokeOffset, strokeOffset));
    }

    content.rect = rect;

    final imgSize = rect.size * adjustDevicePixelRatio;
    final pic = rec.endRecording();
    final img = pic.toImageSync(imgSize.width.ceil(), imgSize.height.ceil());
    pic.dispose();
    paragraph.dispose();

    return img;
  }

  static Rect _calculateRotatedBounds(
    double w,
    double h,
    double rotateZ,
    Matrix4? matrix,
  ) {
    final double cosZ;
    final double cosY;
    final double sinZ;
    if (matrix == null) {
      cosZ = cos(rotateZ);
      sinZ = sin(rotateZ);
      cosY = 1;
    } else {
      cosZ = matrix[5];
      sinZ = matrix[1];
      cosY = matrix[10];
    }

    final wx = w * cosZ * cosY;
    final wy = w * sinZ;
    final hx = -h * sinZ * cosY;
    final hy = h * cosZ;

    final minX = _min4(0.0, wx, hx, wx + hx);
    final maxX = _max4(0.0, wx, hx, wx + hx);
    final minY = _min4(0.0, wy, hy, wy + hy);
    final maxY = _max4(0.0, wy, hy, wy + hy);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @pragma("vm:prefer-inline")
  static double _min4(double a, double b, double c, double d) {
    final ab = a < b ? a : b;
    final cd = c < d ? c : d;
    return ab < cd ? ab : cd;
  }

  @pragma("vm:prefer-inline")
  static double _max4(double a, double b, double c, double d) {
    final ab = a > b ? a : b;
    final cd = c > d ? c : d;
    return ab > cd ? ab : cd;
  }
}
