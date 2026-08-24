import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HardwareItem {
  const HardwareItem({required this.label, required this.value});

  factory HardwareItem.fromJson(Map<String, dynamic> json) {
    return HardwareItem(
      label: '${json['label'] ?? '项目'}',
      value: '${json['value'] ?? '未知'}',
    );
  }

  final String label;
  final String value;
}

class HardwareSection {
  const HardwareSection({
    required this.id,
    required this.title,
    required this.items,
  });

  factory HardwareSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => HardwareItem.fromJson(item.cast<String, dynamic>()),
              )
              .toList()
        : <HardwareItem>[];
    return HardwareSection(
      id: '${json['id'] ?? 'system'}',
      title: '${json['title'] ?? '硬件信息'}',
      items: items,
    );
  }

  final String id;
  final String title;
  final List<HardwareItem> items;
}

class HardwareSnapshot {
  const HardwareSnapshot({
    required this.computerName,
    required this.collectedAt,
    required this.sections,
  });

  factory HardwareSnapshot.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final sections = rawSections is List
        ? rawSections
              .whereType<Map>()
              .map(
                (section) =>
                    HardwareSection.fromJson(section.cast<String, dynamic>()),
              )
              .where((section) => section.items.isNotEmpty)
              .toList()
        : <HardwareSection>[];
    return HardwareSnapshot(
      computerName: '${json['computerName'] ?? '本机'}',
      collectedAt:
          DateTime.tryParse('${json['collectedAt'] ?? ''}') ?? DateTime.now(),
      sections: sections,
    );
  }

  final String computerName;
  final DateTime collectedAt;
  final List<HardwareSection> sections;

  int get itemCount =>
      sections.fold(0, (sum, section) => sum + section.items.length);

  HardwareSection? section(String id) {
    for (final section in sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  String value(String sectionId, String label, {String fallback = '未知'}) {
    final target = section(sectionId);
    if (target == null) return fallback;
    for (final item in target.items) {
      if (item.label == label) return item.value;
    }
    return fallback;
  }

  bool get hasRtx3080 {
    return sections
        .where((section) => section.id == 'gpu')
        .expand((section) => section.items)
        .where((item) => RegExp(r'^显卡 \d+$').hasMatch(item.label))
        .any(
          (item) =>
              RegExp(r'RTX\s*3080', caseSensitive: false).hasMatch(item.value),
        );
  }

  String toReport() {
    final buffer = StringBuffer()
      ..writeln('3080工具箱 - 硬件检测报告')
      ..writeln('计算机：$computerName')
      ..writeln('检测时间：${_formatTime(collectedAt)}')
      ..writeln();
    for (final section in sections) {
      buffer.writeln('【${section.title}】');
      for (final item in section.items) {
        final value =
            hasRtx3080 &&
                section.id == 'gpu' &&
                RegExp(r'^显卡 \d+$').hasMatch(item.label)
            ? '老牧师3080'
            : item.value;
        buffer.writeln('${item.label}：$value');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

class HardwareDetectionService {
  const HardwareDetectionService();

  Future<HardwareSnapshot> detect() async {
    if (!Platform.isWindows) throw UnsupportedError('硬件检测目前仅支持 Windows');
    final encoded = _encodePowerShell(_powerShellScript);
    final process = await Process.start('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ], runInShell: false);
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      process.kill();
      throw TimeoutException('硬件检测超过 20 秒，已停止本次检测');
    }
    final output = await outputFuture;
    final error = await errorFuture;
    if (exitCode != 0) {
      throw StateError(
        error.trim().isEmpty ? 'PowerShell 退出码 $exitCode' : error.trim(),
      );
    }
    final decoded = jsonDecode(output.trim());
    if (decoded is! Map) throw const FormatException('硬件检测返回了无效数据');
    final snapshot = HardwareSnapshot.fromJson(decoded.cast<String, dynamic>());
    if (snapshot.sections.isEmpty) throw const FormatException('没有读取到硬件信息');
    return snapshot;
  }

  Future<bool> hasRtx3080() async {
    if (!Platform.isWindows) return false;
    const script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$match = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'RTX\s*3080' }).Count -gt 0
if ($match) { 'true' } else { 'false' }
''';
    final process = await Process.start('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      _encodePowerShell(script),
    ], runInShell: false);
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    process.stderr.drain<void>();
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 10),
      );
      final output = await outputFuture;
      return exitCode == 0 && output.trim().toLowerCase() == 'true';
    } on TimeoutException {
      process.kill();
      return false;
    }
  }

  static String _encodePowerShell(String script) {
    final bytes = <int>[];
    for (final codeUnit in script.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add(codeUnit >> 8);
    }
    return base64Encode(bytes);
  }

  static const _powerShellScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
function TextOrUnknown($value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return '未知' }
  $text = [string]$value
  if ($text -in @('Undefined', 'Unknown', 'To be filled by O.E.M.')) { return '未知' }
  return $text
}
function BytesText([double]$value) {
  if ($value -le 0) { return '未知' }
  if ($value -ge 1TB) { return ('{0:N2} TB' -f ($value / 1TB)) }
  return ('{0:N1} GB' -f ($value / 1GB))
}
function SpeedText([double]$value) {
  if ($value -le 0) { return '未知' }
  if ($value -ge 1000000000) { return ('{0:N1} Gbps' -f ($value / 1000000000)) }
  return ('{0:N0} Mbps' -f ($value / 1000000))
}
function Item($label, $value) {
  return [pscustomobject]@{ label = $label; value = (TextOrUnknown $value) }
}

$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
$gpus = @(Get-CimInstance Win32_VideoController)
$memory = @(Get-CimInstance Win32_PhysicalMemory)
$disks = @(Get-CimInstance Win32_DiskDrive)
$volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')
$adapters = @(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -and $_.NetEnabled } | Select-Object -First 6)
$monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active })
$audioDevices = @(Get-CimInstance Win32_SoundDevice | Where-Object { $_.Status -eq 'OK' })
$sections = @()

$uptime = (Get-Date) - $os.LastBootUpTime
$systemItems = @(
  (Item '计算机名' $env:COMPUTERNAME),
  (Item '操作系统' ("{0} {1}" -f $os.Caption, $os.OSArchitecture)),
  (Item '系统版本' ("{0}（Build {1}）" -f $os.Version, $os.BuildNumber)),
  (Item '整机厂商' $computer.Manufacturer),
  (Item '整机型号' $computer.Model),
  (Item '本次运行时间' ("{0} 天 {1} 小时 {2} 分钟" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes))
)
$sections += [pscustomobject]@{ id = 'system'; title = '系统与整机'; items = $systemItems }

$cpuItems = @(
  (Item '处理器' $cpu.Name.Trim()),
  (Item '核心 / 线程' ("{0} 核 / {1} 线程" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)),
  (Item '最高频率' ("{0:N2} GHz" -f ($cpu.MaxClockSpeed / 1000))),
  (Item '架构' $os.OSArchitecture),
  (Item '处理器标识' $cpu.ProcessorId)
)
$sections += [pscustomobject]@{ id = 'cpu'; title = '处理器'; items = $cpuItems }

$gpuItems = @()
for ($i = 0; $i -lt $gpus.Count; $i++) {
  $gpu = $gpus[$i]
  $n = $i + 1
  $gpuItems += Item ("显卡 $n") $gpu.Name
  $gpuItems += Item ("显卡 $n 驱动") $gpu.DriverVersion
  if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
    $gpuItems += Item ("显卡 $n 当前输出") ("{0} × {1} · {2} Hz" -f $gpu.CurrentHorizontalResolution, $gpu.CurrentVerticalResolution, $gpu.CurrentRefreshRate)
  }
}
$sections += [pscustomobject]@{ id = 'gpu'; title = '显卡与显示'; items = $gpuItems }

$memoryItems = @(
  (Item '已安装内存' (BytesText $computer.TotalPhysicalMemory)),
  (Item '当前可用' (BytesText ($os.FreePhysicalMemory * 1KB))),
  (Item '内存插槽数量' ("{0} 条" -f $memory.Count))
)
for ($i = 0; $i -lt $memory.Count; $i++) {
  $module = $memory[$i]
  $memoryItems += Item ("内存条 $($i + 1)") ("{0} · {1} MHz · {2}" -f (BytesText $module.Capacity), $module.ConfiguredClockSpeed, (TextOrUnknown $module.Manufacturer))
}
$sections += [pscustomobject]@{ id = 'memory'; title = '内存'; items = $memoryItems }

$boardItems = @(
  (Item '主板厂商' $board.Manufacturer),
  (Item '主板型号' $board.Product),
  (Item '主板版本' $board.Version),
  (Item 'BIOS 厂商' $bios.Manufacturer),
  (Item 'BIOS 版本' $bios.SMBIOSBIOSVersion),
  (Item 'BIOS 日期' ($bios.ReleaseDate.ToString('yyyy-MM-dd')))
)
$sections += [pscustomobject]@{ id = 'board'; title = '主板与 BIOS'; items = $boardItems }

$diskItems = @()
for ($i = 0; $i -lt $disks.Count; $i++) {
  $disk = $disks[$i]
  $diskItems += Item ("物理磁盘 $($i + 1)") ("{0} · {1} · {2}" -f $disk.Model, (BytesText $disk.Size), (TextOrUnknown $disk.InterfaceType))
}
foreach ($volume in $volumes) {
  $used = $volume.Size - $volume.FreeSpace
  $diskItems += Item ("分区 $($volume.DeviceID)") ("已用 {0} / 总计 {1} · 可用 {2}" -f (BytesText $used), (BytesText $volume.Size), (BytesText $volume.FreeSpace))
}
$sections += [pscustomobject]@{ id = 'storage'; title = '存储设备'; items = $diskItems }

$monitorItems = @()
foreach ($monitor in $monitors) {
  $name = -join @($monitor.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
  $maker = -join @($monitor.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
  $monitorItems += Item ("显示器 $($monitorItems.Count + 1)") ("{0} · 厂商 {1}" -f (TextOrUnknown $name), (TextOrUnknown $maker))
}
if ($monitorItems.Count -eq 0) { $monitorItems += Item '显示器' '未读取到 EDID 信息' }
$sections += [pscustomobject]@{ id = 'monitor'; title = '显示器'; items = $monitorItems }

$audioItems = @()
for ($i = 0; $i -lt $audioDevices.Count; $i++) {
  $audioItems += Item ("声卡 $($i + 1)") $audioDevices[$i].Name
}
if ($audioItems.Count -eq 0) { $audioItems += Item '声卡' '未检测到' }
$sections += [pscustomobject]@{ id = 'audio'; title = '声卡'; items = $audioItems }

$networkItems = @()
foreach ($adapter in $adapters) {
  $networkItems += Item $adapter.Name ("{0} · MAC {1}" -f (SpeedText $adapter.Speed), (TextOrUnknown $adapter.MACAddress))
}
if ($networkItems.Count -eq 0) { $networkItems += Item '活动适配器' '未检测到' }
$sections += [pscustomobject]@{ id = 'network'; title = '网络适配器'; items = $networkItems }

[pscustomobject]@{
  computerName = $env:COMPUTERNAME
  collectedAt = (Get-Date).ToString('o')
  sections = $sections
} | ConvertTo-Json -Depth 7 -Compress
''';
}
