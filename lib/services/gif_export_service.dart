import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'screen_capture_service.dart';

class RecordedScreenFrame {
  const RecordedScreenFrame({
    required this.width,
    required this.height,
    required this.jpegBytes,
  });

  final int width;
  final int height;
  final Uint8List jpegBytes;

  Map<String, Object> toMessage() => <String, Object>{
    'width': width,
    'height': height,
    'encoded': jpegBytes,
  };
}

class GifExportSettings {
  const GifExportSettings({
    required this.framesPerSecond,
    required this.colors,
    required this.scalePercent,
    this.targetKilobytes = 0,
  });

  final int framesPerSecond;
  final int colors;
  final int scalePercent;
  final int targetKilobytes;
}

class GifExportResult {
  const GifExportResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.colors,
    required this.metTarget,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int colors;
  final bool metTarget;
}

class GifExportService {
  const GifExportService();

  Future<RecordedScreenFrame> compressFrame(RawScreenFrame frame) async {
    final result = await compute(_compressFrame, frame.toMessage());
    return RecordedScreenFrame(
      width: result['width']! as int,
      height: result['height']! as int,
      jpegBytes: result['encoded']! as Uint8List,
    );
  }

  Future<Uint8List> createPreview(RecordedScreenFrame frame) =>
      compute(_createPreview, frame.toMessage());

  Future<List<Uint8List>> createThumbnails(List<RecordedScreenFrame> frames) =>
      compute(
        _createThumbnails,
        frames.map((frame) => frame.toMessage()).toList(),
      );

  Future<GifExportResult> encode(
    List<RecordedScreenFrame> frames,
    GifExportSettings settings,
  ) async {
    if (frames.isEmpty) throw StateError('没有可导出的帧');
    final message = <String, Object>{
      'frames': frames.map((frame) => frame.toMessage()).toList(),
      'fps': settings.framesPerSecond,
      'colors': settings.colors,
      'scale': settings.scalePercent,
      'targetKB': settings.targetKilobytes,
    };
    final result = await compute(_encodeGif, message);
    return GifExportResult(
      bytes: result['bytes']! as Uint8List,
      width: result['width']! as int,
      height: result['height']! as int,
      colors: result['colors']! as int,
      metTarget: result['metTarget']! as bool,
    );
  }
}

img.Image _decodeFrame(Map<Object?, Object?> frame) {
  final encoded = frame['encoded']! as Uint8List;
  final decoded = img.decodeImage(encoded);
  if (decoded == null) throw const FormatException('录制帧解码失败');
  return decoded;
}

Map<String, Object> _compressFrame(Map<String, Object> message) {
  final width = message['width']! as int;
  final height = message['height']! as int;
  final pixels = message['pixels']! as Uint8List;
  final source = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    order: img.ChannelOrder.bgra,
  );
  return <String, Object>{
    'width': width,
    'height': height,
    'encoded': Uint8List.fromList(img.encodeJpg(source, quality: 82)),
  };
}

Uint8List _createPreview(Map<String, Object> message) {
  final source = _decodeFrame(message);
  final preview = source.width > 1100
      ? img.copyResize(
          source,
          width: 1100,
          interpolation: img.Interpolation.linear,
        )
      : source;
  return Uint8List.fromList(img.encodePng(preview, level: 3));
}

List<Uint8List> _createThumbnails(List<Map<String, Object>> messages) {
  return messages.map((message) {
    final source = _decodeFrame(message);
    final thumb = img.copyResize(
      source,
      width: 128,
      interpolation: img.Interpolation.linear,
    );
    return Uint8List.fromList(img.encodeJpg(thumb, quality: 68));
  }).toList();
}

Map<String, Object> _encodeGif(Map<String, Object> message) {
  final frameMessages = (message['frames']! as List)
      .cast<Map<Object?, Object?>>();
  final first = _decodeFrame(frameMessages.first);
  final fps = message['fps']! as int;
  final requestedColors = message['colors']! as int;
  final requestedScale = message['scale']! as int;
  final targetBytes = (message['targetKB']! as int) * 1024;

  var scale = requestedScale.clamp(20, 100);
  var colors = requestedColors.clamp(16, 256);
  Uint8List? best;
  var bestWidth = 0;
  var bestHeight = 0;

  for (var attempt = 0; attempt < 12; attempt++) {
    final width = (first.width * scale / 100).round().clamp(1, 4096);
    final height = (first.height * scale / 100).round().clamp(1, 4096);
    final encoder = img.GifEncoder(
      repeat: 0,
      numColors: colors,
      quantizerType: img.QuantizerType.octree,
    );
    final duration = (100 / fps).round().clamp(1, 100);
    for (final frameMessage in frameMessages) {
      final source = _decodeFrame(frameMessage);
      final frame = width == source.width && height == source.height
          ? source
          : img.copyResize(
              source,
              width: width,
              height: height,
              interpolation: img.Interpolation.linear,
            );
      encoder.addFrame(frame, duration: duration);
    }
    final encoded = encoder.finish();
    if (encoded == null) throw StateError('GIF 编码失败');
    best = Uint8List.fromList(encoded);
    bestWidth = width;
    bestHeight = height;
    if (targetBytes <= 0 || best.length <= targetBytes) break;
    if (colors > 32) {
      colors = (colors ~/ 2).clamp(32, 256);
    } else if (scale > 20) {
      scale = (scale * 0.84).round().clamp(20, 100);
    } else {
      break;
    }
  }

  return <String, Object>{
    'bytes': best!,
    'width': bestWidth,
    'height': bestHeight,
    'colors': colors,
    'metTarget': targetBytes <= 0 || best.length <= targetBytes,
  };
}
