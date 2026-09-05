import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toolbox_3080/input_tester_screen.dart';
import 'package:toolbox_3080/models/app_models.dart';
import 'package:toolbox_3080/services/export_service.dart';
import 'package:toolbox_3080/services/gif_export_service.dart';
import 'package:toolbox_3080/services/hardware_detection_service.dart';
import 'package:toolbox_3080/services/image_conversion_service.dart';

void main() {
  test('format conversion can upscale while preserving aspect ratio', () async {
    final temp = await Directory.systemTemp.createTemp('toolbox-upscale-test-');
    try {
      final input = File('${temp.path}/source.png');
      final output = Directory('${temp.path}/output');
      final source = img.Image(width: 100, height: 50);
      await input.writeAsBytes(img.encodePng(source));
      final result = await ImageConversionService().convert(
        input.path,
        ImageConversionSettings(
          outputDirectory: output.path,
          format: ImageOutputFormat.png,
          quality: 90,
          width: 200,
          height: 100,
          keepAspectRatio: true,
          keepMetadata: false,
          overwrite: false,
          targetKilobytes: 0,
        ),
      );
      final converted = img.decodeImage(
        await File(result.outputPath).readAsBytes(),
      );
      expect((converted!.width, converted.height), (200, 100));
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);

  test('only matching RTX 3080 is renamed in a mixed GPU report', () {
    final snapshot = HardwareSnapshot(
      computerName: 'test',
      collectedAt: DateTime(2026),
      sections: const [
        HardwareSection(
          id: 'gpu',
          title: '显卡',
          items: [
            HardwareItem(label: '显卡 1', value: 'NVIDIA GeForce RTX 3080'),
            HardwareItem(label: '显卡 2', value: 'AMD Radeon Graphics'),
          ],
        ),
      ],
    );
    final report = snapshot.toReport();
    expect(report, contains('显卡 1：老牧师3080'));
    expect(report, contains('显卡 2：AMD Radeon Graphics'));
  });

  test('colored portrait contain padding should use selected background', () {
    final source = img.Image(width: 100, height: 50, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(0, 0, 255));
    final result = const ExportService().render(
      Uint8List.fromList(img.encodePng(source)),
      const ExportSettings(
        width: 100,
        height: 100,
        format: OutputFormat.png,
        resizeMode: ResizeMode.contain,
        targetKilobytes: 0,
        backgroundColor: RgbColor(0, 0, 255),
      ),
    );
    final top = img.decodeImage(result.bytes)!.getPixel(50, 0);
    expect([top.r, top.g, top.b], [0, 0, 255]);
  });

  test(
    'five frames captured at 5 FPS should retain one-second duration',
    () async {
      final frames = List.generate(5, (index) {
        final source = img.Image(width: 8, height: 8, numChannels: 3);
        img.fill(source, color: img.ColorRgb8(index * 40, 0, 255));
        return RecordedScreenFrame(
          width: 8,
          height: 8,
          jpegBytes: Uint8List.fromList(img.encodeJpg(source)),
        );
      });
      final result = await const GifExportService().encode(
        frames,
        const GifExportSettings(
          framesPerSecond: 5,
          colors: 64,
          scalePercent: 100,
        ),
      );
      final decoded = img.decodeGif(result.bytes)!;
      final durationMs = decoded.frames.fold<int>(
        0,
        (sum, frame) => sum + frame.frameDuration,
      );
      expect(durationMs, 1000);
    },
  );

  testWidgets(
    'pressing right mouse while left remains held should be counted',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: InputTesterScreen())),
      );
      final area = find.byKey(const ValueKey('mouse-test-area'));
      await tester.ensureVisible(area);
      final position = tester.getCenter(area);
      await tester.sendEventToBinding(
        PointerAddedEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          position: position,
        ),
      );
      await tester.sendEventToBinding(
        PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          position: position,
          buttons: kPrimaryMouseButton,
        ),
      );
      await tester.pump();
      expect(find.text('鼠标左键  1'), findsOneWidget);
      // Flutter delivers additional mouse-button presses as PointerMoveEvent.
      await tester.sendEventToBinding(
        PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.mouse,
          position: position,
          buttons: kPrimaryMouseButton | kSecondaryMouseButton,
        ),
      );
      await tester.pump();
      expect(find.text('鼠标右键  1'), findsOneWidget);
    },
  );
}
