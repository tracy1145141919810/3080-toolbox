import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'screen_capture_service.dart';

class QrDecodedContent {
  const QrDecodedContent({
    required this.text,
    required this.format,
    required this.isInverted,
    required this.isMirrored,
  });

  final String text;
  final String format;
  final bool isInverted;
  final bool isMirrored;

  Uri? get webUri {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  String get contentType {
    final value = text.trimLeft().toUpperCase();
    if (webUri != null) return '网页链接';
    if (value.startsWith('WIFI:')) return 'Wi-Fi 配置';
    if (value.startsWith('BEGIN:VCARD')) return '联系人';
    if (value.startsWith('MAILTO:')) return '电子邮件';
    if (value.startsWith('TEL:')) return '电话号码';
    return '文本内容';
  }
}

class QrScanPayload {
  const QrScanPayload({
    required this.sourceLabel,
    required this.previewPng,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.results,
  });

  final String sourceLabel;
  final Uint8List previewPng;
  final int width;
  final int height;
  final int durationMs;
  final List<QrDecodedContent> results;
}

class QrScannerService {
  const QrScannerService({
    this.screenCaptureService = const ScreenCaptureService(),
  });

  final ScreenCaptureService screenCaptureService;

  Future<QrScanPayload> scanFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('无法读取这张图片，请选择常见图片格式');
    }
    final decoded = await zxing.zx.readBarcodesImagePathString(
      path,
      _decodeParams(),
    );
    return QrScanPayload(
      sourceLabel: p.basename(path),
      previewPng: _previewPng(image),
      width: image.width,
      height: image.height,
      durationMs: decoded.duration,
      results: _validResults(decoded),
    );
  }

  Future<QrScanPayload?> scanScreen() async {
    await screenCaptureService.setToolboxVisible(false);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      final region = await screenCaptureService.selectRegion(
        instruction: '拖动鼠标框选二维码区域 · Esc 或右键取消',
      );
      if (region == null) return null;
      final longestSide = math.max(region.width, region.height);
      final scale = longestSide > 3072 ? 3072 / longestSide : 1.0;
      final outputWidth = math.max(32, (region.width * scale).round());
      final outputHeight = math.max(32, (region.height * scale).round());
      final frame = await screenCaptureService.capture(
        region,
        outputWidth: outputWidth,
        outputHeight: outputHeight,
        includeCursor: false,
      );
      return scanFrame(frame, sourceLabel: '屏幕框选区域');
    } finally {
      await screenCaptureService.setToolboxVisible(true);
    }
  }

  QrScanPayload scanFrame(RawScreenFrame frame, {String sourceLabel = '屏幕图像'}) {
    final decoded = zxing.zx.readBarcodes(
      frame.bgraBytes,
      _decodeParams(
        imageFormat: zxing.ImageFormat.bgrx,
        width: frame.width,
        height: frame.height,
      ),
    );
    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.bgraBytes.buffer,
      bytesOffset: frame.bgraBytes.offsetInBytes,
      order: img.ChannelOrder.bgra,
    );
    return QrScanPayload(
      sourceLabel: sourceLabel,
      previewPng: _previewPng(image),
      width: frame.width,
      height: frame.height,
      durationMs: decoded.duration,
      results: _validResults(decoded),
    );
  }

  zxing.DecodeParams _decodeParams({
    int imageFormat = zxing.ImageFormat.rgb,
    int width = 0,
    int height = 0,
  }) => zxing.DecodeParams(
    imageFormat: imageFormat,
    format:
        zxing.Format.qrCode | zxing.Format.microQRCode | zxing.Format.rmqrCode,
    width: width,
    height: height,
    tryHarder: true,
    tryRotate: true,
    tryInverted: true,
    tryDownscale: true,
    maxNumberOfSymbols: 10,
    maxSize: 2048,
    isMultiScan: true,
  );

  List<QrDecodedContent> _validResults(zxing.Codes decoded) {
    final seen = <String>{};
    final results = <QrDecodedContent>[];
    for (final code in decoded.codes) {
      final text = code.text?.trim();
      if (!code.isValid || text == null || text.isEmpty) continue;
      final format = code.format?.name ?? 'QR Code';
      if (!seen.add('$format\u0000$text')) continue;
      results.add(
        QrDecodedContent(
          text: text,
          format: format,
          isInverted: code.isInverted,
          isMirrored: code.isMirrored,
        ),
      );
    }
    return List.unmodifiable(results);
  }

  Uint8List _previewPng(img.Image source) {
    final longestSide = math.max(source.width, source.height);
    final preview = longestSide > 1200
        ? img.copyResize(
            source,
            width: source.width >= source.height ? 1200 : null,
            height: source.height > source.width ? 1200 : null,
            interpolation: img.Interpolation.linear,
          )
        : source;
    return Uint8List.fromList(img.encodePng(preview, level: 3));
  }
}
