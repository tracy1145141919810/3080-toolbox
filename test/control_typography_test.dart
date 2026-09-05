import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/main.dart';

void main() {
  testWidgets(
    'Control labels preserve font, proportions and bounds at multiple DPI/text scales',
    (tester) async {
      final loader = FontLoader('ToolboxCJK')
        ..addFont(rootBundle.load('assets/fonts/NotoSansCJKsc-Medium.otf'));
      await loader.load();
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var presses = 0;
      const labels = ['复制原文', '翻译原文', '复制译文'];
      for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
        for (final width in [380.0, 1100.0]) {
          for (final textScale in [1.0, 1.5, 2.0]) {
            tester.view.devicePixelRatio = dpr;
            tester.view.physicalSize = Size(width * dpr, 500 * dpr);
            await tester.pumpWidget(
              Toolbox3080App(
                homeOverride: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => presses++,
                              child: const Text('复制原文'),
                            ),
                            FilledButton(
                              onPressed: () => presses++,
                              child: const Text('翻译原文'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => presses++,
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('复制译文'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final rects = <Rect>[];
            for (final label in labels) {
              final finder = find.text(label);
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              final style = paragraph.text.style!;
              expect(style.fontFamily, 'ToolboxCJK');
              expect(style.fontSize, 14);
              expect(style.fontWeight, FontWeight.w500);
              expect(style.letterSpacing, 0);
              expect(style.wordSpacing, 0);
              final transform = paragraph.getTransformTo(null);
              expect(
                transform.entry(0, 0),
                closeTo(transform.entry(1, 1), .00001),
              );
              expect(transform.entry(0, 1), 0);
              expect(transform.entry(1, 0), 0);
              final rect = tester.getRect(finder);
              rects.add(rect);
              final button = find
                  .ancestor(
                    of: finder,
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first;
              final bounds = tester.getRect(button);
              expect(bounds.contains(rect.topLeft), isTrue);
              expect(
                bounds.contains(rect.bottomRight - const Offset(.01, .01)),
                isTrue,
              );
              await tester.tap(finder);
              await tester.pumpAndSettle();
            }
            expect(rects[0].width, closeTo(rects[1].width, .01));
            expect(rects[0].width, closeTo(rects[2].width, .01));
            expect(rects[0].height, closeTo(rects[2].height, .01));
            expect(tester.takeException(), isNull);
          }
        }
      }
      expect(presses, 72);
    },
  );
}
