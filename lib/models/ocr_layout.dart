import 'dart:math' as math;

class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.confidence = 1,
    this.points = const [],
  });
  final String text;
  final double x, y, width, height, confidence;
  final List<List<double>> points;
  factory OcrBlock.fromJson(Map<String, dynamic> json) => OcrBlock(
    text: json['text'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    confidence: (json['confidence'] as num? ?? 1).toDouble(),
    points: (json['points'] as List? ?? [])
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
  );
  OcrBlock withText(String value) => OcrBlock(
    text: value,
    x: x,
    y: y,
    width: width,
    height: height,
    confidence: confidence,
    points: points,
  );
}

/// Group horizontal blocks by baseline, then sort columns left-to-right.
/// Geometry remains untouched: grouping is for text export/reading order only.
List<List<OcrBlock>> ocrRows(List<OcrBlock> blocks) {
  final sorted = [...blocks]
    ..sort((a, b) => (a.y + a.height / 2).compareTo(b.y + b.height / 2));
  final rows = <List<OcrBlock>>[];
  for (final block in sorted) {
    List<OcrBlock>? match;
    for (final row in rows.reversed) {
      final anchor = row.first;
      if (((anchor.y + anchor.height / 2) - (block.y + block.height / 2))
              .abs() <=
          math.min(anchor.height, block.height) * .45) {
        match = row;
        break;
      }
    }
    if (match == null) {
      rows.add([block]);
    } else {
      match.add(block);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
  }
  return rows;
}

/// TSV keeps column boundaries when copying into an editor or spreadsheet.
String layoutText(List<OcrBlock> blocks) =>
    ocrRows(blocks)
        .map((row) => row.map((block) => block.text).join('\t'))
        .join('\n');
