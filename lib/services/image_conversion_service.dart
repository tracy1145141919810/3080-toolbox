import 'dart:io';

import 'package:path/path.dart' as p;

enum ImageOutputFormat {
  jpeg('JPEG', 'jpg', true, false),
  png('PNG', 'png', false, true),
  webp('WebP', 'webp', true, true),
  avif('AVIF', 'avif', true, true),
  jxl('JPEG XL', 'jxl', true, true),
  tiff('TIFF', 'tiff', false, true),
  bmp('BMP', 'bmp', false, true),
  gif('GIF', 'gif', false, true),
  ico('ICO', 'ico', false, true),
  exr('OpenEXR', 'exr', false, true);

  const ImageOutputFormat(
    this.label,
    this.extension,
    this.lossy,
    this.supportsAlpha,
  );

  final String label;
  final String extension;
  final bool lossy;
  final bool supportsAlpha;
}

class ImageConversionSettings {
  const ImageConversionSettings({
    required this.outputDirectory,
    required this.format,
    required this.quality,
    required this.width,
    required this.height,
    required this.keepAspectRatio,
    required this.keepMetadata,
    required this.overwrite,
    required this.targetKilobytes,
  });

  final String outputDirectory;
  final ImageOutputFormat format;
  final int quality;
  final int width;
  final int height;
  final bool keepAspectRatio;
  final bool keepMetadata;
  final bool overwrite;
  final int targetKilobytes;
}

class ImageConversionResult {
  const ImageConversionResult({
    required this.outputPath,
    required this.byteLength,
    required this.quality,
    required this.metTarget,
  });

  final String outputPath;
  final int byteLength;
  final int quality;
  final bool metTarget;
}

class ImageConversionService {
  ImageConversionService({this._runtimeDirectory});

  static const supportedInputExtensions = <String>{
    'jpg',
    'jpeg',
    'jpe',
    'png',
    'webp',
    'avif',
    'heic',
    'heif',
    'jxl',
    'tif',
    'tiff',
    'bmp',
    'dib',
    'gif',
    'ico',
    'cur',
    'tga',
    'exr',
    'hdr',
    'dpx',
    'psd',
    'psb',
    'jp2',
    'j2k',
    'j2c',
    'pnm',
    'ppm',
    'pgm',
    'pbm',
    'pcx',
    'dds',
    'xcf',
    'cr2',
    'cr3',
    'crw',
    'arw',
    'nef',
    'nrw',
    'raf',
    'rw2',
    'orf',
    'pef',
    'dng',
    'sr2',
    'srf',
    'x3f',
    '3fr',
    'erf',
    'mef',
    'mos',
    'kdc',
    'dcr',
    'mrw',
  };

  final String? _runtimeDirectory;

  String get runtimeDirectory {
    if (_runtimeDirectory != null) return _runtimeDirectory;
    final bundled = p.join(
      p.dirname(Platform.resolvedExecutable),
      'imagemagick',
    );
    if (File(p.join(bundled, 'magick.exe')).existsSync()) return bundled;
    return p.join(Directory.current.path, 'windows', 'runtime', 'imagemagick');
  }

  String get executablePath => p.join(runtimeDirectory, 'magick.exe');

  bool get isAvailable => File(executablePath).existsSync();

  Map<String, String> get _environment => <String, String>{
    ...Platform.environment,
    'MAGICK_HOME': runtimeDirectory,
    'MAGICK_CONFIGURE_PATH': runtimeDirectory,
  };

  Future<String> version() async {
    final result = await Process.run(
      executablePath,
      ['-version'],
      environment: _environment,
      workingDirectory: runtimeDirectory,
    );
    if (result.exitCode != 0) {
      throw StateError(_errorText(result));
    }
    return (result.stdout as String).split(RegExp(r'[\r\n]')).first.trim();
  }

  Future<ImageConversionResult> convert(
    String inputPath,
    ImageConversionSettings settings,
  ) async {
    if (!isAvailable) throw StateError('未找到随应用提供的 ImageMagick 运行库');
    await Directory(settings.outputDirectory).create(recursive: true);
    final outputPath = _resolveOutputPath(inputPath, settings);
    var quality = settings.quality.clamp(1, 100);
    var result = await _runConversion(inputPath, outputPath, settings, quality);
    if (result.exitCode != 0) {
      throw FormatException(_errorText(result));
    }

    var length = await File(outputPath).length();
    final targetBytes = settings.targetKilobytes * 1024;
    if (targetBytes > 0 && settings.format.lossy) {
      while (length > targetBytes && quality > 20) {
        quality = (quality - 10).clamp(20, 100);
        result = await _runConversion(inputPath, outputPath, settings, quality);
        if (result.exitCode != 0) {
          throw FormatException(_errorText(result));
        }
        length = await File(outputPath).length();
      }
    }
    return ImageConversionResult(
      outputPath: outputPath,
      byteLength: length,
      quality: quality,
      metTarget: targetBytes <= 0 || length <= targetBytes,
    );
  }

  Future<ProcessResult> _runConversion(
    String inputPath,
    String outputPath,
    ImageConversionSettings settings,
    int quality,
  ) {
    final staticOutput = !{
      ImageOutputFormat.gif,
      ImageOutputFormat.webp,
      ImageOutputFormat.avif,
    }.contains(settings.format);
    final input = staticOutput ? '$inputPath[0]' : inputPath;
    final arguments = <String>[
      input,
      '-auto-orient',
      if (settings.width > 0 || settings.height > 0) ...[
        '-resize',
        '${settings.width > 0 ? settings.width : ''}x'
            '${settings.height > 0 ? settings.height : ''}'
            '${settings.keepAspectRatio ? '' : '!'}',
      ],
      if (!settings.keepMetadata) '-strip',
      if (settings.format.lossy) ...['-quality', '$quality'],
      if (settings.format == ImageOutputFormat.jpeg &&
          settings.targetKilobytes > 0) ...[
        '-define',
        'jpeg:extent=${settings.targetKilobytes}KB',
      ],
      if (!settings.format.supportsAlpha) ...[
        '-background',
        'white',
        '-alpha',
        'remove',
        '-alpha',
        'off',
      ],
      outputPath,
    ];
    return Process.run(
      executablePath,
      arguments,
      environment: _environment,
      workingDirectory: runtimeDirectory,
    );
  }

  String _resolveOutputPath(
    String inputPath,
    ImageConversionSettings settings,
  ) {
    final baseName = p.basenameWithoutExtension(inputPath);
    var output = p.join(
      settings.outputDirectory,
      '$baseName.${settings.format.extension}',
    );
    if (settings.overwrite || !File(output).existsSync()) return output;
    var suffix = 1;
    while (File(output).existsSync()) {
      output = p.join(
        settings.outputDirectory,
        '$baseName ($suffix).${settings.format.extension}',
      );
      suffix++;
    }
    return output;
  }

  String _errorText(ProcessResult result) {
    final error = (result.stderr as String).trim();
    if (error.isNotEmpty) return error.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return 'ImageMagick 退出码 ${result.exitCode}';
  }
}
