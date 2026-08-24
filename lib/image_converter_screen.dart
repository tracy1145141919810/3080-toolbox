import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'services/image_conversion_service.dart';

enum _ConversionStatus { waiting, converting, completed, failed }

class _ConversionItem {
  _ConversionItem({required this.path, required this.byteLength});

  final String path;
  final int byteLength;
  _ConversionStatus status = _ConversionStatus.waiting;
  String? outputPath;
  String? message;
  int? outputBytes;
}

class ImageConverterScreen extends StatefulWidget {
  const ImageConverterScreen({super.key});

  @override
  State<ImageConverterScreen> createState() => _ImageConverterScreenState();
}

class _ImageConverterScreenState extends State<ImageConverterScreen> {
  static const _blue = Color(0xFF2563EB);
  final _service = ImageConversionService();
  final _widthController = TextEditingController(text: '0');
  final _heightController = TextEditingController(text: '0');
  final _targetController = TextEditingController(text: '0');
  final List<_ConversionItem> _items = [];

  ImageOutputFormat _format = ImageOutputFormat.webp;
  double _quality = 88;
  bool _keepAspectRatio = true;
  bool _keepMetadata = false;
  bool _overwrite = false;
  bool _working = false;
  String? _outputDirectory;
  String? _runtimeVersion;

