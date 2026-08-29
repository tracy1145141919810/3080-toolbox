import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:heic_native/heic_native.dart';
import 'package:image/image.dart' as img;

import 'models/app_models.dart';
import 'services/export_service.dart';
import 'services/gif_export_service.dart';
import 'services/hardware_detection_service.dart';
import 'services/hardware_monitor_service.dart';
import 'services/image_conversion_service.dart';
import 'services/qr_scanner_service.dart';
import 'services/screen_capture_service.dart';
import 'services/yolo_segmentation_service.dart';
import 'toolbox_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length == 3 && args.first == '--heic-decode-test') {
    await _runHeicDecodeTest(args[1], args[2]);
    return;
  }
  if (args.length == 3 && args.first == '--smoke-test') {
    await _runSmokeTest(args[1], args[2]);
    return;
  }
  if (args.length == 2 && args.first == '--gif-smoke-test') {
    await _runGifSmokeTest(args[1]);
    return;
  }
  if (args.length == 2 && args.first == '--region-select-smoke-test') {
    await _runRegionSelectSmokeTest(args[1]);
    return;
  }
  if (args.length == 2 && args.first == '--visibility-smoke-test') {
    await _runVisibilitySmokeTest(args[1]);
    return;
  }
  if (args.length == 4 && args.first == '--convert-smoke-test') {
    await _runConversionSmokeTest(args[1], args[2], args[3]);
    return;
  }
  if (args.length == 2 && args.first == '--hardware-smoke-test') {
    await _runHardwareSmokeTest(args[1]);
    return;
  }
  if (args.length == 2 && args.first == '--telemetry-smoke-test') {
    await _runTelemetrySmokeTest(args[1]);
    return;
  }
  if (args.length == 2 && args.first == '--qr-smoke-test') {
    await _runQrSmokeTest(args[1]);
    return;
  }
  runApp(
    Toolbox3080App(
      initialPage: switch (args) {
        ['--show-hardware'] => ToolboxPage.hardwareDetection,
        ['--show-input-tester'] => ToolboxPage.inputTester,
        ['--show-qr-scanner'] => ToolboxPage.qrScanner,
        _ => ToolboxPage.home,
      },
    ),
  );
}

