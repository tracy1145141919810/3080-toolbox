import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/models/ocr_layout.dart';
import 'package:toolbox_3080/widgets/linked_ocr_comparison.dart';

void main() {
  testWidgets(
    'image and text retain one camera through zoom, pan, resize, DPI and new captures',
    (tester) async {
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      var preview = image;
      var imageSize = const Size(842, 1131);
      var text = '测试文字';
      var edits = 0;
      Future<void> pump(double width, double dpr) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(width * dpr, 1600 * dpr);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LinkedOcrComparison(
                  preview: preview,
                  imageWidth: imageSize.width.toInt(),
                  imageHeight: imageSize.height.toInt(),
                  blocks: [
                    OcrBlock(text: text, x: 30, y: 50, width: 250, height: 40),
                  ],
                  referenceBlocks: const [
                    OcrBlock(
                      text: '原始文字',
                      x: 30,
                      y: 50,
                      width: 250,
                      height: 40,
                    ),
                  ],
                  leftTitle: '译文',
                  onEdit: (_) => edits++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Finder viewport(String name) => find.byKey(ValueKey('$name-viewport'));
      Matrix4 matrix(String name) => tester
          .widget<Transform>(find.byKey(ValueKey('$name-camera')))
          .transform;
      void assertLinked() {
        expect(
          tester.getSize(viewport('text')),
          tester.getSize(viewport('image')),
        );
        expect(
          tester.getTopLeft(viewport('text')).dy,
          tester.getTopLeft(viewport('image')).dy,
        );
        expect(matrix('text'), matrix('image'));
        final size = tester.getSize(viewport('image'));
        expect(
          size.width / size.height,
          closeTo(imageSize.width / imageSize.height, .000001),
        );
        final camera = matrix('text');
        expect(camera.entry(0, 0), camera.entry(1, 1));
        expect(camera.entry(0, 1), 0);
        expect(camera.entry(1, 0), 0);
        // A source-image landmark must occupy the same relative position in
        // both panes, not just share a nominal zoom percentage.
        final point = Offset(
          30 / imageSize.width * size.width,
          50 / imageSize.height * size.height,
        );
        expect(
          MatrixUtils.transformPoint(matrix('text'), point),
          MatrixUtils.transformPoint(matrix('image'), point),
        );
      }

      await pump(1100, 1);
      await tester.tap(find.text('测试文字'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      assertLinked();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(viewport('image')),
          scrollDelta: const Offset(0, -300),
        ),
      );
      await tester.pumpAndSettle();
      expect(matrix('text').entry(0, 0), greaterThan(1));
      assertLinked();
      await tester.drag(viewport('image'), const Offset(-30, -40));
      await tester.pumpAndSettle();
      assertLinked();
      final oldSize = tester.getSize(viewport('image'));
      final normalizedX = matrix('image').entry(0, 3) / oldSize.width;
      final normalizedY = matrix('image').entry(1, 3) / oldSize.height;
      for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
        for (final width in [380.0, 800.0, 1600.0]) {
          await pump(width, dpr);
          assertLinked();
          final size = tester.getSize(viewport('image'));
          expect(
            matrix('image').entry(0, 3) / size.width,
            closeTo(normalizedX, 1e-9),
          );
          expect(
            matrix('image').entry(1, 3) / size.height,
            closeTo(normalizedY, 1e-9),
          );
        }
      }
      final beforeStream = matrix('image').clone();
      text = '新的译文';
      await pump(1600, 2);
      expect(matrix('image'), beforeStream);
      assertLinked();
      await tester.drag(viewport('text'), const Offset(20, 20));
      await tester.pumpAndSettle();
      assertLinked();
      await tester.tap(find.text('复位视图'));
      await tester.pumpAndSettle();
      expect(matrix('text'), Matrix4.identity());
      for (final dimensions in [
        const Size(1920, 1080),
        const Size(500, 1500),
      ]) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(viewport('image')),
            scrollDelta: const Offset(0, -200),
          ),
        );
        await tester.pump();
        preview = image.sublist(0);
        imageSize = dimensions;
        await pump(800, 1);
        expect(matrix('image'), Matrix4.identity());
        assertLinked();
      }
    },
  );
}
