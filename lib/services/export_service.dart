import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/app_models.dart';

class ExportService {
  const ExportService();

  Uint8List applyBackground(Uint8List cutoutBytes, RgbColor color) {
    final cutout = img.decodeImage(cutoutBytes);
    if (cutout == null) {
      throw const FormatException('无法读取抠像结果。');
    }
    final canvas = img.Image(
      width: cutout.width,
      height: cutout.height,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(color.red, color.green, color.blue));
    img.compositeImage(canvas, cutout);
    return Uint8List.fromList(img.encodePng(canvas, level: 6));
  }

  ExportResult render(Uint8List sourceBytes, ExportSettings settings) {
    if (settings.width < 1 || settings.height < 1) {
      throw const FormatException('分辨率必须大于 0。');
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const FormatException('无法读取处理后的图像。');
    }

    final source = img.bakeOrientation(decoded);
    final canvas = img.Image(
      width: settings.width,
      height: settings.height,
      numChannels: 3,
    );
    final background = settings.backgroundColor;
    img.fill(
      canvas,
      color: img.ColorRgb8(background.red, background.green, background.blue),
    );

    final scale = settings.resizeMode == ResizeMode.cover
        ? _max(settings.width / source.width, settings.height / source.height)
        : _min(settings.width / source.width, settings.height / source.height);
    final scaledWidth = (source.width * scale).round().clamp(1, 20000);
    final scaledHeight = (source.height * scale).round().clamp(1, 20000);
    final resized = img.copyResize(
      source,
      width: scaledWidth,
      height: scaledHeight,
      interpolation: img.Interpolation.cubic,
    );
    final x = ((settings.width - scaledWidth) / 2).round();
    final y = ((settings.height - scaledHeight) / 2).round();
    img.compositeImage(canvas, resized, dstX: x, dstY: y);

    if (settings.format == OutputFormat.png) {
      return ExportResult(
        bytes: Uint8List.fromList(img.encodePng(canvas, level: 9)),
        width: settings.width,
        height: settings.height,
        quality: null,
      );
    }

    final targetBytes = settings.targetKilobytes * 1024;
    if (targetBytes <= 0) {
      const quality = 92;
      return ExportResult(
        bytes: Uint8List.fromList(img.encodeJpg(canvas, quality: quality)),
        width: settings.width,
        height: settings.height,
        quality: quality,
      );
    }

    Uint8List? best;
    int? bestQuality;
    var low = 5;
    var high = 98;
    while (low <= high) {
      final quality = (low + high) ~/ 2;
      final encoded = Uint8List.fromList(
        img.encodeJpg(canvas, quality: quality),
      );
      if (encoded.length <= targetBytes) {
        best = encoded;
        bestQuality = quality;
        low = quality + 1;
      } else {
        high = quality - 1;
      }
    }

    if (best == null) {
      throw FormatException(
        '在 ${settings.width}×${settings.height} 分辨率下无法压缩到 '
        '${settings.targetKilobytes} KB，请增大目标体积。',
      );
    }

    return ExportResult(
      bytes: best,
      width: settings.width,
      height: settings.height,
      quality: bestQuality,
    );
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;
}
