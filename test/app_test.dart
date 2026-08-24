import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toolbox_3080/main.dart';
import 'package:toolbox_3080/models/app_models.dart';
import 'package:toolbox_3080/services/export_service.dart';
import 'package:toolbox_3080/services/gif_export_service.dart';
import 'package:toolbox_3080/services/hardware_detection_service.dart';
import 'package:toolbox_3080/services/hardware_monitor_service.dart';
import 'package:toolbox_3080/services/screen_capture_service.dart';
import 'package:toolbox_3080/toolbox_shell.dart';

void main() {
  testWidgets('工具箱首页可以进入白底人像并返回工具中心', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Toolbox3080App());

    expect(find.text('3080工具箱'), findsOneWidget);
    expect(find.text('工具中心'), findsNWidgets(2));
    expect(find.text('打开工具'), findsNWidgets(4));

    await tester.tap(find.widgetWithText(FilledButton, '打开工具').first);
    await tester.pumpAndSettle();

    expect(find.text('选择照片'), findsOneWidget);
    expect(find.text('自动换背景'), findsOneWidget);
    expect(find.textContaining('选择颜色'), findsOneWidget);
    expect(find.text('导出成品'), findsOneWidget);
    expect(find.text('在文件夹中显示'), findsOneWidget);

    final processButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '自动换背景'),
    );
    final exportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '导出成品'),
    );
    expect(processButton.onPressed, isNull);
    expect(exportButton.onPressed, isNull);

    await tester.tap(find.text('工具中心').first);
    await tester.pumpAndSettle();
    expect(find.text('打开工具'), findsNWidgets(4));
  });

  testWidgets('工具搜索和清除搜索可以工作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Toolbox3080App());

    await tester.enterText(find.byType(TextField), '不存在的功能');
    await tester.pump();
    expect(find.text('没有找到匹配的工具'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '清除搜索'));
    await tester.pump();
    expect(find.text('打开工具'), findsNWidgets(4));
  });

  testWidgets('硬件检测独立页面识别 RTX 3080 并在首页显示专属评分', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = HardwareSnapshot(
      computerName: 'TEST-PC',
      collectedAt: DateTime(2026, 8, 24),
      sections: const [
        HardwareSection(
          id: 'system',
          title: '系统与整机',
          items: [
            HardwareItem(label: '整机厂商', value: 'ASUS'),
            HardwareItem(label: '整机型号', value: 'System Product Name'),
            HardwareItem(label: '操作系统', value: 'Windows 11 Pro 64位'),
            HardwareItem(label: '本次运行时间', value: '0 天 21 小时 28 分钟'),
          ],
        ),
        HardwareSection(
          id: 'cpu',
          title: '处理器',
          items: [
            HardwareItem(label: '处理器', value: 'AMD Ryzen 5 7500F'),
            HardwareItem(label: '核心 / 线程', value: '6 核 / 12 线程'),
          ],
        ),
        HardwareSection(
          id: 'gpu',
          title: '显卡与显示',
          items: [
            HardwareItem(label: '显卡 1', value: 'NVIDIA GeForce RTX 3080'),
          ],
        ),
        HardwareSection(
          id: 'memory',
          title: '内存',
          items: [HardwareItem(label: '已安装内存', value: '16 GB')],
        ),
        HardwareSection(
          id: 'board',
          title: '主板与 BIOS',
          items: [
            HardwareItem(label: '主板厂商', value: 'ASUS'),
            HardwareItem(label: '主板型号', value: 'PRIME B650M-F'),
          ],
        ),
        HardwareSection(
          id: 'storage',
          title: '存储设备',
          items: [HardwareItem(label: '物理磁盘 1', value: 'ZHITAI Ti600 1TB')],
        ),
        HardwareSection(
          id: 'monitor',
          title: '显示器',
          items: [HardwareItem(label: '显示器 1', value: 'ANT27VU')],
        ),
        HardwareSection(
          id: 'audio',
          title: '声卡',
          items: [HardwareItem(label: '声卡 1', value: 'NVIDIA Audio')],
        ),
        HardwareSection(
          id: 'network',
          title: '网络适配器',
          items: [HardwareItem(label: '网卡', value: 'Realtek PCIe GbE')],
        ),
      ],
    );
    expect(snapshot.toReport(), contains('显卡 1：老牧师3080'));
    var telemetryCancelled = false;
    final telemetryController = StreamController<HardwareTelemetry>(
      onCancel: () => telemetryCancelled = true,
    );
    addTearDown(telemetryController.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: ToolboxShell(
          hardwareLoader: () async => snapshot,
          hardwareTelemetryStreamFactory: () => telemetryController.stream,
        ),
      ),
    );

    expect(find.text('114514分'), findsNothing);
    await tester.tap(find.text('硬件检测').first);
    await tester.pumpAndSettle();
    telemetryController.add(
      HardwareTelemetry(
        collectedAt: DateTime(2026, 8, 24, 14, 30),
        cpuUsagePercent: 36,
        cpuFrequencyMhz: 5200,
        gpuUsagePercent: 48,
        gpuTemperatureCelsius: 52,
        gpuMemoryUsedMb: 3072,
        gpuMemoryTotalMb: 10240,
        gpuPowerWatts: 76,
        memoryUsagePercent: 64,
        memoryUsedGb: 10.1,
        memoryTotalGb: 15.7,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CPU 实时'), findsOneWidget);
    expect(find.text('GPU 实时'), findsOneWidget);
    expect(find.text('内存实时'), findsOneWidget);
    expect(find.text('36 %'), findsOneWidget);
    expect(find.text('48 %'), findsOneWidget);
    expect(find.text('64 %'), findsOneWidget);
    expect(find.textContaining('52 °C'), findsOneWidget);
    expect(find.text('详细信息'), findsOneWidget);
    final special = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == '老牧师3080',
      ),
    );
    expect(special.style?.color, const Color(0xFFD92D20));

    await tester.tap(find.text('工具中心'));
    await tester.pumpAndSettle();
    expect(telemetryCancelled, isTrue);
    expect(find.text('114514分'), findsOneWidget);
    expect(find.text('整机性能评分'), findsOneWidget);
  });

  testWidgets('图片格式转换分支已整合且空列表不能启动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Toolbox3080App());

    await tester.tap(find.text('格式转换'));
    await tester.pumpAndSettle();

    expect(find.text('图片格式转换'), findsOneWidget);
    expect(find.text('添加文件夹'), findsOneWidget);
    expect(find.text('添加图片'), findsOneWidget);
    expect(find.text('输出格式'), findsOneWidget);
    expect(find.text('输出分辨率（0 = 保持原始）'), findsOneWidget);
    expect(find.text('目标文件大小（0 = 不限制）'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始转换'),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('GIF录屏分支已整合且导出按钮按状态工作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Toolbox3080App());

    await tester.tap(find.text('GIF录屏').first);
    await tester.pumpAndSettle();

    expect(find.text('选择录制区域'), findsOneWidget);
    expect(find.text('开始录制'), findsOneWidget);
    expect(find.text('帧时间线'), findsOneWidget);
    expect(find.text('导出 GIF'), findsOneWidget);
    expect(find.text('目标文件大小上限（KB）'), findsOneWidget);
    await tester.tap(find.text('5 秒'));
    await tester.pumpAndSettle();
    expect(find.text('5 分钟'), findsOneWidget);
    await tester.tap(find.text('5 分钟'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最长支持 5 分钟'), findsOneWidget);
    final export = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '导出 GIF'),
    );
    expect(export.onPressed, isNull);
  });

  test('JPEG 导出同时满足指定分辨率与文件大小上限', () {
    final source = img.Image(width: 800, height: 1000, numChannels: 3);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final result = const ExportService().render(
      img.encodePng(source),
      const ExportSettings(
        width: 295,
        height: 413,
        format: OutputFormat.jpeg,
        resizeMode: ResizeMode.cover,
        targetKilobytes: 100,
      ),
    );
    final decoded = img.decodeJpg(result.bytes)!;
    expect(decoded.width, 295);
    expect(decoded.height, 413);
    expect(result.byteLength, lessThanOrEqualTo(100 * 1024));
  });

  test('透明人像可以即时合成任意 RGB 背景色', () {
    final cutout = img.Image(width: 2, height: 2, numChannels: 4);
    img.fill(cutout, color: img.ColorRgba8(0, 0, 0, 0));
    final bytes = const ExportService().applyBackground(
      img.encodePng(cutout),
      const RgbColor(12, 34, 56),
    );
    final result = img.decodePng(bytes)!;
    final pixel = result.getPixel(0, 0);
    expect(pixel.r, 12);
    expect(pixel.g, 34);
    expect(pixel.b, 56);
  });

  test('GIF 编码保留帧数并应用输出分辨率', () async {
    RawScreenFrame frame(int blue) {
      final bytes = Uint8List(8 * 6 * 4);
      for (var index = 0; index < bytes.length; index += 4) {
        bytes[index] = blue;
        bytes[index + 1] = 40;
        bytes[index + 2] = 220;
        bytes[index + 3] = 255;
      }
      return RawScreenFrame(width: 8, height: 6, bgraBytes: bytes);
    }

    const service = GifExportService();
    final frames = [
      await service.compressFrame(frame(20)),
      await service.compressFrame(frame(180)),
    ];
    final result = await service.encode(
      frames,
      const GifExportSettings(framesPerSecond: 5, colors: 64, scalePercent: 50),
    );
    final decoded = img.decodeGif(result.bytes)!;
    expect(decoded.width, 4);
    expect(decoded.height, 3);
    expect(decoded.numFrames, 2);
  });
}
