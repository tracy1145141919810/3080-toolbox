import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'services/gif_export_service.dart';
import 'services/screen_capture_service.dart';

class GifRecorderScreen extends StatefulWidget {
  const GifRecorderScreen({super.key});

  @override
  State<GifRecorderScreen> createState() => _GifRecorderScreenState();
}

class _GifRecorderScreenState extends State<GifRecorderScreen> {
  static const _captureService = ScreenCaptureService();
  static const _gifService = GifExportService();

  final _targetSizeController = TextEditingController(text: '0');
  final List<RecordedScreenFrame> _frames = [];
  final List<Uint8List> _thumbnails = [];
  Timer? _timer;
  ScreenRegion? _region;
  Uint8List? _preview;
  Stopwatch? _stopwatch;
  int _selectedFrame = -1;
  int _fps = 5;
  int _durationSeconds = 5;
  int _scalePercent = 100;
  int _colors = 128;
  bool _includeCursor = true;
  bool _recording = false;
  bool _paused = false;
  bool _capturing = false;
  bool _exporting = false;
  bool _transitioning = false;
  bool _stopping = false;
  int _generation = 0;
  int _previewRequest = 0;
  int _recordedFps = 5;
  bool get _locked => _recording || _transitioning || _exporting;
  String _status = '选择屏幕区域后即可开始录制。';
  String? _exportedPath;

  int get _effectiveFps => _durationSeconds >= 180 ? math.min(_fps, 5) : _fps;

  @override
  void initState() {
    super.initState();
    _captureService.setRecordingIndicatorCallback(_pauseAndShowToolbox);
  }

  @override
  void dispose() {
    _generation++;
    _previewRequest++;
    _recording = false;
    _timer?.cancel();
    _captureService.setRecordingIndicatorCallback(null);
    unawaited(_captureService.hideRecordingIndicator());
    unawaited(_captureService.setToolboxVisible(true));
    _targetSizeController.dispose();
    super.dispose();
  }

