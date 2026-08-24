import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:heic_native/heic_native.dart';
import 'package:path/path.dart' as p;

import 'models/app_models.dart';
import 'services/export_service.dart';
import 'services/yolo_segmentation_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _imageTypes = XTypeGroup(
    label: '图像',
    extensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp', 'heic', 'heif'],
  );

  final _yolo = YoloSegmentationService();
  final _exporter = const ExportService();
  final _widthController = TextEditingController(text: '295');
  final _heightController = TextEditingController(text: '413');
  final _sizeController = TextEditingController(text: '100');

  Uint8List? _sourceBytes;
  Uint8List? _cutoutBytes;
  Uint8List? _processedBytes;
  String? _sourcePath;
  String? _exportedPath;
  SegmentationResult? _segmentation;
  SizePreset _preset = SizePreset.values[1];
  InferenceDevice _device = InferenceDevice.automatic;
  OutputFormat _format = OutputFormat.jpeg;
  ResizeMode _resizeMode = ResizeMode.cover;
  RgbColor _backgroundColor = RgbColor.white;
  bool _busy = false;
  String _status = '请选择一张清晰的人像照片。';
  bool _statusIsError = false;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _sizeController.dispose();
    _yolo.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    if (_busy) return;
    final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (file == null) return;
    try {
      final fileLength = await File(file.path).length();
      if (fileLength > 50 * 1024 * 1024) {
        throw const FormatException('单张图片不能超过 50 MB。');
      }
      final extension = p.extension(file.path).toLowerCase();
      final isHeic = extension == '.heic' || extension == '.heif';
      if (isHeic) {
        setState(() {
          _busy = true;
          _status = '正在本地解码 HEIC/HEIF 图像…';
          _statusIsError = false;
        });
      }
      final bytes = isHeic
          ? await HeicNative.convertToBytes(
              file.path,
              compressionLevel: 3,
              preserveMetadata: false,
            )
          : await file.readAsBytes();
      setState(() {
        _sourceBytes = bytes;
        _sourcePath = file.path;
        _cutoutBytes = null;
        _processedBytes = null;
        _segmentation = null;
        _exportedPath = null;
        _status = isHeic
            ? 'HEIC 图像已在本地解码，点击“自动换背景”开始处理。'
            : '图片已导入，点击“自动换背景”开始处理。';
        _statusIsError = false;
      });
    } on PlatformException catch (error) {
      _setError('HEIC 解码失败：${error.message ?? error.code}');
    } catch (error) {
      _setError(_message(error));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _processImage() async {
    final bytes = _sourceBytes;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _status = '正在加载 YOLO 模型并识别人像…';
      _statusIsError = false;
    });
    try {
      final result = await _yolo.process(bytes, _device);
      if (!mounted) return;
      setState(() {
        _segmentation = result;
        _cutoutBytes = result.pngBytes;
        _processedBytes = _exporter.applyBackground(
          result.pngBytes,
          _backgroundColor,
        );
        _exportedPath = null;
        _status =
            '处理完成：识别到 ${result.personCount} 人，使用 '
            '${result.deviceLabel}，耗时 '
            '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒。';
      });
    } catch (error) {
      _setError(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportImage() async {
    final bytes = _processedBytes;
    if (bytes == null || _busy) return;
    final width = int.tryParse(_widthController.text.trim());
    final height = int.tryParse(_heightController.text.trim());
    final targetKb = int.tryParse(_sizeController.text.trim());
    if (width == null || height == null || width < 1 || height < 1) {
      _setError('请输入有效的宽度和高度。');
      return;
    }
    if (width > 10000 || height > 10000) {
      _setError('导出宽高不能超过 10000 像素。');
      return;
    }
    if (_format == OutputFormat.jpeg && (targetKb == null || targetKb < 0)) {
      _setError('目标文件大小应为 0 或正整数。');
      return;
    }

    final baseName = _sourcePath == null
        ? '白底人像'
        : '${p.basenameWithoutExtension(_sourcePath!)}_白底';
    final location = await getSaveLocation(
      suggestedName: '$baseName.${_format.extension}',
      acceptedTypeGroups: [
        XTypeGroup(label: _format.label, extensions: [_format.extension]),
      ],
    );
    if (location == null) return;

    setState(() {
      _busy = true;
      _status = '正在调整分辨率并压缩文件…';
      _statusIsError = false;
    });
    try {
      final result = _exporter.render(
        bytes,
        ExportSettings(
          width: width,
          height: height,
          format: _format,
          resizeMode: _resizeMode,
          targetKilobytes: _format == OutputFormat.jpeg ? targetKb! : 0,
        ),
      );
      var outputPath = location.path;
      if (p.extension(outputPath).toLowerCase() != '.${_format.extension}') {
        outputPath = '$outputPath.${_format.extension}';
      }
      await File(outputPath).writeAsBytes(result.bytes, flush: true);
      if (!mounted) return;
      final kb = result.byteLength / 1024;
      setState(() {
        _exportedPath = outputPath;
        _status =
            '已导出 ${result.width}×${result.height} ${_format.label}，'
            '${kb.toStringAsFixed(1)} KB'
            '${result.quality == null ? '' : '，质量 ${result.quality}'}。';
      });
    } catch (error) {
      _setError(_message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showExportedFile() async {
    final outputPath = _exportedPath;
    if (outputPath == null || !File(outputPath).existsSync()) return;
    await Process.run('explorer.exe', ['/select,', outputPath]);
  }

  void _applyPreset(SizePreset? preset) {
    if (preset == null) return;
    setState(() {
      _preset = preset;
      if (preset.width > 0) {
        _widthController.text = preset.width.toString();
        _heightController.text = preset.height.toString();
      }
    });
  }

  Future<void> _chooseBackgroundColor() async {
    var red = _backgroundColor.red;
    var green = _backgroundColor.green;
    var blue = _backgroundColor.blue;
    final hexController = TextEditingController(text: _backgroundColor.hex);
    final selected = await showDialog<RgbColor>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void update(int r, int g, int b) {
            setDialogState(() {
              red = r.clamp(0, 255);
              green = g.clamp(0, 255);
              blue = b.clamp(0, 255);
              hexController.text = RgbColor(red, green, blue).hex;
            });
          }

          return AlertDialog(
            title: const Text('选择背景颜色'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Color.fromARGB(255, red, green, blue),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD0D5DD)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ColorSlider(
                    label: 'R',
                    value: red,
                    color: Colors.red,
                    onChanged: (value) => update(value, green, blue),
                  ),
                  _ColorSlider(
                    label: 'G',
                    value: green,
                    color: Colors.green,
                    onChanged: (value) => update(red, value, blue),
                  ),
                  _ColorSlider(
                    label: 'B',
                    value: blue,
                    color: Colors.blue,
                    onChanged: (value) => update(red, green, value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hexController,
                    maxLength: 7,
                    decoration: const InputDecoration(
                      labelText: '十六进制颜色（例如 #FFFFFF）',
                      counterText: '',
                    ),
                    onSubmitted: (value) {
                      final parsed = _parseHex(value);
                      if (parsed != null) {
                        update(parsed.red, parsed.green, parsed.blue);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        const [
                              RgbColor(255, 255, 255),
                              RgbColor(67, 142, 219),
                              RgbColor(35, 92, 185),
                              RgbColor(215, 47, 47),
                              RgbColor(238, 238, 238),
                              RgbColor(32, 32, 32),
                            ]
                            .map(
                              (color) => _ColorPreset(
                                color: color,
                                onTap: () =>
                                    update(color.red, color.green, color.blue),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = _parseHex(hexController.text);
                  Navigator.pop(
                    dialogContext,
                    parsed ?? RgbColor(red, green, blue),
                  );
                },
                child: const Text('使用此颜色'),
              ),
            ],
          );
        },
      ),
    );
    hexController.dispose();
    if (selected == null || !mounted) return;
    setState(() {
      _backgroundColor = selected;
      if (_cutoutBytes != null) {
        _processedBytes = _exporter.applyBackground(
          _cutoutBytes!,
          _backgroundColor,
        );
        _exportedPath = null;
      }
      _status = '背景颜色已设为 ${selected.hex}。';
      _statusIsError = false;
    });
  }

  static RgbColor? _parseHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) return null;
    final number = int.parse(normalized, radix: 16);
    return RgbColor((number >> 16) & 0xFF, (number >> 8) & 0xFF, number & 0xFF);
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = true;
    });
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    return '操作失败：$error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildWorkspace()),
                    const SizedBox(width: 18),
                    SizedBox(width: 330, child: _buildSettings()),
                  ],
                ),
              ),
            ),
            _buildStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '白底人像',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'YOLO 本地识别 · HEIC 支持 · GPU 加速 · 照片不上传',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: const Color(0xFF667085)),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _chooseImage,
            child: Text(_sourceBytes == null ? '选择照片' : '更换照片'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _sourceBytes == null || _busy ? null : _processImage,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('自动换背景'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _PreviewPanel(
              title: '原图',
              bytes: _sourceBytes,
              emptyText: '选择一张人像照片',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _PreviewPanel(
              title: '背景效果',
              bytes: _processedBytes,
              emptyText: _sourceBytes == null ? '等待导入照片' : '等待自动处理',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Container(
      decoration: _panelDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '处理与导出',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('推理设备'),
                  DropdownButtonFormField<InferenceDevice>(
                    initialValue: _device,
                    items: InferenceDevice.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _device = value!),
                  ),
                  const SizedBox(height: 12),
                  _label('背景颜色'),
                  OutlinedButton(
                    onPressed: _busy ? null : _chooseBackgroundColor,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Color.fromARGB(
                              255,
                              _backgroundColor.red,
                              _backgroundColor.green,
                              _backgroundColor.blue,
                            ),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFFD0D5DD)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('选择颜色  ${_backgroundColor.hex}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _label('成品尺寸'),
                  DropdownButtonFormField<SizePreset>(
                    initialValue: _preset,
                    items: SizePreset.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : _applyPreset,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '宽度（px）',
                          ),
                          onChanged: (_) =>
                              setState(() => _preset = SizePreset.values.first),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '高度（px）',
                          ),
                          onChanged: (_) =>
                              setState(() => _preset = SizePreset.values.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ResizeMode>(
                    initialValue: _resizeMode,
                    decoration: const InputDecoration(labelText: '画面适配'),
                    items: ResizeMode.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _resizeMode = value!),
                  ),
                  const SizedBox(height: 12),
                  _label('文件格式与大小'),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<OutputFormat>(
                          initialValue: _format,
                          decoration: const InputDecoration(labelText: '格式'),
                          items: OutputFormat.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value.label),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _format = value!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _sizeController,
                          enabled: !_busy && _format == OutputFormat.jpeg,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '上限（KB）',
                            helperText: '0 = 不限制',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_segmentation != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '原始分辨率：${_segmentation!.width}×${_segmentation!.height}\n'
                      '当前设备：${_segmentation!.deviceLabel}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _processedBytes == null || _busy ? null : _exportImage,
            child: const Text('导出成品'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _exportedPath == null || _busy
                ? null
                : _showExportedFile,
            child: const Text('在文件夹中显示'),
          ),
        ],
      ),
    );
  }

  Widget _label(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF344054),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4E7EC)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A101828),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      color: _statusIsError ? const Color(0xFFFFF1F0) : const Color(0xFFEEF4FF),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      child: Text(
        _status,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _statusIsError
              ? const Color(0xFFB42318)
              : const Color(0xFF3538CD),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.title,
    required this.bytes,
    required this.emptyText,
  });

  final String title;
  final Uint8List? bytes;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: bytes == null
                ? Center(
                    child: Text(
                      emptyText,
                      style: const TextStyle(color: Color(0xFF98A2B3)),
                    ),
                  )
                : InteractiveViewer(
                    minScale: 0.7,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(
                        bytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(width: 36, child: Text(value.toString())),
      ],
    );
  }
}

class _ColorPreset extends StatelessWidget {
  const _ColorPreset({required this.color, required this.onTap});

  final RgbColor color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color.hex,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 42,
          height: 32,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, color.red, color.green, color.blue),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
        ),
      ),
    );
  }
}