Future<void> _runQrSmokeTest(String outputPath) async {
  const expected = 'https://example.com/3080-toolbox-qr-smoke';
  var status = 0;
  try {
    final encoded = zxing.zx.encodeBarcode(
      contents: expected,
      params: zxing.EncodeParams(
        format: zxing.Format.qrCode,
        width: 512,
        height: 512,
        margin: 16,
        eccLevel: zxing.EccLevel.high,
      ),
    );
    if (!encoded.isValid || encoded.data == null) {
      throw StateError(encoded.error ?? '二维码测试图生成失败');
    }
    final png = zxing.pngFromBytes(encoded.data!, 512, 512);
    await File(outputPath).writeAsBytes(png, flush: true);
    final payload = await const QrScannerService().scanFile(outputPath);
    if (!payload.results.any((result) => result.text == expected)) {
      throw StateError('二维码解码结果与预期不一致');
    }
    await File('$outputPath.smoke.txt').writeAsString(
      'results=${payload.results.length}\n'
      'durationMs=${payload.durationMs}\n'
      'text=${payload.results.first.text}\n',
      flush: true,
    );
    stdout.writeln(
      'QR_OK results=${payload.results.length} '
      'durationMs=${payload.durationMs} text=${payload.results.first.text}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('QR_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runTelemetrySmokeTest(String outputPath) async {
  final monitor = HardwareMonitorService();
  var status = 0;
  try {
    final samples = await monitor
        .watch()
        .take(3)
        .toList()
        .timeout(const Duration(seconds: 15));
    await File(outputPath).writeAsString(
      samples.map((sample) => jsonEncode(sample.toJson())).join('\n'),
      encoding: utf8,
      flush: true,
    );
    stdout.writeln(
      'TELEMETRY_OK samples=${samples.length} '
      'cpu=${samples.last.cpuUsagePercent} '
      'gpu=${samples.last.gpuUsagePercent} '
      'memory=${samples.last.memoryUsagePercent}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('TELEMETRY_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  } finally {
    await monitor.dispose();
  }
  exit(status);
}

Future<void> _runHardwareSmokeTest(String outputPath) async {
  var status = 0;
  try {
    final snapshot = await const HardwareDetectionService().detect();
    await File(outputPath)
        .writeAsString(snapshot.toReport(), encoding: utf8, flush: true);
    stdout.writeln(
      'HARDWARE_OK sections=${snapshot.sections.length} '
      'items=${snapshot.itemCount} rtx3080=${snapshot.hasRtx3080}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('HARDWARE_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runConversionSmokeTest(
  String inputPath,
  String outputDirectory,
  String formatName,
) async {
  var status = 0;
  try {
    final format = ImageOutputFormat.values.byName(formatName);
    final result = await ImageConversionService().convert(
      inputPath,
      ImageConversionSettings(
        outputDirectory: outputDirectory,
        format: format,
        quality: 86,
        width: 320,
        height: 240,
        keepAspectRatio: true,
        keepMetadata: false,
        overwrite: true,
        targetKilobytes: format.lossy ? 100 : 0,
      ),
    );
    await File('${result.outputPath}.smoke.txt').writeAsString(
      'format=${format.label}\n'
      'path=${result.outputPath}\n'
      'bytes=${result.byteLength}\n'
      'quality=${result.quality}\n'
      'metTarget=${result.metTarget}\n',
      flush: true,
    );
    stdout.writeln(
      'CONVERT_OK format=${format.label} bytes=${result.byteLength} '
      'path=${result.outputPath}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('CONVERT_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runVisibilitySmokeTest(String outputPath) async {
  const capture = ScreenCaptureService();
  var status = 0;
  try {
    await capture.showRecordingIndicator('录制中 00:01 / 05:00 · 点击暂停');
    await capture.setToolboxVisible(false);
    await File(outputPath).writeAsString('hidden=true\n', flush: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    await capture.updateRecordingIndicator('录制已暂停 · 返回工具箱操作');
    await Future<void>.delayed(const Duration(seconds: 1));
    await capture.hideRecordingIndicator();
    await capture.setToolboxVisible(true);
    await File(outputPath).writeAsString('hidden=true\nrestored=true\n');
  } catch (error, stackTrace) {
    stderr.writeln('VISIBILITY_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runRegionSelectSmokeTest(String outputPath) async {
  var status = 0;
  try {
    final region = await const ScreenCaptureService().selectRegion();
    if (region == null) throw StateError('区域选择被取消');
    await File(outputPath).writeAsString(
      'x=${region.x}\ny=${region.y}\n'
      'width=${region.width}\nheight=${region.height}\n',
      flush: true,
    );
  } catch (error, stackTrace) {
    stderr.writeln('REGION_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runGifSmokeTest(String outputPath) async {
  var status = 0;
  try {
    const capture = ScreenCaptureService();
    const region = ScreenRegion(x: 0, y: 0, width: 320, height: 200);
    const gifService = GifExportService();
    final frames = <RecordedScreenFrame>[];
    for (var index = 0; index < 3; index++) {
      final rawFrame = await capture.capture(
        region,
        outputWidth: 320,
        outputHeight: 200,
        includeCursor: true,
      );
      frames.add(await gifService.compressFrame(rawFrame));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final result = await gifService.encode(
      frames,
      const GifExportSettings(
        framesPerSecond: 5,
        colors: 64,
        scalePercent: 100,
      ),
    );
    await File(outputPath).writeAsBytes(result.bytes, flush: true);
    await File('$outputPath.smoke.txt').writeAsString(
      'frames=${frames.length}\n'
      'width=${result.width}\n'
      'height=${result.height}\n'
      'bytes=${result.bytes.length}\n',
      flush: true,
    );
    stdout.writeln(
      'GIF_OK frames=${frames.length} width=${result.width} '
      'height=${result.height} bytes=${result.bytes.length}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('GIF_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runHeicDecodeTest(String inputPath, String outputPath) async {
  var status = 0;
  try {
    final pngBytes = await HeicNative.convertToBytes(
      inputPath,
      compressionLevel: 3,
      preserveMetadata: false,
    );
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) {
      throw const FormatException('HEIC 解码结果不是有效的 PNG 图像');
    }
    await File(outputPath).writeAsBytes(pngBytes, flush: true);
    await File('$outputPath.smoke.txt').writeAsString(
      'width=${decoded.width}\n'
      'height=${decoded.height}\n'
      'bytes=${pngBytes.length}\n',
      flush: true,
    );
    stdout.writeln(
      'HEIC_OK width=${decoded.width} height=${decoded.height} '
      'bytes=${pngBytes.length}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('HEIC_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  }
  exit(status);
}

Future<void> _runSmokeTest(String inputPath, String outputPath) async {
  final yolo = YoloSegmentationService();
  var status = 0;
  try {
    final input = await File(inputPath).readAsBytes();
    final segmented = await yolo.process(input, InferenceDevice.automatic);
    final exported = const ExportService().render(
      segmented.pngBytes,
      const ExportSettings(
        width: 600,
        height: 800,
        format: OutputFormat.jpeg,
        resizeMode: ResizeMode.cover,
        targetKilobytes: 150,
      ),
    );
    await File(outputPath).writeAsBytes(exported.bytes, flush: true);
    await File('$outputPath.smoke.txt').writeAsString(
      'device=${segmented.deviceLabel}\n'
      'persons=${segmented.personCount}\n'
      'width=600\nheight=800\nbytes=${exported.byteLength}\n',
      flush: true,
    );
    stdout.writeln(
      'SMOKE_OK device=${segmented.deviceLabel} '
      'persons=${segmented.personCount} bytes=${exported.byteLength}',
    );
  } catch (error, stackTrace) {
    stderr.writeln('SMOKE_FAILED $error');
    stderr.writeln(stackTrace);
    status = 1;
  } finally {
    yolo.dispose();
  }
  exit(status);
}

class Toolbox3080App extends StatelessWidget {
  const Toolbox3080App({super.key, this.initialPage = ToolboxPage.home});

  final ToolboxPage initialPage;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2563EB);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: const Color(0xFFF7F8FA),
    );
    return MaterialApp(
      title: '3080工具箱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: ToolboxShell(initialPage: initialPage),
    );
  }
}
