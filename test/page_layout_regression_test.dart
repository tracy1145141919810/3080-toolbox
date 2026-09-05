import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/hardware_detection_screen.dart';
import 'package:toolbox_3080/main.dart';
import 'package:toolbox_3080/services/hardware_detection_service.dart';
import 'package:toolbox_3080/services/hardware_monitor_service.dart';
import 'package:toolbox_3080/toolbox_shell.dart';

void main() {
  const pages = [
    ToolboxPage.home,
    ToolboxPage.portraitBackground,
    ToolboxPage.imageConverter,
    ToolboxPage.gifRecorder,
    ToolboxPage.qrScanner,
    ToolboxPage.screenTranslation,
    ToolboxPage.inputTester,
  ];

  for (final size in [const Size(900, 520), const Size(720, 480)]) {
    for (final page in pages) {
      testWidgets('${page.name} lays out at ${size.width}x${size.height}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('toolbox_3080/screen_capture'),
              (_) async => null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('toolbox_3080/screen_capture'),
                null,
              ),
        );
        final errors = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = errors.add;
        await tester.pumpWidget(Toolbox3080App(initialPage: page));
        await tester.pumpAndSettle();
        FlutterError.onError = previous;
        expect(
          errors.map((error) => error.exceptionAsString()).toList(),
          isEmpty,
        );
      });
    }
  }

  testWidgets('hardware page lays out at 720x480 with live telemetry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final telemetry = StreamController<HardwareTelemetry>();
    addTearDown(telemetry.close);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(
      MaterialApp(
        home: HardwareDetectionScreen(
          loader: () async => HardwareSnapshot(
            computerName: 'test',
            collectedAt: DateTime(2026),
            sections: const [
              HardwareSection(
                id: 'gpu',
                title: '显卡',
                items: [
                  HardwareItem(label: '显卡 1', value: 'NVIDIA GeForce RTX 3080'),
                ],
              ),
            ],
          ),
          telemetryStreamFactory: () => telemetry.stream,
        ),
      ),
    );
    telemetry.add(
      HardwareTelemetry(
        collectedAt: DateTime(2026),
        cpuUsagePercent: 30,
        gpuUsagePercent: 40,
        memoryUsagePercent: 50,
      ),
    );
    await tester.pumpAndSettle();
    FlutterError.onError = previous;
    expect(errors.map((error) => error.exceptionAsString()).toList(), isEmpty);
  });
}
