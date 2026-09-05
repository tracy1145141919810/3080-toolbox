import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/local_translation_screen.dart';
import 'package:toolbox_3080/models/ocr_layout.dart';
import 'package:toolbox_3080/services/local_translation_service.dart';
import 'package:toolbox_3080/widgets/ocr_layout_view.dart';

class FakeJapaneseOcr extends LocalOcrService {
  String? selected;
  @override
  Future<List<Map<String, String>>> languages() async => [];
  @override
  Future<LocalOcrResult?> scanScreen(String language) async {
    selected = language;
    return LocalOcrResult(
      'キャスト\t内山夕実',
      'Japanese',
      30,
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
      width: 400,
      height: 200,
      blocks: const [
        OcrBlock(text: 'キャスト', x: 20, y: 30, width: 120, height: 24),
        OcrBlock(text: '内山夕実', x: 240, y: 30, width: 120, height: 24),
      ],
    );
  }
}

class FakeTranslator extends LocalTranslationService {
  final inputs = <String>[];
  final targets = <String>[];
  @override
  Future<void> ensureReady() async {}
  @override
  Stream<TranslationUpdate> translate(
    String text,
    String target, {
    String? context,
  }) async* {
    inputs.add(text);
    targets.add(target);
    yield TranslationUpdate(text == 'キャスト' ? '配音演员' : text, 10, done: true);
  }
}

void main() {
  testWidgets(
    'Japanese OCR is available without a Windows language pack and preserves boxes',
    (tester) async {
      final ocr = FakeJapaneseOcr();
      final translator = FakeTranslator();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalTranslationScreen(ocr: ocr, translator: translator),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('中 / 日 / 英'), findsOneWidget);
      await tester.tap(find.text('框选屏幕翻译'));
      await tester.pumpAndSettle();
      expect(ocr.selected, 'multilingual');
      expect(translator.inputs, ['キャスト', '内山夕実']);
      expect(find.byType(OcrLayoutView), findsOneWidget);
      final views = tester
          .widgetList<OcrLayoutView>(find.byType(OcrLayoutView))
          .toList();
      expect(views[0].blocks[1].x, views[0].referenceBlocks![1].x);
      expect(views[0].blocks[0].text, '配音演员');
      expect(find.text('原始截图'), findsOneWidget);
      expect(find.byKey(const ValueKey('image-viewport')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('Hy-MT uses its translation-only user template', () {
    final messages =
        LocalTranslationService.requestBody(
              '日本語',
              'Simplified Chinese',
            )['messages']
            as List;
    expect((messages[0] as Map)['content'], contains('日语'));
    expect(messages, hasLength(1));
    expect((messages[0] as Map)['role'], 'user');
    expect((messages[0] as Map)['content'], endsWith('日本語'));
  });
  test('Qwen local files retain their compatible request template', () {
    final body = LocalTranslationService.requestBody(
      '日本語',
      'English',
      modelFileName: 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    );
    final messages = body['messages'] as List;
    expect(messages, hasLength(2));
    expect((messages[0] as Map)['role'], 'system');
    expect((messages[1] as Map)['content'], '日本語');
  });
  test(
    'Hy-MT preserves background separation and official sampling settings',
    () {
      final body = LocalTranslationService.requestBody(
        'ルーデウス',
        'Simplified Chinese',
        context: '配音表',
      );
      final prompt =
          ((body['messages'] as List).single as Map)['content'] as String;
      expect(prompt, contains('仅用于理解，不要翻译或输出'));
      expect(prompt, contains('配音表'));
      expect(body['temperature'], 0.7);
      expect(body['top_p'], 0.6);
      expect(body['repeat_penalty'], 1.05);
      expect(body.containsKey('chat_template_kwargs'), isFalse);
      expect(LocalTranslationService.defaultModelName, 'Hy-MT2-7B-Q4_K_M.gguf');
    },
  );
  test(
    'GPU status accepts current llama.cpp allocation and offload messages',
    () {
      expect(
        LocalTranslationService.deviceFromLog(
          'load_tensors: offloaded 33/33 layers to GPU',
        ),
        'CUDA GPU',
      );
      expect(
        LocalTranslationService.deviceFromLog(
          'load_tensors: CUDA0 model buffer size = 4096 MiB',
        ),
        'CUDA GPU',
      );
      expect(
        LocalTranslationService.deviceFromLog(
          'load_tensors: offloaded 0/33 layers to GPU',
        ),
        'CPU（GPU 未启用）',
      );
      expect(
        LocalTranslationService.deviceFromLog('found 1 CUDA devices'),
        isNull,
      );
    },
  );
  test('Untranslated Japanese cannot pass the Chinese completion check', () {
    expect(
      LocalTranslationService.hasUntranslatedJapanese(
        '空虚のシルヴァリル',
        'Simplified Chinese',
      ),
      isTrue,
    );
    expect(
      LocalTranslationService.hasUntranslatedJapanese(
        '恒松あゆみ',
        'Simplified Chinese',
      ),
      isTrue,
    );
    expect(
      LocalTranslationService.hasUntranslatedJapanese(
        '空虚的西尔瓦里尔',
        'Simplified Chinese',
      ),
      isFalse,
    );
    expect(
      LocalTranslationService.hasUntranslatedJapanese(
        '小原好美',
        'Simplified Chinese',
      ),
      isFalse,
    );
    expect(
      LocalTranslationService.hasUntranslatedJapanese('日本語の翻訳', 'Japanese'),
      isFalse,
    );
  });
}
