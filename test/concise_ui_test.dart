import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toolbox_3080/main.dart';
import 'package:toolbox_3080/toolbox_shell.dart';

void main() {
  testWidgets('二维码空状态保持顶部对齐，不因移除教程而居中', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const Toolbox3080App(initialPage: ToolboxPage.qrScanner),
    );
    expect(tester.getTopLeft(find.text('二维码扫描').last).dy, lessThan(100));
    expect(find.text('等待扫描'), findsOneWidget);
    expect(find.text('暂无识别结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('工具中心保留七个可用入口，不显示介绍文案和装饰性标签', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Toolbox3080App());
    expect(find.text('打开工具'), findsNWidgets(7));
    expect(find.text('7'), findsOneWidget);
    for (final text in [
      'YOLO',
      'GPU',
      'HEIC',
      '批量转换',
      '本地处理',
      '日语 OCR',
      '本地只读',
      '本地影像处理工作台',
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(find.textContaining('数据无需上传'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻译页在模型缺失时明确提示用户自行导入', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const Toolbox3080App(initialPage: ToolboxPage.screenTranslation),
    );
    expect(find.textContaining('未导入翻译模型'), findsOneWidget);
    expect(find.text('导入本地模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('七个工具的宣传副标题不再进入界面', () {
    final removed = <String, List<String>>{
      'home_screen.dart': ['YOLO 本地识别 · HEIC 支持'],
      'gif_recorder_screen.dart': ['框选区域 · 帧预览与删除'],
      'image_converter_screen.dart': ['主流格式批量转换 · HEIC/RAW'],
      'hardware_detection_screen.dart': ['读取本机硬件与 Windows 系统信息 · 无需联网'],
      'input_tester_screen.dart': ['全键位触发、鼠标五键与滚轮', 'required this.subtitle'],
      'qr_scanner_screen.dart': ['两种快速扫描方式', '_buildPrivacyNotice', '完全离线'],
      'local_translation_screen.dart': [
        '仅本机回环通信，无在线服务或云端回退',
        '没有任何在线请求',
        '模型首次加载需要几秒',
      ],
    };
    for (final entry in removed.entries) {
      final source = File('lib/${entry.key}').readAsStringSync();
      for (final text in entry.value) {
        expect(source.contains(text), isFalse, reason: '${entry.key}: $text');
      }
    }
  });
}
