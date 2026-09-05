import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/services/local_translation_service.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = File('build/test_support/llama-server.exe');
  test(
    'cancel then immediate retry uses a fresh process and isolates old cleanup',
    () async {
      final previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = _LoopbackHttpOverrides();
      final temp = await Directory.systemTemp.createTemp(
        'toolbox-cancel-test-',
      );
      final model = File('${temp.path}/test.gguf');
      await model.writeAsString('test fixture, not a real model');
      await fixture.copy('${temp.path}/llama-server.exe');
      final service = LocalTranslationService(
        runtimeDirectory: temp.path,
        modelPath: model.path,
      );
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      final releaseSecond = Completer<void>();
      var processes = 0;
      const channel = MethodChannel('toolbox_3080/screen_capture');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'manageChildProcess') {
          processes++;
          if (processes == 1) {
            firstEntered.complete();
            await releaseFirst.future;
          } else if (processes == 2) {
            secondEntered.complete();
            await releaseSecond.future;
          }
        }
        return null;
      });
      try {
        final first = service.ensureReady().then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );
        await firstEntered.future.timeout(const Duration(seconds: 10));
        service.cancel();
        final second = service.ensureReady();
        await secondEntered.future.timeout(const Duration(seconds: 10));
        releaseFirst.complete();
        expect(await first, isA<StateError>());
        final third = service.ensureReady();
        releaseSecond.complete();
        await Future.wait([second, third]).timeout(const Duration(seconds: 10));
        expect(processes, 2);
      } finally {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        if (!releaseSecond.isCompleted) releaseSecond.complete();
        service.dispose();
        HttpOverrides.global = previousHttpOverrides;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        // Windows process termination releases the executable asynchronously.
        for (var attempt = 0; attempt < 20; attempt++) {
          try {
            await temp.delete(recursive: true);
            break;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      }
    },
    skip: !fixture.existsSync()
        ? 'Compile test/fixtures/fake_llama_server.dart first'
        : false,
  );
}