  Future<void> _selectRegion() async {
    if (_locked) return;
    setState(() => _transitioning = true);
    try {
      final selected = await _captureService.selectRegion();
      if (!mounted || selected == null) return;
      setState(() {
        _region = selected;
        _status = '已选择 ${selected.width} × ${selected.height} 区域。';
      });
    } catch (error) {
      _showError('无法选择区域：$error');
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  (int, int) _captureDimensions(ScreenRegion region) {
    final maxWidth = _durationSeconds > 60 ? 640 : 960;
    final maxHeight = _durationSeconds > 60 ? 360 : 540;
    final ratio = math.min(
      1.0,
      math.min(maxWidth / region.width, maxHeight / region.height),
    );
    return (
      math.max(1, (region.width * ratio).round()),
      math.max(1, (region.height * ratio).round()),
    );
  }

  Future<void> _startRecording() async {
    if (_locked) return;
    if (_region == null) {
      await _selectRegion();
      if (_region == null || !mounted) return;
    }
    _timer?.cancel();
    final generation = ++_generation;
    _previewRequest++;
    _recordedFps = _effectiveFps;
    _frames.clear();
    _thumbnails.clear();
    _lastIndicatorSecond = -1;
    _stopwatch = Stopwatch();
    setState(() {
      _transitioning = true;
      _recording = true;
      _paused = false;
      _selectedFrame = -1;
      _preview = null;
      _exportedPath = null;
      _status = '正在录制 · 0 帧';
    });
    try {
      await _captureService.showRecordingIndicator(
        _indicatorText(),
        region: _region,
      );
      if (!mounted || generation != _generation) return;
      await _captureService.setToolboxVisible(false);
      if (!mounted || generation != _generation) return;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || generation != _generation) return;
      _stopwatch?.start();
      await _captureFrame();
      if (!mounted || generation != _generation || !_recording) return;
      _timer = Timer.periodic(
        Duration(milliseconds: (1000 / _recordedFps).round()),
        (_) => _captureTick(),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        _recording = false;
        await _captureService.hideRecordingIndicator();
        await _captureService.setToolboxVisible(true);
        _showError('无法开始录制：$error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _transitioning = false);
      }
    }
  }

  Future<void> _captureTick() async {
    if (!_recording || _paused || _capturing) return;
    if ((_stopwatch?.elapsedMilliseconds ?? 0) >= _durationSeconds * 1000) {
      await _stopRecording();
      return;
    }
    final elapsedSeconds = (_stopwatch?.elapsedMilliseconds ?? 0) ~/ 1000;
    if (elapsedSeconds != _lastIndicatorSecond) {
      _lastIndicatorSecond = elapsedSeconds;
      unawaited(_captureService.updateRecordingIndicator(_indicatorText()));
    }
    await _captureFrame();
  }

  int _lastIndicatorSecond = -1;

  String _indicatorText() {
    final elapsed = (_stopwatch?.elapsedMilliseconds ?? 0) ~/ 1000;
    String clock(int seconds) =>
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return _paused
        ? '录制已暂停 · 返回工具箱操作'
        : '录制中 ${clock(elapsed)} / ${clock(_durationSeconds)} · 点击暂停';
  }

  Future<void> _captureFrame() async {
    final region = _region;
    final generation = _generation;
    if (region == null || _capturing) return;
    _capturing = true;
    try {
      final (width, height) = _captureDimensions(region);
      final rawFrame = await _captureService.capture(
        region,
        outputWidth: width,
        outputHeight: height,
        includeCursor: _includeCursor,
      );
      if (!mounted || !_recording || _paused || generation != _generation) {
        return;
      }
      final frame = await _gifService.compressFrame(rawFrame);
      if (!mounted || !_recording || _paused || generation != _generation) {
        return;
      }
      _frames.add(frame);
      setState(() {
        _status = '正在录制 · ${_frames.length} 帧';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        await _stopRecording();
        _showError('屏幕录制失败：$error');
      }
    } finally {
      _capturing = false;
    }
  }

  Future<void> _pauseAndShowToolbox() async {
    if (!mounted || !_recording || _transitioning) return;
    if (!_paused) {
      _stopwatch?.stop();
      setState(() {
        _paused = true;
        _status = '录制已暂停 · ${_frames.length} 帧';
      });
      await _captureService.updateRecordingIndicator(_indicatorText());
    }
    await _captureService.setToolboxVisible(true);
  }

  Future<void> _togglePause() async {
    if (!mounted || !_recording || _transitioning) return;
    final generation = _generation;
    if (!_paused) {
      await _pauseAndShowToolbox();
      return;
    }
    setState(() {
      _paused = false;
      _stopwatch?.start();
      _status = '正在录制 · ${_frames.length} 帧';
    });
    await _captureService.updateRecordingIndicator(_indicatorText());
    if (!mounted || generation != _generation) return;
    await _captureService.setToolboxVisible(false);
  }

  Future<void> _stopRecording() async {
    if (!mounted || !_recording || _stopping) return;
    final generation = ++_generation;
    _previewRequest++;
    setState(() {
      _recording = false;
      _transitioning = true;
      _stopping = true;
    });
    _timer?.cancel();
    _stopwatch?.stop();
    final frames = List<RecordedScreenFrame>.of(_frames);
    try {
      await _captureService.hideRecordingIndicator();
      await _captureService.setToolboxVisible(true);
      if (!mounted || generation != _generation) return;
      setState(() {
        _recording = false;
        _paused = false;
        _status = _frames.isEmpty ? '没有捕获到画面。' : '正在生成帧预览…';
      });
      if (frames.isEmpty) return;
      final previews = await _gifService.createThumbnails(frames);
      final preview = await _gifService.createPreview(frames.last);
      if (!mounted || generation != _generation) return;
      setState(() {
        _thumbnails
          ..clear()
          ..addAll(previews);
        _preview = preview;
        _selectedFrame = _frames.length - 1;
        _status = '录制完成 · ${_frames.length} 帧，可删除不需要的帧后导出。';
      });
    } catch (error) {
      _showError('生成录制预览失败：$error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _transitioning = false;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _selectFrame(int index) async {
    if (_locked || index < 0 || index >= _frames.length) return;
    final request = ++_previewRequest;
    final preview = await _gifService.createPreview(_frames[index]);
    if (!mounted || request != _previewRequest) return;
    setState(() {
      _selectedFrame = index;
      _preview = preview;
    });
  }

  Future<void> _deleteSelectedFrame() async {
    if (_selectedFrame < 0 || _locked) return;
    final index = _selectedFrame;
    _frames.removeAt(index);
    _thumbnails.removeAt(index);
    if (_frames.isEmpty) {
      setState(() {
        _selectedFrame = -1;
        _preview = null;
        _status = '帧已全部删除，可重新录制。';
      });
      return;
    }
    await _selectFrame(math.min(index, _frames.length - 1));
    if (mounted) setState(() => _status = '已删除 1 帧，剩余 ${_frames.length} 帧。');
  }

  void _clearFrames() {
    if (_locked || _frames.isEmpty) return;
    _previewRequest++;
    setState(() {
      _frames.clear();
      _thumbnails.clear();
      _selectedFrame = -1;
      _preview = null;
      _exportedPath = null;
      _status = '帧已清空，可重新录制。';
    });
  }

  Future<void> _exportGif() async {
    if (_frames.isEmpty || _locked) return;
    final target = int.tryParse(_targetSizeController.text.trim());
    if (target == null || target < 0) {
      _showError('目标大小请输入 0 或正整数。');
      return;
    }
    setState(() => _exporting = true);
    final frames = List<RecordedScreenFrame>.of(_frames);
    try {
      final location = await getSaveLocation(
        suggestedName: '3080录屏_${DateTime.now().millisecondsSinceEpoch}.gif',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'GIF 动图', extensions: ['gif']),
        ],
      );
      if (location == null || !mounted) return;
      setState(() {
        _exporting = true;
        _status = '正在本地编码 GIF…';
      });
      final result = await _gifService.encode(
        frames,
        GifExportSettings(
          framesPerSecond: _recordedFps,
          colors: _colors,
          scalePercent: _scalePercent,
          targetKilobytes: target,
        ),
      );
      var outputPath = location.path;
      if (p.extension(outputPath).toLowerCase() != '.gif') {
        outputPath = '$outputPath.gif';
      }
      await File(outputPath).writeAsBytes(result.bytes, flush: true);
      if (!mounted) return;
      final size = (result.bytes.length / 1024).toStringAsFixed(1);
      setState(() {
        _exportedPath = outputPath;
        _status = result.metTarget
            ? '导出成功 · ${result.width} × ${result.height} · $size KB'
            : '已导出最小可用结果 · $size KB（未达到设定上限）';
      });
    } catch (error) {
      _showError('GIF 导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showExportedFile() async {
    final outputPath = _exportedPath;
    if (outputPath == null || !File(outputPath).existsSync()) return;
    await Process.run('explorer.exe', ['/select,', outputPath]);
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildPreviewPanel()),
                  const SizedBox(width: 18),
                  SizedBox(width: 324, child: _buildSettingsPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GIF录屏',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: _locked ? null : _selectRegion,
          icon: const Icon(Icons.crop_free_rounded),
          label: const Text('选择录制区域'),
        ),
        const SizedBox(width: 10),
        if (!_recording)
          FilledButton.icon(
            onPressed: _locked ? null : _startRecording,
            icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
            label: const Text('开始录制'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _transitioning ? null : _togglePause,
            icon: Icon(
              _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            label: Text(_paused ? '继续' : '暂停'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD92D20),
            ),
            onPressed: _transitioning ? null : _stopRecording,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('停止录制'),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 650
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                actions,
              ],
            ),
    );
  }

  Widget _buildPreviewPanel() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '录制预览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                _region == null
                    ? '未选择区域'
                    : '${_region!.x}, ${_region!.y} · ${_region!.width} × ${_region!.height}',
                style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF101828),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _preview == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _recording
                              ? Icons.fiber_manual_record_rounded
                              : Icons.desktop_windows_outlined,
                          color: _recording
                              ? const Color(0xFFF04438)
                              : const Color(0xFF98A2B3),
                          size: 46,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _recording ? '正在捕获屏幕…' : '暂无录制内容',
                          style: const TextStyle(color: Color(0xFFD0D5DD)),
                        ),
                      ],
                    )
                  : Image.memory(
                      _preview!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final label = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '帧时间线',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_frames.length} 帧',
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _selectedFrame >= 0 && !_locked
                        ? _deleteSelectedFrame
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    label: const Text('删除所选帧'),
                  ),
                  TextButton(
                    onPressed: _frames.isNotEmpty && !_locked
                        ? _clearFrames
                        : null,
                    child: const Text('清空'),
                  ),
                ],
              );
              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(children: [label, const Spacer(), actions]);
            },
          ),
          SizedBox(
            height: 82,
            child: _thumbnails.isEmpty
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    child: const Text(
                      '尚无帧',
                      style: TextStyle(color: Color(0xFF98A2B3)),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _thumbnails.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => InkWell(
                      onTap: () => _selectFrame(index),
                      child: Container(
                        width: 116,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedFrame == index
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFE4E7EC),
                            width: _selectedFrame == index ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Image.memory(
                                _thumbnails[index],
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              left: 4,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                color: const Color(0xB3000000),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return _Panel(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '录制设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _SettingLabel('帧率'),
            DropdownButtonFormField<int>(
              initialValue: _fps,
              items: const [5, 10, 15]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value FPS'),
                    ),
                  )
                  .toList(),
              onChanged: _recording
                  ? null
                  : (value) => setState(() => _fps = value!),
            ),
            const SizedBox(height: 13),
            _SettingLabel('最长录制时间'),
            DropdownButtonFormField<int>(
              initialValue: _durationSeconds,
              items: const [5, 15, 30, 60, 180, 300]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value < 60 ? '$value 秒' : '${value ~/ 60} 分钟',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _recording
                  ? null
                  : (value) => setState(() => _durationSeconds = value!),
            ),
            if (_durationSeconds >= 180) ...[
              const SizedBox(height: 7),
              const Text(
                '长录制自动使用最高 5 FPS 与压缩帧缓存，最长支持 5 分钟。',
                style: TextStyle(color: Color(0xFF667085), fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('录制鼠标指针', style: TextStyle(fontSize: 14)),
              value: _includeCursor,
              onChanged: _recording
                  ? null
                  : (value) => setState(() => _includeCursor = value),
            ),
            const Divider(height: 26),
            const Text(
              '导出设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _SettingLabel('输出分辨率'),
            DropdownButtonFormField<int>(
              initialValue: _scalePercent,
              items: const [100, 75, 50]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text('$value%')),
                  )
                  .toList(),
              onChanged: _exporting
                  ? null
                  : (value) => setState(() => _scalePercent = value!),
            ),
            const SizedBox(height: 13),
            _SettingLabel('GIF 色彩'),
            DropdownButtonFormField<int>(
              initialValue: _colors,
              items: const [64, 128, 256]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text('$value 色')),
                  )
                  .toList(),
              onChanged: _exporting
                  ? null
                  : (value) => setState(() => _colors = value!),
            ),
            const SizedBox(height: 13),
            _SettingLabel('目标文件大小上限（KB）'),
            TextField(
              controller: _targetSizeController,
              enabled: !_exporting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0 表示不限制',
                suffixText: 'KB',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _frames.isNotEmpty && !_locked ? _exportGif : null,
              icon: _exporting
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(_exporting ? '正在编码' : '导出 GIF'),
            ),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _exportedPath == null ? null : _showExportedFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('在文件夹中显示'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  color: Color(0xFF475467),
                  height: 1.45,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
