import 'package:flutter/material.dart';

import 'gif_recorder_screen.dart';
import 'hardware_detection_screen.dart';
import 'home_screen.dart';
import 'image_converter_screen.dart';
import 'services/hardware_detection_service.dart';
import 'services/hardware_monitor_service.dart';

enum ToolboxPage {
  home,
  portraitBackground,
  imageConverter,
  gifRecorder,
  hardwareDetection,
}

class ToolboxShell extends StatefulWidget {
  const ToolboxShell({
    super.key,
    this.hardwareLoader,
    this.hardwareTelemetryStreamFactory,
    this.initialPage = ToolboxPage.home,
  });

  final HardwareSnapshotLoader? hardwareLoader;
  final HardwareTelemetryStreamFactory? hardwareTelemetryStreamFactory;
  final ToolboxPage initialPage;

  @override
  State<ToolboxShell> createState() => _ToolboxShellState();
}

class _ToolboxShellState extends State<ToolboxShell> {
  final _searchController = TextEditingController();
  late ToolboxPage _page;
  String _query = '';
  bool _hasRtx3080 = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(ToolboxPage page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactNavigation = constraints.maxWidth < 1000;
        return Scaffold(
          body: Row(
            children: [
              _ToolboxNavigation(
                selected: _page,
                onSelected: _open,
                compact: compactNavigation,
              ),
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFFF5F7FA),
                  child: switch (_page) {
                    ToolboxPage.home => _buildToolCenter(),
                    ToolboxPage.portraitBackground => const HomeScreen(),
                    ToolboxPage.imageConverter => const ImageConverterScreen(),
                    ToolboxPage.gifRecorder => const GifRecorderScreen(),
                    ToolboxPage.hardwareDetection => HardwareDetectionScreen(
                      loader: widget.hardwareLoader,
                      telemetryStreamFactory:
                          widget.hardwareTelemetryStreamFactory,
                      onDetected: _onHardwareDetected,
                    ),
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolCenterHeader() {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '工具中心',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          '选择工具即可使用，图像处理和屏幕录制均在本机完成。',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: const Color(0xFF667085)),
        ),
      ],
    );
    final search = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: const InputDecoration(
        hintText: '搜索工具或功能',
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), search],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 24),
            SizedBox(width: 340, child: search),
          ],
        );
      },
    );
  }

  Widget _buildToolCenter() {
    final normalized = _query.trim().toLowerCase();
    final portraitMatches =
        normalized.isEmpty ||
        '白底人像 人像抠图 背景替换 证件照 heic yolo gpu'.contains(normalized);
    final gifMatches =
        normalized.isEmpty ||
        'gif录屏 gif 动图 屏幕录制 框选区域 帧 编辑 screentogif'.contains(normalized);
    final converterMatches =
        normalized.isEmpty ||
        '图片 图像 格式转换 批量 heic raw jpg jpeg png webp avif jxl tiff imagemagick'
            .contains(normalized);
    final hardwareMatches =
        normalized.isEmpty ||
        '硬件检测 硬件信息 配置 cpu gpu 显卡 内存 主板 bios 磁盘 显示器 声卡 网卡 rtx3080'.contains(
          normalized,
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolCenterHeader(),
            const SizedBox(height: 28),
            _OverviewBanner(showScore: _hasRtx3080),
            const SizedBox(height: 28),
            if (portraitMatches || converterMatches) ...[
              Text(
                '图像处理',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  if (portraitMatches)
                    _PortraitToolCard(
                      onOpen: () => _open(ToolboxPage.portraitBackground),
                    ),
                  if (converterMatches)
                    _ImageConverterToolCard(
                      onOpen: () => _open(ToolboxPage.imageConverter),
                    ),
                ],
              ),
              const SizedBox(height: 26),
            ],
            if (gifMatches) ...[
              Text(
                '屏幕工具',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _GifRecorderToolCard(
                onOpen: () => _open(ToolboxPage.gifRecorder),
              ),
              const SizedBox(height: 26),
            ],
            if (hardwareMatches) ...[
              Text(
                '硬件工具',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _HardwareDetectionToolCard(
                onOpen: () => _open(ToolboxPage.hardwareDetection),
              ),
            ],
            if (!portraitMatches &&
                !converterMatches &&
                !gifMatches &&
                !hardwareMatches)
              _buildEmptySearch(),
          ],
        ),
      ),
    );
  }

  void _onHardwareDetected(HardwareSnapshot snapshot) {
    if (_hasRtx3080 == snapshot.hasRtx3080) return;
    setState(() => _hasRtx3080 = snapshot.hasRtx3080);
  }

  Widget _buildEmptySearch() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          const Text(
            '没有找到匹配的工具',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              _searchController.clear();
              setState(() => _query = '');
            },
            child: const Text('清除搜索'),
          ),
        ],
      ),
    );
  }
}

class _OverviewBanner extends StatelessWidget {
  const _OverviewBanner({required this.showScore});

