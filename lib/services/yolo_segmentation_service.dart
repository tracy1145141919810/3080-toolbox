import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import '../models/app_models.dart';

class YoloSegmentationService {
  static const _modelAsset = 'assets/models/yolo11n-seg.onnx';
  static const _inputSize = 640;

  OrtSession? _session;
  Uint8List? _modelBytes;
  InferenceDevice? _configuredDevice;
  String _activeDeviceLabel = '尚未初始化';
  bool _environmentReady = false;

  String get activeDeviceLabel => _activeDeviceLabel;

  Future<void> initialize(InferenceDevice requestedDevice) async {
    if (_session != null && _configuredDevice == requestedDevice) return;

    _session?.release();
    _session = null;

    if (!_environmentReady) {
      OrtEnv.instance.init();
      _environmentReady = true;
    }
    _modelBytes ??= (await rootBundle.load(_modelAsset)).buffer.asUint8List();

    if (requestedDevice != InferenceDevice.cpu) {
      try {
        _session = _createSession(useGpu: true);
        _activeDeviceLabel = 'DirectML GPU';
        _configuredDevice = requestedDevice;
        return;
      } catch (error) {
        if (requestedDevice == InferenceDevice.gpu) {
          throw StateError('无法启动 DirectML GPU：$error');
        }
      }
    }

    _session = _createSession(useGpu: false);
    _activeDeviceLabel = 'CPU';
    _configuredDevice = requestedDevice;
  }