  @override
  void initState() {
    super.initState();
    _loadRuntimeVersion();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadRuntimeVersion() async {
    try {
      final value = await _service.version();
      if (mounted) setState(() => _runtimeVersion = value);
    } catch (_) {
      if (mounted) setState(() => _runtimeVersion = 'ImageMagick 运行库不可用');
    }
  }

  Future<void> _addFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '图片文件',
          extensions: ImageConversionService.supportedInputExtensions.toList(),
        ),
      ],
    );
    await _appendPaths(files.map((file) => file.path));
  }

  Future<void> _addFolder() async {
    final folder = await getDirectoryPath(confirmButtonText: '选择此文件夹');
    if (folder == null) return;
    final paths = <String>[];
    try {
      await for (final entity in Directory(
        folder,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File && _isSupported(entity.path)) paths.add(entity.path);
        if (paths.length >= 1000) break;
      }
      await _appendPaths(paths);
      if (paths.length >= 1000 && mounted) {
        _showMessage('单次最多加入 1000 张图片，已忽略其余文件。');
      }
    } catch (error) {
      if (mounted) _showMessage('无法读取文件夹：$error', error: true);
    }
  }

  Future<void> _appendPaths(Iterable<String> paths) async {
    final existing = _items.map((item) => p.canonicalize(item.path)).toSet();
    final additions = <_ConversionItem>[];
    for (final path in paths) {
      if (_items.length + additions.length >= 1000) break;
      if (!_isSupported(path) || !existing.add(p.canonicalize(path))) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      additions.add(
        _ConversionItem(path: path, byteLength: await file.length()),
      );
    }
    if (!mounted || additions.isEmpty) return;
    setState(() {
      _items.addAll(additions);
      _outputDirectory ??= p.join(p.dirname(additions.first.path), '转换结果');
    });
  }

  bool _isSupported(String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    return ImageConversionService.supportedInputExtensions.contains(extension);
  }

  Future<void> _chooseOutputDirectory() async {
    final selected = await getDirectoryPath(
      initialDirectory: _outputDirectory,
      confirmButtonText: '保存到此文件夹',
    );
    if (selected != null && mounted) {
      setState(() => _outputDirectory = selected);
    }
  }

  Future<void> _startConversion() async {
    if (_working || _items.isEmpty) return;
    if (_outputDirectory == null) {
      _showMessage('请先选择输出文件夹。', error: true);
      return;
    }
    final width = int.tryParse(_widthController.text.trim()) ?? -1;
    final height = int.tryParse(_heightController.text.trim()) ?? -1;
    final target = int.tryParse(_targetController.text.trim()) ?? -1;
    if (width < 0 || height < 0 || target < 0) {
      _showMessage('宽度、高度和目标大小必须是大于或等于 0 的整数。', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      for (final item in _items) {
        item
          ..status = _ConversionStatus.waiting
          ..message = null
          ..outputPath = null
          ..outputBytes = null;
      }
    });
    var succeeded = 0;
    for (final item in _items) {
      if (!mounted) return;
      setState(() => item.status = _ConversionStatus.converting);
      try {
        final result = await _service.convert(
          item.path,
          ImageConversionSettings(
            outputDirectory: _outputDirectory!,
            format: _format,
            quality: _quality.round(),
            width: width,
            height: height,
            keepAspectRatio: _keepAspectRatio,
            keepMetadata: _keepMetadata,
            overwrite: _overwrite,
            targetKilobytes: target,
          ),
        );
        succeeded++;
        if (!mounted) return;
        setState(() {
          item
            ..status = _ConversionStatus.completed
            ..outputPath = result.outputPath
            ..outputBytes = result.byteLength
            ..message = result.metTarget ? null : '已尽力压缩，仍高于目标大小';
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          item
            ..status = _ConversionStatus.failed
            ..message = _shortError(error);
        });
      }
    }
    if (!mounted) return;
    setState(() => _working = false);
    _showMessage('转换完成：$succeeded 成功，${_items.length - succeeded} 失败。');
  }

  String _shortError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  Future<void> _openOutputDirectory() async {
    final directory = _outputDirectory;
    if (directory == null) {
      _showMessage('尚未选择输出文件夹。', error: true);
      return;
    }
    await Directory(directory).create(recursive: true);
    await Process.start('explorer.exe', [directory]);
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB42318) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildFilePanel()),
                  const SizedBox(width: 18),
                  SizedBox(width: 346, child: _buildSettingsPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '图片格式转换',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                '主流格式批量转换 · HEIC/RAW 输入 · 尺寸与文件大小控制 · 全程本地处理',
                style: TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _working ? null : _addFolder,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('添加文件夹'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _working ? null : _addFiles,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('添加图片'),
        ),
      ],
    );
  }

  Widget _buildFilePanel() {
    return _Panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 10, 12),
            child: Row(
              children: [
                Text(
                  '待转换文件（${_items.length}）',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _working || _items.isEmpty
                      ? null
                      : () => setState(_items.clear),
                  child: const Text('清空列表'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _buildFileRow(index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.collections_outlined,
            size: 52,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(height: 14),
          const Text(
            '还没有待转换的图片',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '可添加单张、多张，或扫描整个文件夹（最多 1000 张）',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _addFiles, child: const Text('选择图片')),
        ],
      ),
    );
  }

  Widget _buildFileRow(int index) {
    final item = _items[index];
    final statusColor = switch (item.status) {
      _ConversionStatus.waiting => const Color(0xFF667085),
      _ConversionStatus.converting => _blue,
      _ConversionStatus.completed => const Color(0xFF039855),
      _ConversionStatus.failed => const Color(0xFFD92D20),
    };
    final statusLabel = switch (item.status) {
      _ConversionStatus.waiting => '等待中',
      _ConversionStatus.converting => '正在转换',
      _ConversionStatus.completed => '已完成',
      _ConversionStatus.failed => '失败',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              p.extension(item.path).replaceFirst('.', '').toUpperCase(),
              style: const TextStyle(
                color: _blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(item.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message ??
                      '${_formatBytes(item.byteLength)}${item.outputBytes == null ? '' : ' → ${_formatBytes(item.outputBytes!)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: item.message == null
                        ? const Color(0xFF667085)
                        : statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 76,
            child: Row(
              children: [
                if (item.status == _ConversionStatus.converting)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.circle, size: 9, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(fontSize: 12, color: statusColor),
                ),
              ],
            ),
          ),
          Tooltip(
            message: '从列表移除',
            child: IconButton(
              onPressed: _working
                  ? null
                  : () => setState(() => _items.removeAt(index)),
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return _Panel(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '输出设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const _FieldLabel('输出格式'),
            const SizedBox(height: 7),
            DropdownButtonFormField<ImageOutputFormat>(
              initialValue: _format,
              items: ImageOutputFormat.values
                  .map(
                    (format) => DropdownMenuItem(
                      value: format,
                      child: Text('${format.label} (.${format.extension})'),
                    ),
                  )
                  .toList(),
              onChanged: _working
                  ? null
                  : (value) => setState(() => _format = value ?? _format),
            ),
            if (_format.lossy) ...[
              const SizedBox(height: 15),
              Row(
                children: [
                  const _FieldLabel('画质'),
                  const Spacer(),
                  Text(
                    '${_quality.round()}',
                    style: const TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _quality,
                min: 20,
                max: 100,
                divisions: 80,
                onChanged: _working
                    ? null
                    : (value) => setState(() => _quality = value),
              ),
            ],
            const SizedBox(height: 10),
            const _FieldLabel('输出分辨率（0 = 保持原始）'),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _widthController,
                    enabled: !_working,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: '宽'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×', style: TextStyle(color: Color(0xFF667085))),
                ),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    enabled: !_working,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: '高'),
                  ),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('保持宽高比'),
              value: _keepAspectRatio,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _keepAspectRatio = value),
            ),
            const SizedBox(height: 5),
            const _FieldLabel('目标文件大小（0 = 不限制）'),
            const SizedBox(height: 7),
            TextField(
              controller: _targetController,
              enabled: !_working && _format.lossy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: 'KB',
                helperText: _format.lossy ? '程序会逐步降低画质以接近目标' : '当前格式不支持按体积压缩',
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('保留 EXIF 等元数据'),
              value: _keepMetadata,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _keepMetadata = value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('覆盖同名文件'),
              value: _overwrite,
              onChanged: _working
                  ? null
                  : (value) => setState(() => _overwrite = value),
            ),
            const Divider(height: 24),
            const _FieldLabel('保存位置'),
            const SizedBox(height: 7),
            OutlinedButton(
              onPressed: _working ? null : _chooseOutputDirectory,
              child: Text(
                _outputDirectory == null
                    ? '选择输出文件夹'
                    : p.basename(_outputDirectory!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_outputDirectory != null) ...[
              const SizedBox(height: 5),
              Text(
                _outputDirectory!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
              ),
            ],
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: _working || _items.isEmpty ? null : _startConversion,
              icon: _working
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_working ? '正在转换…' : '开始转换'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _working ? null : _openOutputDirectory,
              child: const Text('在文件夹中显示'),
            ),
            const SizedBox(height: 13),
            Text(
              _runtimeVersion ?? '正在检测 ImageMagick…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFF98A2B3)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE4E7EC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
