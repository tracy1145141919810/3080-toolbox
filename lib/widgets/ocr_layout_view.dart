import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ocr_layout.dart';

const translationTextStyle = TextStyle(
  inherit: false,
  fontFamily: 'ToolboxCJK',
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.normal,
  color: Color(0xFF182230),
  height: 1.2,
  letterSpacing: 0,
  wordSpacing: 0,
);

/// Text stays in source-image coordinates; resizing only scales the canvas.
class OcrLayoutView extends StatelessWidget {
  const OcrLayoutView({
    super.key,
    required this.blocks,
    required this.imageWidth,
    required this.imageHeight,
    this.onEdit,
    this.referenceBlocks,
    this.transformationController,
    this.interactive = true,
  });
  final List<OcrBlock> blocks;
  final int imageWidth, imageHeight;
  final ValueChanged<int>? onEdit;
  final List<OcrBlock>? referenceBlocks;
  final TransformationController? transformationController;

  /// Embedded comparisons own both viewports and their shared transformation.
  final bool interactive;

  double _uniformFontSize() {
    final sizingBlocks = referenceBlocks ?? blocks;
    final heights =
        sizingBlocks
            .where((b) => b.text.isNotEmpty)
            .map((b) => b.height)
            .toList()
          ..sort();
    if (heights.isEmpty) return 24;
    var size = heights[heights.length ~/ 2] * .7;
    // Measure in original-image coordinates. Choose ONE size for the canvas,
    // not a different magnification for each name/character fallback font.
    for (final block in sizingBlocks) {
      if (block.text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: block.text,
          style: translationTextStyle.copyWith(fontSize: 100),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      size = math.min(size, 100 * block.width / math.max(1, painter.width));
      size = math.min(size, 100 * block.height / math.max(1, painter.height));
      painter.dispose();
    }
    return size * .97;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = interactive
          ? math.min(constraints.maxWidth / imageWidth, 480 / imageHeight)
          : constraints.maxWidth / imageWidth;
      final fontSize = _uniformFontSize() * scale;
      final canvas = SizedBox(
        width: imageWidth * scale,
        height: imageHeight * scale,
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var i = 0; i < blocks.length; i++)
                Positioned(
                  left: blocks[i].x * scale,
                  top: blocks[i].y * scale,
                  width: math.max(1, blocks[i].width * scale),
                  height: math.max(1, blocks[i].height * scale),
                  child: Tooltip(
                    message:
                        '${blocks[i].text}${blocks[i].confidence < .8 ? '\n低置信度，请核对原图' : ''}${onEdit == null ? '' : '\n点击校对'}',
                    child: InkWell(
                      onTap: onEdit == null ? null : () => onEdit!(i),
                      child: Container(
                        decoration: blocks[i].confidence < .8
                            ? const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.orange),
                                ),
                              )
                            : null,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            blocks[i].text,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            textScaler: TextScaler.noScaling,
                            style: translationTextStyle.copyWith(
                              fontSize: fontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      if (!interactive) return canvas;
      return InteractiveViewer(
        transformationController: transformationController,
        minScale: 1,
        maxScale: 5,
        child: canvas,
      );
    },
  );
}
