import 'package:flutter/services.dart';

class ScreenRegion {
  const ScreenRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

class RawScreenFrame {
  const RawScreenFrame({
    required this.width,
    required this.height,
    required this.bgraBytes,
  });

  final int width;
  final int height;
  final Uint8List bgraBytes;

  Map<String, Object> toMessage() => <String, Object>{
    'width': width,
    'height': height,
    'pixels': bgraBytes,
  };
}

class ScreenCaptureService {
  const ScreenCaptureService();

  static const _channel = MethodChannel('toolbox_3080/screen_capture');
  static Future<void> Function()? _indicatorCallback;

  void setRecordingIndicatorCallback(Future<void> Function()? callback) {
    _indicatorCallback = callback;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'recordingIndicatorClicked') {
        await _indicatorCallback?.call();
      }
    });
  }

  Future<ScreenRegion?> selectRegion({
    String instruction = '拖动鼠标框选录制区域 · Esc 或右键取消',
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'selectRegion',
      <String, Object>{'instruction': instruction},
    );
    if (result == null) return null;
    return ScreenRegion(
      x: result['x']! as int,
      y: result['y']! as int,
      width: result['width']! as int,
      height: result['height']! as int,
    );
  }

  Future<RawScreenFrame> capture(
    ScreenRegion region, {
    required int outputWidth,
    required int outputHeight,
    required bool includeCursor,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'captureRegion',
      <String, Object>{
        'x': region.x,
        'y': region.y,
        'width': region.width,
        'height': region.height,
        'outputWidth': outputWidth,
        'outputHeight': outputHeight,
        'includeCursor': includeCursor,
      },
    );
    if (result == null) {
      throw StateError('屏幕抓取未返回图像');
    }
    return RawScreenFrame(
      width: result['width']! as int,
      height: result['height']! as int,
      bgraBytes: result['pixels']! as Uint8List,
    );
  }

  Future<void> setToolboxVisible(bool visible) => _channel.invokeMethod<void>(
    'setToolboxVisible',
    <String, Object>{'visible': visible},
  );

  Future<void> showRecordingIndicator(String text, {ScreenRegion? region}) =>
      _channel.invokeMethod<void>('showRecordingIndicator', <String, Object>{
        'text': text,
        if (region != null) 'x': region.x + region.width ~/ 2,
        if (region != null) 'y': region.y + region.height ~/ 2,
      });

  Future<void> updateRecordingIndicator(String text) =>
      _channel.invokeMethod<void>('updateRecordingIndicator', <String, Object>{
        'text': text,
      });

  Future<void> hideRecordingIndicator() =>
      _channel.invokeMethod<void>('hideRecordingIndicator');
}
