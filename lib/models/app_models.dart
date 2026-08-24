import 'dart:typed_data';

enum InferenceDevice {
  automatic('自动（优先 GPU）'),
  gpu('GPU（DirectML）'),
  cpu('CPU');

  const InferenceDevice(this.label);
  final String label;
}

enum OutputFormat {
  jpeg('JPEG', 'jpg'),
  png('PNG', 'png');

  const OutputFormat(this.label, this.extension);
  final String label;
  final String extension;
}

enum ResizeMode {
  cover('居中裁切'),
  contain('完整适配');

  const ResizeMode(this.label);
  final String label;
}

class RgbColor {
  const RgbColor(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;

  String get hex =>
      '#${red.toRadixString(16).padLeft(2, '0')}'
              '${green.toRadixString(16).padLeft(2, '0')}'
              '${blue.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  static const white = RgbColor(255, 255, 255);
}

class SizePreset {
  const SizePreset(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;

  static const values = <SizePreset>[
    SizePreset('自定义', 0, 0),
    SizePreset('一寸证件照', 295, 413),
    SizePreset('二寸证件照', 413, 579),
    SizePreset('护照照片', 354, 472),
    SizePreset('社保照片', 358, 441),
    SizePreset('高清头像', 1200, 1200),
  ];
}

class SegmentationResult {
  const SegmentationResult({
    required this.pngBytes,
    required this.width,
    required this.height,
    required this.personCount,
    required this.deviceLabel,
    required this.elapsed,
  });

  final Uint8List pngBytes;
  final int width;
  final int height;
  final int personCount;
  final String deviceLabel;
  final Duration elapsed;
}

class ExportSettings {
  const ExportSettings({
    required this.width,
    required this.height,
    required this.format,
    required this.resizeMode,
    required this.targetKilobytes,
  });

  final int width;
  final int height;
  final OutputFormat format;
  final ResizeMode resizeMode;
  final int targetKilobytes;
}

class ExportResult {
  const ExportResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int? quality;

  int get byteLength => bytes.length;
}
