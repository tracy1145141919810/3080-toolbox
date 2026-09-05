import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/local_translation_screen.dart';
import 'package:toolbox_3080/services/local_translation_service.dart';
import 'package:toolbox_3080/widgets/ocr_layout_view.dart';

import 'local_translation_test.dart' show FakeJapaneseOcr, FakeTranslator;

class LongTranslator extends FakeTranslator {
  static final result = '${List.filled(130, '译').join()}\n第二行';
  @override
  Stream<TranslationUpdate> translate(
    String text,
    String target, {
    String? context,
  }) async* {
    yield TranslationUpdate(result, 1, done: true);
  }
}

void main() {
  testWidgets('typing first source text enables copy immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTranslationScreen(
            ocr: FakeJapaneseOcr(),
            translator: FakeTranslator(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, '复制原文');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
  });
  testWidgets('long multiline translated block is retained without aborting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalTranslationScreen(
            ocr: FakeJapaneseOcr(),
            translator: LongTranslator(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('框选屏幕翻译'));
    await tester.pumpAndSettle();
    final layout = tester.widget<OcrLayoutView>(find.byType(OcrLayoutView));
    expect(layout.blocks.every((b) => b.text == LongTranslator.result), isTrue);
    expect(find.textContaining('超出单个文字框'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
