import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/gif_recorder_screen.dart';

void main() {
  testWidgets(
    'starting a new recording during thumbnail generation must not read an empty frame list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('toolbox_3080/screen_capture');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'selectRegion':
            return {'x': 0, 'y': 0, 'width': 32, 'height': 32};
          case 'captureRegion':
            return {
              'width': 32,
              'height': 32,
              'pixels': Uint8List(32 * 32 * 4),
            };
          default:
            return null;
        }
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GifRecorderScreen())),
      );
      await tester.tap(find.text('选择录制区域'));
      await tester.pump();
      await tester.tap(find.text('开始录制'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(find.text('正在录制 · 1 帧'), findsOneWidget);
      await tester.tap(find.text('停止录制'));
      await tester.pump();
      expect(find.text('正在生成帧预览…'), findsOneWidget);
      await tester.tap(find.text('开始录制'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final error = tester.takeException();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      expect(error, isNull);
    },
  );
}
