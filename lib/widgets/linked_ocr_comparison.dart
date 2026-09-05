import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/ocr_layout.dart';
import 'ocr_layout_view.dart';

/// Both panes use one normalized image-space camera. Pixel offsets are never
/// cached, so a resize/DPI change cannot desynchronize the image and the text.
class LinkedOcrComparison extends StatefulWidget {
  const LinkedOcrComparison({
    super.key,
    required this.preview,
    required this.imageWidth,
    required this.imageHeight,
    required this.blocks,
    required this.referenceBlocks,
    required this.leftTitle,
    this.onEdit,
  });

  final Uint8List preview;
  final int imageWidth, imageHeight;
  final List<OcrBlock> blocks, referenceBlocks;
  final String leftTitle;
  final ValueChanged<int>? onEdit;

  @override
  State<LinkedOcrComparison> createState() => _LinkedOcrComparisonState();
}

class _LinkedOcrComparisonState extends State<LinkedOcrComparison> {
  double _zoom = 1;
  Offset _offset = Offset.zero;
  double _gestureZoom = 1;
  Offset _anchor = Offset.zero;

  @override
  void didUpdateWidget(LinkedOcrComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Streaming/editing text retains the camera; a new screenshot resets both.
    if (!identical(oldWidget.preview, widget.preview) ||
        oldWidget.imageWidth != widget.imageWidth ||
        oldWidget.imageHeight != widget.imageHeight) {
      _zoom = 1;
      _offset = Offset.zero;
    }
  }

  Offset _normalized(Offset point, Size size) =>
      Offset(point.dx / size.width, point.dy / size.height);

  void _setCamera(double zoom, Offset offset) {
    setState(() {
      _zoom = zoom.clamp(1.0, 5.0);
      _offset = Offset(
        offset.dx.clamp(1 - _zoom, 0.0),
        offset.dy.clamp(1 - _zoom, 0.0),
      );
    });
  }

  void _reset() => _setCamera(1, Offset.zero);

  Widget _viewport(String name, Size size, Widget child) => Listener(
    onPointerSignal: (event) {
      if (event is! PointerScrollEvent) return;
      // Claim the wheel here so the surrounding page does not also scroll.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final focal = _normalized(event.localPosition, size);
        final anchor = (focal - _offset) / _zoom;
        final zoom = (_zoom * math.exp(-event.scrollDelta.dy * .002)).clamp(
          1.0,
          5.0,
        );
        _setCamera(zoom, focal - anchor * zoom);
      });
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _gestureZoom = _zoom;
        _anchor =
            (_normalized(details.localFocalPoint, size) - _offset) / _zoom;
      },
      onScaleUpdate: (details) {
        final zoom = (_gestureZoom * details.scale).clamp(1.0, 5.0);
        _setCamera(
          zoom,
          _normalized(details.localFocalPoint, size) - _anchor * zoom,
        );
      },
      child: ClipRect(
        key: ValueKey('$name-viewport'),
        child: SizedBox.fromSize(
          size: size,
          child: Transform(
            key: ValueKey('$name-camera'),
            alignment: Alignment.topLeft,
            transform: Matrix4.identity()
              ..translateByDouble(
                _offset.dx * size.width,
                _offset.dy * size.height,
                0,
                1,
              )
              ..scaleByDouble(_zoom, _zoom, 1, 1),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('同步缩放 ${(_zoom * 100).round()}% · 滚轮缩放 / 拖动平移'),
          TextButton(onPressed: _reset, child: const Text('复位视图')),
        ],
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, (constraints.maxWidth - 16) / 2);
          final size = Size(
            width,
            width * widget.imageHeight / widget.imageWidth,
          );
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.leftTitle, textAlign: TextAlign.center),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text('原始截图', textAlign: TextAlign.center),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _viewport(
                          'text',
                          size,
                          ColoredBox(
                            color: Colors.white,
                            child: OcrLayoutView(
                              blocks: widget.blocks,
                              referenceBlocks: widget.referenceBlocks,
                              imageWidth: widget.imageWidth,
                              imageHeight: widget.imageHeight,
                              interactive: false,
                              onEdit: widget.onEdit,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        _viewport(
                          'image',
                          size,
                          Image.memory(
                            widget.preview,
                            width: size.width,
                            height: size.height,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}
