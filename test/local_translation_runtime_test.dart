// Opt-in real local inference, never downloads models or calls remote services.
// HY_SMOKE_RUNTIME, HY_SMOKE_MODEL, HY_SMOKE_REPORT; optional HY_SMOKE_OCR_REPORT.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/services/local_translation_service.dart';

class LocalInferenceTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  LocalInferenceTestBinding();
  final env = Platform.environment;
  test(
    'real offline translation completes and releases the local model',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('toolbox_3080/screen_capture'),
            (_) async => null,
          );
      final service = LocalTranslationService(
        runtimeDirectory: env['HY_SMOKE_RUNTIME'],
        modelPath: env['HY_SMOKE_MODEL'],
      );
      final cpu = env['HY_SMOKE_CPU'] == '1';
      service.useGpu = !cpu;
      final samples = <Map<String, String>>[
        {'text': '設定を保存してから、このウィンドウを閉じてください。', 'target': 'Simplified Chinese'},
        {
          'text': '更新中は電源を切らないでください。ファイルは削除されません。',
          'target': 'Simplified Chinese',
        },
        {
          'text': '合計金額は129.99ドルです。100ドル以上のご注文は送料無料です。',
          'target': 'Simplified Chinese',
        },
        {
          'text': 'Please save your changes before closing this window.',
          'target': 'Simplified Chinese',
        },
        {'text': '这个工具完全在本机运行。', 'target': 'Japanese'},
        {'text': '此工具不会上传截图或文字。', 'target': 'English'},
      ];
      if (cpu) samples.removeRange(1, samples.length);
      if (!cpu && env['HY_SMOKE_OCR_REPORT'] != null) {
        final ocr = jsonDecode(
          await File(env['HY_SMOKE_OCR_REPORT']!).readAsString(),
        );
        for (final block in ocr['blocks'] as List) {
          samples.add({
            'text': block['text'] as String,
            'target': 'Simplified Chinese',
          });
        }
      }
      final results = <Map<String, Object?>>[];
      try {
        await service.ensureReady();
        final gpu = await Process.run('nvidia-smi', [
          '--query-gpu=name,memory.used',
          '--format=csv,noheader',
        ]);
        for (final sample in samples) {
          final clock = Stopwatch()..start();
          int? firstTokenMs;
          TranslationUpdate? last;
          String? error;
          try {
            await for (final update in service.translate(
              sample['text']!,
              sample['target']!,
            )) {
              if (update.text.isNotEmpty) {
                firstTokenMs ??= clock.elapsedMilliseconds;
              }
              last = update;
            }
          } catch (e) {
            error = e.toString();
          }
          results.add({
            'source': sample['text'],
            'target': sample['target'],
            'translation': last?.text,
            'done': last?.done ?? false,
            'firstTokenMs': firstTokenMs,
            'ms': clock.elapsedMilliseconds,
            'error': error,
          });
        }
        await File(env['HY_SMOKE_REPORT']!).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'model': service.modelPath,
            'device': service.deviceLabel,
            'loadMs': service.lastLoadMs,
            'gpuLoaded': gpu.stdout.toString().trim(),
            'results': results,
          }),
        );
        expect(service.deviceLabel, cpu ? startsWith('CPU') : 'CUDA GPU');
        expect(
          results.where((r) => r['done'] != true),
          isEmpty,
          reason: 'Every sample must complete without silently retaining Japanese kana',
        );
      } finally {
        service.dispose();
        expect(service.ready, isFalse);
      }
    },
    skip: env['HY_SMOKE_MODEL'] == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