  OrtSession _createSession({required bool useGpu}) {
    final options = OrtSessionOptions();
    try {
      options.setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );
      if (useGpu) {
        options.setSessionExecutionMode(OrtSessionExecutionMode.ortSequential);
        options.appendDirectMLProvider({'device_id': '0'});
      } else {
        options.setIntraOpNumThreads(math.max(1, math.min(8, 4)));
        options.appendCPUProvider(CPUFlags.useArena);
      }
      return OrtSession.fromBuffer(_modelBytes!, options);
    } finally {
      options.release();
    }
  }

  Future<SegmentationResult> process(
    Uint8List imageBytes,
    InferenceDevice requestedDevice,
  ) async {
    final stopwatch = Stopwatch()..start();
    await initialize(requestedDevice);
    final prepared = await Isolate.run(() => _prepare(imageBytes));

    final input = OrtValueTensor.createTensorWithDataList(
      prepared.tensor,
      const [1, 3, _inputSize, _inputSize],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session!.runAsyncWithTimeout(runOptions, {
        _session!.inputNames.first: input,
      }, const Duration(minutes: 2));
      if (outputs == null || outputs.length < 2) {
        throw const FormatException('YOLO 模型没有返回分割遮罩。');
      }
      final first = outputs[0]!.value;
      final second = outputs[1]!.value;
      final result = await Isolate.run(
        () => _composeWhiteBackground(prepared, first, second),
      );
      stopwatch.stop();
      return SegmentationResult(
        pngBytes: result.bytes,
        width: result.width,
        height: result.height,
        personCount: result.personCount,
        deviceLabel: _activeDeviceLabel,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      input.release();
      runOptions.release();
      outputs?.forEach((value) => value?.release());
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    if (_environmentReady) {
      OrtEnv.instance.release();
      _environmentReady = false;
    }
  }

  static _PreparedImage _prepare(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('不支持此图像，建议使用 JPG 或 PNG。');
    }
    final source = img.bakeOrientation(decoded);
    if (source.width > 20000 || source.height > 20000) {
      throw const FormatException('图像尺寸过大，请选择边长不超过 20000 像素的图片。');
    }

    final scale = math.min(
      _inputSize / source.width,
      _inputSize / source.height,
    );
    final resizedWidth = math.max(1, (source.width * scale).round());
    final resizedHeight = math.max(1, (source.height * scale).round());
    final padX = ((_inputSize - resizedWidth) / 2).floor();
    final padY = ((_inputSize - resizedHeight) / 2).floor();
    final resized = img.copyResize(
      source,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    final letterboxed = img.Image(
      width: _inputSize,
      height: _inputSize,
      numChannels: 3,
    );
    img.fill(letterboxed, color: img.ColorRgb8(114, 114, 114));
    img.compositeImage(letterboxed, resized, dstX: padX, dstY: padY);

    final tensor = Float32List(3 * _inputSize * _inputSize);
    final plane = _inputSize * _inputSize;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = letterboxed.getPixel(x, y);
        final index = y * _inputSize + x;
        tensor[index] = pixel.r / 255.0;
        tensor[plane + index] = pixel.g / 255.0;
        tensor[2 * plane + index] = pixel.b / 255.0;
      }
    }

    return _PreparedImage(
      tensor: tensor,
      originalBytes: Uint8List.fromList(img.encodePng(source)),
      width: source.width,
      height: source.height,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }

  static _ComposedResult _composeWhiteBackground(
    _PreparedImage prepared,
    dynamic firstOutput,
    dynamic secondOutput,
  ) {
    final firstBatch = (firstOutput as List).first as List;
    final secondBatch = (secondOutput as List).first as List;
    final firstLooksLikePrototype = firstBatch.length == 32;
    final detectionBatch = firstLooksLikePrototype ? secondBatch : firstBatch;
    final prototypeBatch = firstLooksLikePrototype ? firstBatch : secondBatch;

    final channelsFirst = detectionBatch.length < 500;
    final channels = channelsFirst
        ? detectionBatch.length
        : (detectionBatch.first as List).length;
    final anchors = channelsFirst
        ? (detectionBatch.first as List).length
        : detectionBatch.length;
    if (channels < 37) {
      throw const FormatException('YOLO 分割模型输出格式不受支持。');
    }
    double at(int channel, int anchor) {
      final value = channelsFirst
          ? (detectionBatch[channel] as List)[anchor]
          : (detectionBatch[anchor] as List)[channel];
      return (value as num).toDouble();
    }

    final coefficientStart = channels - 32;
    final candidates = <_Detection>[];
    for (var anchor = 0; anchor < anchors; anchor++) {
      final confidence = at(4, anchor); // COCO class 0: person
      if (confidence < 0.25) continue;
      final centerX = at(0, anchor);
      final centerY = at(1, anchor);
      final width = at(2, anchor);
      final height = at(3, anchor);
      candidates.add(
        _Detection(
          confidence: confidence,
          left: centerX - width / 2,
          top: centerY - height / 2,
          right: centerX + width / 2,
          bottom: centerY + height / 2,
          coefficients: List<double>.generate(
            32,
            (index) => at(coefficientStart + index, anchor),
            growable: false,
          ),
        ),
      );
    }
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_Detection>[];
    for (final candidate in candidates) {
      if (kept.every((item) => _iou(item, candidate) < 0.45)) {
        kept.add(candidate);
        if (kept.length == 10) break;
      }
    }
    if (kept.isEmpty) {
      throw const FormatException('未识别到人像，请选择主体清晰、人物占比较大的照片。');
    }

    final prototypeHeight = (prototypeBatch.first as List).length;
    final prototypeWidth =
        ((prototypeBatch.first as List).first as List).length;
    final combinedMask = Float32List(prototypeWidth * prototypeHeight);
    for (final detection in kept) {
      final left = (detection.left / _inputSize * prototypeWidth).floor().clamp(
        0,
        prototypeWidth - 1,
      );
      final right = (detection.right / _inputSize * prototypeWidth)
          .ceil()
          .clamp(0, prototypeWidth);
      final top = (detection.top / _inputSize * prototypeHeight).floor().clamp(
        0,
        prototypeHeight - 1,
      );
      final bottom = (detection.bottom / _inputSize * prototypeHeight)
          .ceil()
          .clamp(0, prototypeHeight);
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          var sum = 0.0;
          for (var channel = 0; channel < 32; channel++) {
            final plane = prototypeBatch[channel] as List;
            final row = plane[y] as List;
            sum += detection.coefficients[channel] * (row[x] as num).toDouble();
          }
          final probability = 1.0 / (1.0 + math.exp(-sum));
          final index = y * prototypeWidth + x;
          if (probability > combinedMask[index]) {
            combinedMask[index] = probability;
          }
        }
      }
    }

    final source = img.decodePng(prepared.originalBytes)!;
    final output = img.Image(
      width: prepared.width,
      height: prepared.height,
      numChannels: 4,
    );
    for (var y = 0; y < prepared.height; y++) {
      final modelY = y * prepared.scale + prepared.padY;
      final maskY = modelY / _inputSize * prototypeHeight;
      for (var x = 0; x < prepared.width; x++) {
        final modelX = x * prepared.scale + prepared.padX;
        final maskX = modelX / _inputSize * prototypeWidth;
        final probability = _bilinear(
          combinedMask,
          prototypeWidth,
          prototypeHeight,
          maskX,
          maskY,
        );
        final alpha = ((probability - 0.32) / 0.36).clamp(0.0, 1.0);
        final pixel = source.getPixel(x, y);
        output.setPixelRgba(
          x,
          y,
          pixel.r,
          pixel.g,
          pixel.b,
          (alpha * 255).round(),
        );
      }
    }

    return _ComposedResult(
      bytes: Uint8List.fromList(img.encodePng(output, level: 6)),
      width: output.width,
      height: output.height,
      personCount: kept.length,
    );
  }

  static double _bilinear(
    Float32List data,
    int width,
    int height,
    double x,
    double y,
  ) {
    final x0 = x.floor().clamp(0, width - 1);
    final y0 = y.floor().clamp(0, height - 1);
    final x1 = (x0 + 1).clamp(0, width - 1);
    final y1 = (y0 + 1).clamp(0, height - 1);
    final dx = (x - x0).clamp(0.0, 1.0);
    final dy = (y - y0).clamp(0.0, 1.0);
    final top = data[y0 * width + x0] * (1 - dx) + data[y0 * width + x1] * dx;
    final bottom =
        data[y1 * width + x0] * (1 - dx) + data[y1 * width + x1] * dx;
    return top * (1 - dy) + bottom * dy;
  }

  static double _iou(_Detection a, _Detection b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final intersection =
        math.max(0.0, right - left) * math.max(0.0, bottom - top);
    final areaA =
        math.max(0.0, a.right - a.left) * math.max(0.0, a.bottom - a.top);
    final areaB =
        math.max(0.0, b.right - b.left) * math.max(0.0, b.bottom - b.top);
    final union = areaA + areaB - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}

class _PreparedImage {
  const _PreparedImage({
    required this.tensor,
    required this.originalBytes,
    required this.width,
    required this.height,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  final Float32List tensor;
  final Uint8List originalBytes;
  final int width;
  final int height;
  final double scale;
  final int padX;
  final int padY;
}

class _Detection {
  const _Detection({
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.coefficients,
  });

  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<double> coefficients;
}

class _ComposedResult {
  const _ComposedResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.personCount,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int personCount;
}
