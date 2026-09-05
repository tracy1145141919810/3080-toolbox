import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/hardware_detection_service.dart';
import 'services/hardware_monitor_service.dart';

typedef HardwareSnapshotLoader = Future<HardwareSnapshot> Function();

class HardwareDetectionScreen extends StatefulWidget {
  const HardwareDetectionScreen({
    super.key,
    this.loader,
    this.telemetryStreamFactory,
    this.onDetected,
  });

  final HardwareSnapshotLoader? loader;
  final HardwareTelemetryStreamFactory? telemetryStreamFactory;
  final ValueChanged<HardwareSnapshot>? onDetected;

  @override
  State<HardwareDetectionScreen> createState() =>
      _HardwareDetectionScreenState();
}

class _HardwareDetectionScreenState extends State<HardwareDetectionScreen> {
  HardwareSnapshot? _snapshot;
  String? _error;
  bool _detecting = true;
  HardwareMonitorService? _monitor;
  StreamSubscription<HardwareTelemetry>? _telemetrySubscription;
  HardwareTelemetry? _telemetry;
  String? _telemetryError;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
    _detect();
  }

  @override
  void dispose() {
    unawaited(_stopMonitoring());
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    await _stopMonitoring();
    if (!mounted) return;
    setState(() {
      _telemetry = null;
      _telemetryError = null;
    });
    Stream<HardwareTelemetry> stream;
    if (widget.telemetryStreamFactory != null) {
      stream = widget.telemetryStreamFactory!();
    } else {
      final monitor = HardwareMonitorService();
      _monitor = monitor;
      stream = monitor.watch();
    }
    _telemetrySubscription = stream.listen(
      (sample) {
        if (!mounted) return;
        setState(() {
          _telemetry = sample;
          _telemetryError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _telemetryError = _shortError(error));
      },
    );
  }

  Future<void> _stopMonitoring() async {
    await _telemetrySubscription?.cancel();
    _telemetrySubscription = null;
    await _monitor?.dispose();
    _monitor = null;
  }

  Future<void> _refreshAll() async {
    unawaited(_startMonitoring());
    await _detect();
  }

  Future<void> _detect() async {
    if (_detecting && _snapshot != null) return;
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final snapshot =
          await (widget.loader ?? const HardwareDetectionService().detect)();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      widget.onDetected?.call(snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _shortError(error));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _copyReport() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await Clipboard.setData(ClipboardData(text: snapshot.toReport()));
    if (mounted) _showMessage('硬件报告已复制到剪贴板。');
  }

  Future<void> _exportReport() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final safeName = snapshot.computerName.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
    final location = await getSaveLocation(
      suggestedName: '3080硬件报告-$safeName.txt',
      acceptedTypeGroups: const [
        XTypeGroup(label: '文本报告', extensions: ['txt']),
      ],
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.txt')) path = '$path.txt';
    await File(path)
        .writeAsString(snapshot.toReport(), encoding: utf8, flush: true);
    if (mounted) _showMessage('硬件报告已导出。');
  }

  String _shortError(Object error) {
    final text = switch (error) {
      StateError() => error.message,
      FormatException() => error.message,
      _ => '$error',
    };
    final oneLine = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return oneLine.length > 180 ? '${oneLine.substring(0, 180)}…' : oneLine;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final inset = compact ? 16.0 : 28.0;
        return ColoredBox(
          color: const Color(0xFFF5F7FA),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, compact ? 16 : 24, inset, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(compact),
                  SizedBox(height: compact ? 14 : 20),
                  Expanded(
                    child: _detecting && _snapshot == null
                        ? _buildLoading()
                        : _error != null && _snapshot == null
                        ? _buildError()
                        : _buildResults(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '硬件检测',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _snapshot == null || _detecting ? null : _copyReport,
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('复制报告'),
        ),
        OutlinedButton.icon(
          onPressed: _snapshot == null || _detecting ? null : _exportReport,
          icon: const Icon(Icons.description_outlined),
          label: const Text('导出 TXT'),
        ),
        FilledButton.icon(
          onPressed: _detecting ? null : _refreshAll,
          icon: _detecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(_detecting ? '检测中…' : '重新检测'),
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 12), actions],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 18),
        actions,
      ],
    );
  }

  Widget _buildLoading() {
    return const _StatePanel(
      icon: Icons.memory_rounded,
      title: '正在读取本机硬件信息',
      description: '请稍候',
      loading: true,
    );
  }

  Widget _buildError() {
    return _StatePanel(
      icon: Icons.error_outline_rounded,
      title: '硬件检测未完成',
      description: _error ?? '发生未知错误',
      action: FilledButton(
        onPressed: _detecting ? null : _detect,
        child: const Text('重试检测'),
      ),
    );
  }

  Widget _buildResults() {
    final snapshot = _snapshot!;
    final telemetry = _telemetry;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 820
                  ? 3
                  : constraints.maxWidth >= 540
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 14)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: width,
                    child: _HardwareSummaryCard(
                      icon: Icons.memory_rounded,
                      title: 'CPU 实时',
                      headline: _percentage(telemetry?.cpuUsagePercent),
                      detail: telemetry == null
                          ? '正在建立实时监测…'
                          : '当前频率 ${_frequency(telemetry.cpuFrequencyMhz)} · 每秒更新',
                      progress: _progress(telemetry?.cpuUsagePercent),
                      colors: const [Color(0xFF1D4ED8), Color(0xFF0891B2)],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HardwareSummaryCard(
                      icon: Icons.speed_rounded,
                      title: 'GPU 实时',
                      headline: _percentage(telemetry?.gpuUsagePercent),
                      detail: telemetry == null
                          ? '正在建立实时监测…'
                          : _gpuDetails(telemetry),
                      progress: _progress(telemetry?.gpuUsagePercent),
                      colors: const [Color(0xFF4338CA), Color(0xFF2563EB)],
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HardwareSummaryCard(
                      icon: Icons.storage_rounded,
                      title: '内存实时',
                      headline: _percentage(telemetry?.memoryUsagePercent),
                      detail: telemetry == null
                          ? '正在建立实时监测…'
                          : '已用 ${_decimal(telemetry.memoryUsedGb)} / '
                                '${_decimal(telemetry.memoryTotalGb)} GB · 每秒更新',
                      progress: _progress(telemetry?.memoryUsagePercent),
                      colors: const [Color(0xFF0369A1), Color(0xFF059669)],
                    ),
                  ),
                ],
              );
            },
          ),
          if (_detecting) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildWarning(_error!),
          ],
          if (_telemetryError != null) ...[
            const SizedBox(height: 12),
            _buildWarning('实时监测暂不可用：$_telemetryError'),
          ],
          const SizedBox(height: 18),
          _HardwareDetailsPanel(rows: _detailRows(snapshot)),
        ],
      ),
    );
  }

  String _percentage(double? value) {
    if (value == null) return '-- %';
    return '${value.clamp(0, 100).round()} %';
  }

  double _progress(double? value) => (value ?? 0).clamp(0, 100) / 100;

  String _frequency(double? mhz) {
    if (mhz == null) return '未知';
    return '${(mhz / 1000).toStringAsFixed(2)} GHz';
  }

  String _decimal(double? value, {int digits = 1}) {
    return value == null ? '未知' : value.toStringAsFixed(digits);
  }

  String _gpuDetails(HardwareTelemetry telemetry) {
    final parts = <String>[];
    if (telemetry.gpuTemperatureCelsius != null) {
      parts.add('${telemetry.gpuTemperatureCelsius!.round()} °C');
    }
    if (telemetry.gpuMemoryUsedMb != null &&
        telemetry.gpuMemoryTotalMb != null) {
      parts.add(
        '显存 ${_decimal(telemetry.gpuMemoryUsedMb! / 1024)} / '
        '${_decimal(telemetry.gpuMemoryTotalMb! / 1024)} GB',
      );
    }
    if (telemetry.gpuPowerWatts != null) {
      parts.add('${telemetry.gpuPowerWatts!.round()} W');
    }
    parts.add('每秒更新');
    return parts.join(' · ');
  }

  List<_HardwareDetailRow> _detailRows(HardwareSnapshot snapshot) {
    String values(String id, {bool physicalOnly = false}) {
      final section = snapshot.section(id);
      if (section == null || section.items.isEmpty) return '未知';
      final items = physicalOnly
          ? section.items.where((item) => item.label.startsWith('物理磁盘'))
          : section.items;
      final result = items.map((item) => item.value).toList();
      return result.isEmpty ? '未知' : result.join('\n');
    }

    final cpu = snapshot.value('cpu', '处理器');
    final cores = snapshot.value('cpu', '核心 / 线程');
    final board =
        '${snapshot.value('board', '主板厂商')} '
        '${snapshot.value('board', '主板型号')}';
    final memory = snapshot.value('memory', '已安装内存');
    final modules = snapshot
        .section('memory')
        ?.items
        .where((item) => item.label.startsWith('内存条'))
        .map((item) => item.value)
        .join(' + ');
    final gpuItems = snapshot.section('gpu')?.items ?? [];
    return [
      _HardwareDetailRow('处理器', '$cpu · $cores'),
      _HardwareDetailRow('主板', board.trim()),
      _HardwareDetailRow(
        '内存',
        modules == null || modules.isEmpty ? memory : '$memory（$modules）',
      ),
      if (gpuItems.isEmpty) const _HardwareDetailRow('显卡', '未知'),
      for (final item in gpuItems)
        _HardwareDetailRow(
          item.label,
          RegExp(r'^显卡 \d+$').hasMatch(item.label) &&
                  RegExp(
                    r'RTX\s*3080\b',
                    caseSensitive: false,
                  ).hasMatch(item.value)
              ? '老牧师3080'
              : item.value,
          highlight:
              RegExp(r'^显卡 \d+$').hasMatch(item.label) &&
              RegExp(
                r'RTX\s*3080\b',
                caseSensitive: false,
              ).hasMatch(item.value),
        ),
      _HardwareDetailRow('显示器', values('monitor')),
      _HardwareDetailRow('磁盘', values('storage', physicalOnly: true)),
      _HardwareDetailRow('声卡', values('audio')),
      _HardwareDetailRow('网卡', values('network')),
    ];
  }

  Widget _buildWarning(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFEC84B)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF7A2E0E))),
    );
  }
}

class _HardwareDetailRow {
  const _HardwareDetailRow(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

class _HardwareSummaryCard extends StatelessWidget {
  const _HardwareSummaryCard({
    required this.icon,
    required this.title,
    required this.headline,
    required this.detail,
    required this.progress,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String headline;
  final String detail;
  final double progress;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 164),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F2563EB),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF67E8F9), size: 27),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LiveDot(),
                    SizedBox(width: 5),
                    Text(
                      '实时',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF86EFAC),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0xAA86EFAC), blurRadius: 5)],
      ),
    );
  }
}

class _HardwareDetailsPanel extends StatelessWidget {
  const _HardwareDetailsPanel({required this.rows});

  final List<_HardwareDetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 19, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.list_alt_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 9),
              Text(
                '详细信息',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(height: 28),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          '${row.label}：',
                          style: const TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value,
                          style: TextStyle(
                            color: row.highlight
                                ? const Color(0xFFD92D20)
                                : const Color(0xFF101828),
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: row.highlight
                                ? FontWeight.w800
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.description,
    this.loading = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085), height: 1.5),
              ),
            ),
            if (loading) ...[
              const SizedBox(height: 20),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
