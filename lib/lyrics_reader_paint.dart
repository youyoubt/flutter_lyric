import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyric_helper.dart';
import 'package:flutter_lyric/lyric_ui/lyric_ui.dart';
import 'package:flutter_lyric/lyrics_log.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';

///draw lyric reader
class LyricsReaderPaint extends ChangeNotifier implements CustomPainter {
  LyricsReaderModel? model;

  LyricUI lyricUI;

  LyricsReaderPaint(this.model, this.lyricUI);

  ///高亮混合笔
  var lightBlendPaint = Paint()
    ..blendMode = BlendMode.srcIn
    ..isAntiAlias = true;

  var playingIndex = 0;

  double _lyricOffset = 0;

  set lyricOffset(double offset) {
    if (checkOffset(offset)) {
      _lyricOffset = offset;
      refresh();
    }
  }

  double totalHeight = 0;

  var cachePlayingIndex = -1;

  clearCache() {
    cachePlayingIndex = -1;
    highlightWidth = 0;
  }

  ///check offset illegal
  ///true is OK
  ///false is illegal
  bool checkOffset(double? offset) {
    if (offset == null) return false;

    calculateTotalHeight();

    if (offset >= maxOffset && offset <= 0) {
      return true;
    } else {
      if (offset <= maxOffset && offset > _lyricOffset) {
        return true;
      }
    }
    LyricsLog.logD("越界取消偏移 可偏移：$maxOffset 目标偏移：$offset 当前：$_lyricOffset ");
    return false;
  }

  ///calculateTotalHeight
  void calculateTotalHeight() {
    ///缓存下，避免多余计算
    if (cachePlayingIndex != playingIndex) {
      cachePlayingIndex = playingIndex;
      var lyrics = model?.lyrics ?? [];
      double lastLineSpace = 0;
      //最大偏移量不包含最后一行
      if (lyrics.isNotEmpty) {
        lyrics = lyrics.sublist(0, lyrics.length - 1);
        lastLineSpace = LyricHelper.getLineSpaceHeight(lyrics.last, lyricUI,
            excludeInline: true);
      }
      totalHeight = -LyricHelper.getTotalHeight(lyrics, playingIndex, lyricUI) +
          (model?.firstCenterOffset(playingIndex, lyricUI) ?? 0) -
          (model?.lastCenterOffset(playingIndex, lyricUI) ?? 0) -
          lastLineSpace;
    }
  }

  double get baseOffset => lyricUI.halfSizeLimit()
      ? mSize.height * (0.5 - lyricUI.getPlayingLineBias())
      : 0;

  double get maxOffset {
    calculateTotalHeight();
    return baseOffset + totalHeight;
  }

  double get lyricOffset => _lyricOffset;

  //限制刷新频率
  int ts = DateTime.now().microsecond;

  refresh() {
    notifyListeners();
  }

  var _centerLyricIndex = 0;

  set centerLyricIndex(int value) {
    _centerLyricIndex = value;
    centerLyricIndexChangeCall?.call(value);
  }

  int get centerLyricIndex => _centerLyricIndex;

  Function(int)? centerLyricIndexChangeCall;

  Size mSize = Size.zero;

  ///给外部C位位置
  var centerY = 0.0;

  @override
  bool? hitTest(Offset position) => null;

