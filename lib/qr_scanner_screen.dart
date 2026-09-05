import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/qr_scanner_service.dart';

typedef QrImagePicker = Future<String?> Function();
typedef QrFileScanner = Future<QrScanPayload> Function(String path);
typedef QrScreenScanner = Future<QrScanPayload?> Function();

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    this.imagePicker,
    this.fileScanner,
    this.screenScanner,
  });

  final QrImagePicker? imagePicker;
  final QrFileScanner? fileScanner;
  final QrScreenScanner? screenScanner;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _service = const QrScannerService();
  QrScanPayload? _payload;
  bool _busy = false;
  String? _error;
  String _status = '等待扫描';

  Future<String?> _pickImage() async {
    const group = XTypeGroup(
      label: '二维码图片',
      extensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp', 'gif'],
    );
    return (await openFile(acceptedTypeGroups: [group]))?.path;
  }

  Future<void> _scanScreen() async {
    if (_busy) return;
    await _runScan(() async {
      final payload = await (widget.screenScanner ?? _service.scanScreen)
          .call();
      if (payload == null) {
        if (mounted) {
          setState(() => _status = '已取消屏幕框选 · 原有结果未改变');
        }
        return null;
      }
      return payload;
    }, busyStatus: '工具箱即将隐藏，请框选屏幕上的二维码区域…');
  }

  Future<void> _importImage() async {
    if (_busy) return;
    final path = await (widget.imagePicker ?? _pickImage).call();
    if (path == null) return;
    await _runScan(
      () => (widget.fileScanner ?? _service.scanFile).call(path),
      busyStatus: '正在读取图片并识别二维码…',
    );
  }

  Future<void> _runScan(
    Future<QrScanPayload?> Function() operation, {
    required String busyStatus,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = busyStatus;
    });
    try {
      final payload = await operation();
      if (!mounted || payload == null) return;
      setState(() {
        _payload = payload;
        _status = payload.results.isEmpty
            ? '扫描完成，但没有识别到二维码'
            : '扫描完成 · 找到 ${payload.results.length} 个二维码';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '扫描失败：${_friendlyError(error)}';
        _status = '扫描失败 · 请重新框选或换一张更清晰的图片';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    return text
        .replaceFirst('Exception: ', '')
        .replaceFirst('FormatException: ', '')
        .replaceFirst('PlatformException', '系统调用失败');
  }

  Future<void> _copy(String text, {String message = '内容已复制'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyAll() async {
    final results = _payload?.results ?? const <QrDecodedContent>[];
    if (results.isEmpty) return;
    await _copy(
      results.map((result) => result.text).join('\n\n'),
      message: '已复制全部 ${results.length} 条结果',
    );
  }

  Future<void> _openLink(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法调用默认浏览器，请复制链接后手动打开')));
    }
  }

  void _clear() {
    setState(() {
      _payload = null;
      _error = null;
      _status = '结果已清空 · 等待新的屏幕框选或图片';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final inset = compact ? 16.0 : 28.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(inset, compact ? 16 : 24, inset, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(compact),
                  const SizedBox(height: 16),
                  _buildStatus(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildError(),
                  ],
                  const SizedBox(height: 18),
                  if (_payload == null) _buildWelcome() else _buildScanResult(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '二维码扫描',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          key: const ValueKey('scan-screen-qr'),
          onPressed: _busy ? null : _scanScreen,
          icon: const Icon(Icons.crop_free_rounded),
          label: const Text('扫描屏幕二维码'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('import-qr-image'),
          onPressed: _busy ? null : _importImage,
          icon: const Icon(Icons.image_outlined),
          label: const Text('导入图片'),
        ),
        if (_payload != null)
          OutlinedButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('清空结果'),
          ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 14), buttons],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        const SizedBox(width: 18),
        buttons,
      ],
    );
  }

  Widget _buildStatus() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: _error == null
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _error == null
              ? const Color(0xFF93C5FD)
              : const Color(0xFFFDA29B),
        ),
      ),
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            )
          else
            Icon(
              _error == null
                  ? Icons.qr_code_scanner_rounded
                  : Icons.error_outline_rounded,
              color: _error == null
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFD92D20),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              key: const ValueKey('qr-scan-status'),
              style: TextStyle(
                color: _error == null
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFFB42318),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEC84B)),
      ),
      child: Text(_error!, style: const TextStyle(color: Color(0xFF93370D))),
    );
  }

  Widget _buildWelcome() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4E7EC)),
    ),
    child: const Center(child: Text('暂无识别结果')),
  );

  Widget _buildScanResult() {
    final payload = _payload!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = _buildPreview(payload);
        final results = _buildResults(payload);
        if (constraints.maxWidth < 900) {
          return Column(
            children: [preview, const SizedBox(height: 18), results],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 430, child: preview),
            const SizedBox(width: 18),
            Expanded(child: results),
          ],
        );
      },
    );
  }

  Widget _buildPreview(QrScanPayload payload) {
    return _QrPanel(
      title: '扫描图像',
      subtitle: '${payload.sourceLabel} · ${payload.width} × ${payload.height}',
      icon: Icons.image_outlined,
      child: Container(
        key: const ValueKey('qr-preview'),
        width: double.infinity,
        height: 360,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD0D5DD)),
        ),
        child: Image.memory(payload.previewPng, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildResults(QrScanPayload payload) {
    final results = payload.results;
    return _QrPanel(
      title: results.isEmpty ? '没有识别到二维码' : '识别结果',
      subtitle: results.isEmpty
          ? '请尽量只框选二维码，并确保图像清晰、边缘留有少量空白。'
          : '共 ${results.length} 条 · 解码 ${payload.durationMs} ms · 最多识别 10 条',
      icon: results.isEmpty ? Icons.search_off_rounded : Icons.task_alt_rounded,
      trailing: results.isEmpty
          ? null
          : OutlinedButton.icon(
              onPressed: _copyAll,
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制全部'),
            ),
      child: results.isEmpty
          ? const SizedBox(
              height: 290,
              child: Center(
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFF98A2B3),
                  size: 82,
                ),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < results.length; index++) ...[
                  _ResultCard(
                    index: index,
                    result: results[index],
                    onCopy: () => _copy(results[index].text),
                    onOpen: results[index].webUri == null
                        ? null
                        : () => _openLink(results[index].webUri!),
                  ),
                  if (index != results.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2563EB)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.index,
    required this.result,
    required this.onCopy,
    required this.onOpen,
  });

  final int index;
  final QrDecodedContent result;
  final VoidCallback onCopy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('qr-result-$index'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D5DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result.contentType,
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                result.format,
                style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
              const Spacer(),
              if (result.isInverted || result.isMirrored)
                const Tooltip(
                  message: '已自动处理反色或镜像二维码',
                  child: Icon(
                    Icons.auto_fix_high_rounded,
                    size: 18,
                    color: Color(0xFF7F56D9),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            result.text,
            style: const TextStyle(
              color: Color(0xFF101828),
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制内容'),
              ),
              if (onOpen != null)
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('用浏览器打开'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
