import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef HardwareTelemetryStreamFactory = Stream<HardwareTelemetry> Function();

class HardwareTelemetry {
  const HardwareTelemetry({
    required this.collectedAt,
    this.cpuUsagePercent,
    this.cpuFrequencyMhz,
    this.gpuUsagePercent,
    this.gpuTemperatureCelsius,
    this.gpuMemoryUsedMb,
    this.gpuMemoryTotalMb,
    this.gpuPowerWatts,
    this.memoryUsagePercent,
    this.memoryUsedGb,
    this.memoryTotalGb,
  });

  factory HardwareTelemetry.fromJson(Map<String, dynamic> json) {
    double? number(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : double.tryParse('$value');
    }

    return HardwareTelemetry(
      collectedAt:
          DateTime.tryParse('${json['collectedAt'] ?? ''}') ?? DateTime.now(),
      cpuUsagePercent: number('cpuUsagePercent'),
      cpuFrequencyMhz: number('cpuFrequencyMhz'),
      gpuUsagePercent: number('gpuUsagePercent'),
      gpuTemperatureCelsius: number('gpuTemperatureCelsius'),
      gpuMemoryUsedMb: number('gpuMemoryUsedMb'),
      gpuMemoryTotalMb: number('gpuMemoryTotalMb'),
      gpuPowerWatts: number('gpuPowerWatts'),
      memoryUsagePercent: number('memoryUsagePercent'),
      memoryUsedGb: number('memoryUsedGb'),
      memoryTotalGb: number('memoryTotalGb'),
    );
  }

  final DateTime collectedAt;
  final double? cpuUsagePercent;
  final double? cpuFrequencyMhz;
  final double? gpuUsagePercent;
  final double? gpuTemperatureCelsius;
  final double? gpuMemoryUsedMb;
  final double? gpuMemoryTotalMb;
  final double? gpuPowerWatts;
  final double? memoryUsagePercent;
  final double? memoryUsedGb;
  final double? memoryTotalGb;

  Map<String, dynamic> toJson() => {
    'collectedAt': collectedAt.toIso8601String(),
    'cpuUsagePercent': cpuUsagePercent,
    'cpuFrequencyMhz': cpuFrequencyMhz,
    'gpuUsagePercent': gpuUsagePercent,
    'gpuTemperatureCelsius': gpuTemperatureCelsius,
    'gpuMemoryUsedMb': gpuMemoryUsedMb,
    'gpuMemoryTotalMb': gpuMemoryTotalMb,
    'gpuPowerWatts': gpuPowerWatts,
    'memoryUsagePercent': memoryUsagePercent,
    'memoryUsedGb': memoryUsedGb,
    'memoryTotalGb': memoryTotalGb,
  };
}

class HardwareMonitorService {
  Process? _process;
  StreamController<HardwareTelemetry>? _controller;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _closed = false;

  Stream<HardwareTelemetry> watch() {
    if (!Platform.isWindows) {
      return Stream.error(UnsupportedError('实时硬件监测目前仅支持 Windows'));
    }
    final existing = _controller;
    if (existing != null) return existing.stream;
    late final StreamController<HardwareTelemetry> controller;
    controller = StreamController<HardwareTelemetry>(
      onListen: () => _start(controller),
      onCancel: dispose,
    );
    _controller = controller;
    return controller.stream;
  }

  Future<void> _start(StreamController<HardwareTelemetry> controller) async {
    try {
      final process = await Process.start('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        _encodePowerShell(_powerShellScript),
      ], runInShell: false);
      if (_closed) {
        process.kill();
        return;
      }
      _process = process;
      _outputSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (_closed || line.trim().isEmpty) return;
            try {
              final value = jsonDecode(line);
              if (value is Map) {
                controller.add(
                  HardwareTelemetry.fromJson(value.cast<String, dynamic>()),
                );
              }
            } on FormatException {
              // Ignore non-JSON PowerShell host messages and keep monitoring.
            }
          });
      _errorSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {});
      final exitCode = await process.exitCode;
      if (!_closed && exitCode != 0) {
        controller.addError(StateError('实时监测进程异常退出（$exitCode）'));
      }
    } catch (error, stackTrace) {
      if (!_closed) controller.addError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _outputSubscription?.cancel();
    await _errorSubscription?.cancel();
    _process?.kill();
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) await controller.close();
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
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$culture = [Globalization.CultureInfo]::InvariantCulture
$os = Get-CimInstance Win32_OperatingSystem
$memoryTotalGb = [Math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 2)
$hasNvidiaSmi = $null -ne (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)

function NumberOrNull($value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq '[N/A]') { return $null }
  $number = 0.0
  if ([double]::TryParse(([string]$value).Trim(), [Globalization.NumberStyles]::Float, $culture, [ref]$number)) { return $number }
  return $null
}

while ($true) {
  $cycle = [Diagnostics.Stopwatch]::StartNew()
  $cpuUsage = $null
  $cpuFrequency = $null
  $memoryUsedGb = $null
  $memoryUsage = $null
  $gpuUsage = $null
  $gpuTemperature = $null
  $gpuMemoryUsed = $null
  $gpuMemoryTotal = $null
  $gpuPower = $null

  $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" | Select-Object -First 1
  if ($null -ne $cpu) { $cpuUsage = NumberOrNull $cpu.PercentProcessorTime }
  $frequency = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
  if ($null -ne $frequency) { $cpuFrequency = NumberOrNull $frequency.ProcessorFrequency }

  $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory | Select-Object -First 1
  if ($null -ne $memory -and $memoryTotalGb -gt 0) {
    $availableGb = [double]$memory.AvailableMBytes / 1024
    $memoryUsedGb = [Math]::Max(0, $memoryTotalGb - $availableGb)
    $memoryUsage = [Math]::Min(100, [Math]::Max(0, ($memoryUsedGb / $memoryTotalGb) * 100))
  }

  if ($hasNvidiaSmi) {
    $line = @(nvidia-smi.exe --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
    if ($line.Count -gt 0) {
      $parts = [string]$line[0] -split ','
      if ($parts.Count -ge 5) {
        $gpuUsage = NumberOrNull $parts[0]
        $gpuTemperature = NumberOrNull $parts[1]
        $gpuMemoryUsed = NumberOrNull $parts[2]
        $gpuMemoryTotal = NumberOrNull $parts[3]
        $gpuPower = NumberOrNull $parts[4]
      }
    }
  }
  if ($null -eq $gpuUsage) {
    $engines = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine)
    if ($engines.Count -gt 0) {
      $sum = ($engines | Measure-Object -Property UtilizationPercentage -Sum).Sum
      $gpuUsage = [Math]::Min(100, [Math]::Max(0, [double]$sum))
    }
  }

  [ordered]@{
    collectedAt = (Get-Date).ToString('o')
    cpuUsagePercent = $cpuUsage
    cpuFrequencyMhz = $cpuFrequency
    gpuUsagePercent = $gpuUsage
    gpuTemperatureCelsius = $gpuTemperature
    gpuMemoryUsedMb = $gpuMemoryUsed
    gpuMemoryTotalMb = $gpuMemoryTotal
    gpuPowerWatts = $gpuPower
    memoryUsagePercent = $memoryUsage
    memoryUsedGb = $memoryUsedGb
    memoryTotalGb = $memoryTotalGb
  } | ConvertTo-Json -Compress | Write-Output
  [Console]::Out.Flush()
  $remaining = 1000 - [int]$cycle.Elapsed.TotalMilliseconds
  if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
}
''';
}