  final bool showScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242563EB),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.offline_bolt_rounded,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本地影像处理工作台',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  '集成 GPU 人像处理、格式转换、GIF 录屏与硬件检测，数据无需上传。',
                  style: TextStyle(color: Color(0xFFDCE8FF), fontSize: 14),
                ),
              ],
            ),
          ),
          const _OverviewMetric(value: '4', label: '可用工具'),
          const SizedBox(width: 28),
          if (showScore) ...[
            const _OverviewMetric(value: '114514分', label: '整机性能评分'),
            const SizedBox(width: 28),
          ],
          const _OverviewMetric(value: 'GPU', label: '本地加速'),
        ],
      ),
    );
  }
}

class _ToolboxNavigation extends StatelessWidget {
  const _ToolboxNavigation({
    required this.selected,
    required this.onSelected,
    required this.compact,
  });

  final ToolboxPage selected;
  final ValueChanged<ToolboxPage> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 82 : 224,
      color: const Color(0xFF111827),
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        20,
        compact ? 10 : 14,
        18,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const _BrandMark(),
                  if (!compact) ...[
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        '3080工具箱',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            _NavigationItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: '工具中心',
              selected: selected == ToolboxPage.home,
              onTap: () => onSelected(ToolboxPage.home),
              compact: compact,
            ),
            if (!compact)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Text(
                  '图像处理',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _NavigationItem(
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: '白底人像',
              selected: selected == ToolboxPage.portraitBackground,
              onTap: () => onSelected(ToolboxPage.portraitBackground),
              compact: compact,
            ),
            const SizedBox(height: 4),
            _NavigationItem(
              icon: Icons.compare_arrows_rounded,
              selectedIcon: Icons.swap_horiz_rounded,
              label: '格式转换',
              selected: selected == ToolboxPage.imageConverter,
              onTap: () => onSelected(ToolboxPage.imageConverter),
              compact: compact,
            ),
            if (!compact)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Text(
                  '屏幕工具',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _NavigationItem(
              icon: Icons.gif_box_outlined,
              selectedIcon: Icons.gif_box_rounded,
              label: 'GIF录屏',
              selected: selected == ToolboxPage.gifRecorder,
              onTap: () => onSelected(ToolboxPage.gifRecorder),
              compact: compact,
            ),
            if (!compact)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 8),
                child: Text(
                  '硬件工具',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _NavigationItem(
              icon: Icons.monitor_heart_outlined,
              selectedIcon: Icons.monitor_heart_rounded,
              label: '硬件检测',
              selected: selected == ToolboxPage.hardwareDetection,
              onTap: () => onSelected(ToolboxPage.hardwareDetection),
              compact: compact,
            ),
            const Spacer(),
            if (!compact)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '本地运行\n模型与照片不上传',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '🤪',
        style: TextStyle(fontFamily: 'Segoe UI Emoji', fontSize: 23, height: 1),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final item = Material(
      color: selected ? const Color(0xFF2563EB) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                color: selected ? Colors.white : const Color(0xFFD0D5DD),
                size: 21,
              ),
              if (!compact) ...[
                const SizedBox(width: 11),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFD0D5DD),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return compact ? Tooltip(message: label, child: item) : item;
  }
}

class _PortraitToolCard extends StatelessWidget {
  const _PortraitToolCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.person_pin_rounded,
                    color: Color(0xFF2563EB),
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '白底人像',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '人像自动抠图、任意背景色、证件照尺寸与文件体积控制。',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: [
                          _FeatureTag('YOLO'),
                          _FeatureTag('GPU'),
                          _FeatureTag('HEIC'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(onPressed: onOpen, child: const Text('打开工具')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageConverterToolCard extends StatelessWidget {
  const _ImageConverterToolCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.compare_arrows_rounded,
                    color: Color(0xFF2563EB),
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '图片格式转换',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '主流图片批量互转，支持 HEIC/RAW 输入、分辨率和文件大小控制。',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: [
                          _FeatureTag('批量转换'),
                          _FeatureTag('HEIC/RAW'),
                          _FeatureTag('本地处理'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(onPressed: onOpen, child: const Text('打开工具')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GifRecorderToolCard extends StatelessWidget {
  const _GifRecorderToolCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.gif_box_rounded,
                    color: Color(0xFF2563EB),
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GIF录屏',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '框选屏幕区域录制，预览和删除帧，控制分辨率与 GIF 文件大小。',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: [
                          _FeatureTag('区域录制'),
                          _FeatureTag('帧编辑'),
                          _FeatureTag('本地编码'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(onPressed: onOpen, child: const Text('打开工具')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HardwareDetectionToolCard extends StatelessWidget {
  const _HardwareDetectionToolCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_rounded,
                    color: Color(0xFF2563EB),
                    size: 34,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '硬件检测',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '独立页面展示整机型号、系统、运行时间和详细硬件配置。',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: [
                          _FeatureTag('CPU/GPU'),
                          _FeatureTag('磁盘/内存'),
                          _FeatureTag('本地只读'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(onPressed: onOpen, child: const Text('打开工具')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475467),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: Color(0xFFDCE8FF))),
      ],
    );
  }
}
