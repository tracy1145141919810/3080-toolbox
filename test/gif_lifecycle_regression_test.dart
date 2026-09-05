import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/toolbox_shell.dart';

void main() {
  testWidgets(
    'switching tool while recording starts must not hide the new tool',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('toolbox_3080/screen_capture');
      final startIndicator = Completer<void>();
      final visibility = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'selectRegion':
            return {'x': 0, 'y': 0, 'width': 32, 'height': 32};
          case 'showRecordingIndicator':
            await startIndicator.future;
            return null;
          case 'setToolboxVisible':
            visibility.add((call.arguments as Map)['visible'] as bool);
            return null;
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
        const MaterialApp(
          home: ToolboxShell(initialPage: ToolboxPage.gifRecorder),
        ),
      );
      await tester.tap(find.text('选择录制区域'));
      await tester.pump();
      await tester.tap(find.text('开始录制'));
      await tester.pump();
      await tester.tap(find.text('工具中心'));
      await tester.pump();
      expect(visibility.last, true);
      startIndicator.complete();
      await tester.pump();
      expect(
        visibility.last,
        true,
        reason: 'disposed GIF task must not hide the toolbox after cleanup',
      );
    },
  );
}
