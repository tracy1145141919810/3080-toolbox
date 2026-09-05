import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/models/ocr_layout.dart';
import 'package:toolbox_3080/widgets/ocr_layout_view.dart';

void main() {
  testWidgets(
    'Source and translation use identical sizes even for a long translation',
    (tester) async {
      const source = [
        OcrBlock(text: 'キャスト', x: 10, y: 10, width: 180, height: 30),
      ];
      for (final width in [350.0, 200.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: width,
                    child: const OcrLayoutView(
                      blocks: source,
                      imageWidth: 400,
                      imageHeight: 200,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: OcrLayoutView(
                      blocks: [source.first.withText('这是一段很长的译文' * 12)],
                      referenceBlocks: source,
                      imageWidth: 400,
                      imageHeight: 200,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final texts = tester.widgetList<Text>(find.byType(Text)).toList();
        expect(texts[0].style!.fontSize, texts[1].style!.fontSize);
        expect(texts[1].overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'Chinese Japanese and Latin share one regular font and one size',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: OcrLayoutView(
                imageWidth: 400,
                imageHeight: 200,
                blocks: [
                  OcrBlock(
                    text: '鲁德斯·格雷拉特',
                    x: 0,
                    y: 0,
                    width: 190,
                    height: 30,
                  ),
                  OcrBlock(
                    text: 'シルフィエット',
                    x: 0,
                    y: 40,
                    width: 190,
                    height: 30,
                  ),
                  OcrBlock(text: 'Lynn', x: 220, y: 0, width: 160, height: 30),
                ],
              ),
            ),
          ),
        ),
      );
      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.data != null)
          .toList();
      expect(rendered.map((w) => w.style!.fontFamily).toSet(), {'ToolboxCJK'});
      expect(rendered.map((w) => w.style!.fontWeight).toSet(), {
        FontWeight.w400,
      });
      expect(rendered.map((w) => w.style!.fontSize).toSet().length, 1);
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  const left = OcrBlock(text: 'ルーデウス', x: 20, y: 50, width: 180, height: 24);
  const right = OcrBlock(text: '内山夕実', x: 260, y: 52, width: 130, height: 24);
  const next = OcrBlock(text: 'ロキシー', x: 20, y: 90, width: 160, height: 24);
  test('Japanese columns retain row pairing despite detection order', () {
    expect(layoutText([right, next, left]), 'ルーデウス\t内山夕実\nロキシー');
    expect(left.withText('校对').x, left.x);
    expect(left.withText('校对').width, left.width);
  });
  test('Parse OCR polygon and confidence without discarding coordinates', () {
    final block = OcrBlock.fromJson({
      'text': '日本語',
      'x': 10,
      'y': 20,
      'width': 100,
      'height': 30,
      'confidence': .7,
      'points': [
        [10, 20],
        [110, 20],
        [110, 50],
        [10, 50],
      ],
    });
    expect(block.points.length, 4);
    expect(block.confidence, .7);
    expect(block.withText('日语').points, block.points);
  });
  testWidgets(
    'Original layout scales uniformly and keeps independent hit targets',
    (tester) async {
      int? edited;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: OcrLayoutView(
                blocks: const [left, right, next],
                imageWidth: 400,
                imageHeight: 200,
                onEdit: (i) => edited = i,
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.text('内山夕実'));
      expect(
        before.left,
        greaterThan(tester.getRect(find.text('ルーデウス')).right),
      );
      await tester.tap(find.text('内山夕実'));
      expect(edited, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: OcrLayoutView(
                blocks: [left, right, next],
                imageWidth: 400,
                imageHeight: 200,
              ),
            ),
          ),
        ),
      );
      final after = tester.getRect(find.text('内山夕実'));
      expect(after.left, closeTo(before.left / 2, .01));
      expect(after.top, closeTo(before.top / 2, .01));
      expect(tester.takeException(), isNull);
    },
  );
}