  @override
  void paint(Canvas canvas, Size size) {
    //全局尺寸信息
    mSize = size;
    //溢出裁剪
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));
    centerY = size.height * lyricUI.getPlayingLineBias();
    var drawOffset = centerY + _lyricOffset;
    var lyrics = model?.lyrics ?? [];
    drawOffset -= model?.firstCenterOffset(playingIndex, lyricUI) ?? 0;
    for (var i = 0; i < lyrics.length; i++) {
      var element = lyrics[i];
      var lineHeight = drawLine(i, drawOffset, canvas, element);
      var nextOffset = drawOffset + lineHeight;
      if (centerY > drawOffset && centerY < nextOffset) {
        if (i != centerLyricIndex) {
          centerLyricIndex = i;
          LyricsLog.logD(
              "drawOffset:$drawOffset next:$nextOffset center:$centerY  当前行是：$i 文本：${element.mainText} ");
        }
      }
      drawOffset = nextOffset;
    }
  }

  double drawLine(
      int i, double drawOffset, Canvas canvas, LyricsLineModel element) {
    //空行直接返回
    if (!element.hasMain && !element.hasExt) {
      return lyricUI.getBlankLineHeight();
    }
    return _drawOtherLyricLine(canvas, drawOffset, element, i);
  }

  ///绘制其他歌词行
  ///返回造成的偏移量值
  double _drawOtherLyricLine(Canvas canvas, double drawOffsetY,
      LyricsLineModel element, int lineIndex) {
    var isPlay = lineIndex == playingIndex;
    var mainTextPainter = (isPlay
        ? element.drawInfo?.playingMainTextPainter
        : element.drawInfo?.otherMainTextPainter);
    var extTextPainter = (isPlay
        ? element.drawInfo?.playingExtTextPainter
        : element.drawInfo?.otherExtTextPainter);
    //该行行高
    double otherLineHeight = 0;
    //第一行不加行间距
    if (lineIndex != 0) {
      otherLineHeight += lyricUI.getLineSpace();
    }
    var nextOffsetY = drawOffsetY + otherLineHeight;
    if (element.hasMain) {
      if (isPlay) {
        drawRemark(element, canvas, mainTextPainter, nextOffsetY);
      }
      otherLineHeight += drawText(
          canvas, mainTextPainter, nextOffsetY, isPlay ? element : null);
    }
    if (element.hasExt) {
      //有主歌词时才加内间距
      if (element.hasMain) {
        otherLineHeight += lyricUI.getInlineSpace();
      }
      var extOffsetY = drawOffsetY + otherLineHeight;
      otherLineHeight += drawText(canvas, extTextPainter, extOffsetY);
    }
    return otherLineHeight;
  }

  Paint imagePaint = Paint();
  List<Rect> remarkPoints = [];

  /// 绘制上半部分标注
  void drawRemark(LyricsLineModel model, Canvas canvas,
      TextPainter? mainTextPainter, double nextOffsetY) {
    String text = mainTextPainter?.plainText ?? "哈";
    double allLength = mainTextPainter?.width ?? 1; //总长度
    int textLength = text.length;
    if (textLength == 0) {
      textLength = 1;
    }
    //大约每个字的长度
    double perSize = allLength / textLength;
    //计算左侧的距离
    double mainLineOffset = getLineOffsetX(mainTextPainter!,isPlay: true);
    //每个字的高度
    double heightOffset = mainTextPainter.height;

    //清空高亮部分
    remarkPoints.clear();

    // 绘制上边标注文字
    model.drawInfo?.topRemarkPainter.forEach((key, value) {
      drawRemarkText(canvas, key, perSize, mainLineOffset, nextOffsetY, value,
          heightOffset, true);
    });
    double imageSize = lyricUI.getRemarkImageSize();
    //绘制上边标注图片
    model.drawInfo?.topRemarkImages.forEach((index, image) {
      drawRemarkImage(canvas, image, index, perSize, mainLineOffset,
          nextOffsetY, imageSize, heightOffset, true);
    });
    // 绘制下边标注文字
    model.drawInfo?.bottomRemarkPainter.forEach((key, value) {
      drawRemarkText(canvas, key, perSize, mainLineOffset, nextOffsetY, value,
          heightOffset, false);
    });
    //绘制下边标注图片
    model.drawInfo?.bottomRemarkImages.forEach((index, image) {
      drawRemarkImage(canvas, image, index, perSize, mainLineOffset,
          nextOffsetY, imageSize, heightOffset, false);
    });
  }

  /// 绘制文本标注
  void drawRemarkText(
      Canvas canvas,
      int index,
      double perSize,
      double mainLineOffset,
      double nextOffsetY,
      TextPainter painter,
      double heightOffset,
      bool isTop) {
    double textOffset = index * perSize;
    double offsetY =
        isTop ? (nextOffsetY - painter.height) : (nextOffsetY + heightOffset);
    Offset offset = Offset(mainLineOffset + textOffset, offsetY);
    //背景
    canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, painter.width, painter.height),
        lightBlendPaint
          ..color = lyricUI.getRemarkTextBgColor()
          ..strokeCap = StrokeCap.round);
    painter.paint(canvas, offset);
    //底部高亮
    offset = Offset(mainLineOffset + textOffset, nextOffsetY);
    remarkPoints
        .add(Rect.fromLTWH(offset.dx, offset.dy, perSize, heightOffset));
  }

  /// 绘制图片标注
  void drawRemarkImage(
      Canvas canvas,
      image,
      int index,
      double perSize,
      double mainLineOffset,
      double nextOffsetY,
      double imageSize,
      double heightOffset,
      bool isTop) {
    //左边偏移
    double textOffset = index * perSize;
    //Y轴偏移
    double offsetY =
        isTop ? (nextOffsetY - imageSize) : (nextOffsetY + heightOffset);
    Offset offset = Offset(mainLineOffset + textOffset, offsetY);
    Rect src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    double width = image.width * imageSize / image.height;
    //居中显示
    double dx = (perSize - width) / 2 + offset.dx;
    Rect dst = Rect.fromLTWH(dx, offset.dy, width, imageSize);
    canvas.drawImageRect(image, src, dst, imagePaint..isAntiAlias = true);

    //底部高亮
    offset = Offset(mainLineOffset + textOffset, nextOffsetY);
    remarkPoints
        .add(Rect.fromLTWH(offset.dx, offset.dy, perSize, heightOffset));
  }

  /// 标注 文字需要高亮部分
  void drawRemarkHighlight(Canvas canvas) {
    //绘制高亮
    remarkPoints.forEach((element) {
      canvas.drawRect(element, lightBlendPaint..color = lyricUI.getRemarkHightLightColor());
    });
  }

  void drawHighlight(LyricsLineModel model, Canvas canvas, TextPainter? painter,
      Offset offset) {
    if (!model.hasMain) return;
    var tmpHighlightWidth = _highlightWidth;
    model.drawInfo?.inlineDrawList.forEach((element) {
      if (tmpHighlightWidth < 0) {
        return;
      }
      var currentWidth = 0.0;
      if (tmpHighlightWidth >= element.width) {
        currentWidth = element.width;
      } else {
        currentWidth = element.width - (element.width - tmpHighlightWidth);
      }
      tmpHighlightWidth -= currentWidth;
      var dx = offset.dx + element.offset.dx;
      if (lyricUI.getHighlightDirection() == HighlightDirection.RTL) {
        dx += element.width;
        dx -= currentWidth;
      }
      canvas.drawRect(
          Rect.fromLTWH(dx, offset.dy + element.offset.dy - 2, currentWidth,
              element.height + 2),
          lightBlendPaint..color = lyricUI.getLyricHightlightColor());
    });
  }

  var _highlightWidth = 0.0;

  set highlightWidth(double value) {
    _highlightWidth = value;
    refresh();
  }

  double get highlightWidth => _highlightWidth;

  Paint layerPaint = Paint();

  ///绘制文本并返回行高度
  ///when [element] not null,then draw gradient
  double drawText(Canvas canvas, TextPainter? paint, double offsetY,
      [LyricsLineModel? element]) {
    //paint 理论上不可能为空，预期报错
    var lineHeight = paint!.height;
    if (offsetY < 0 - lineHeight || offsetY > mSize.height) {
      return lineHeight;
    }
    var isEnableLight = element != null && lyricUI.enableHighlight();
    var offset = Offset(getLineOffsetX(paint,isPlay: element != null), offsetY);
    if (isEnableLight) {
      canvas.saveLayer(
          Rect.fromLTWH(0, 0, mSize.width, mSize.height), layerPaint);
    }

    paint.paint(canvas, offset);
    if (isEnableLight) {
      drawRemarkHighlight(canvas);
      drawHighlight(element!, canvas, paint, offset);
      canvas.restore();
    }
    return lineHeight;
  }

  ///获取行绘制横向坐标
  double getLineOffsetX(TextPainter textPainter,{bool isPlay = false}) {
    switch (lyricUI.getLyricHorizontalAlign()) {
      case LyricAlign.LEFT:
        return 0;
      case LyricAlign.CENTER:
        if (!isPlay || !lyricUI.isPlayingLineOffset()) {
          return (mSize.width - textPainter.width) / 2;
        }
        return (mSize.width - textPainter.width) / 2 - textPainter.width / 2;
      case LyricAlign.RIGHT:
        return mSize.width - textPainter.width;
      default:
        return (mSize.width - textPainter.width) / 2;
    }
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder => null;

  @override
  bool shouldRebuildSemantics(covariant CustomPainter oldDelegate) {
    return shouldRepaint(oldDelegate);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
