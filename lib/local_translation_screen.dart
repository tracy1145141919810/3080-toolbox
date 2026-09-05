import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'services/local_translation_service.dart';
import 'models/ocr_layout.dart';
import 'widgets/ocr_layout_view.dart';
import 'widgets/linked_ocr_comparison.dart';

class LocalTranslationScreen extends StatefulWidget {
  const LocalTranslationScreen({
    super.key,
    this.translator,
    this.ocr,
    this.initialImagePath,
    this.reportPath,
  });
  final LocalTranslationService? translator;
  final LocalOcrService? ocr;
  final String? initialImagePath;
  final String? reportPath;
  @override
  State<LocalTranslationScreen> createState() => _LocalTranslationScreenState();
}

class _LocalTranslationScreenState extends State<LocalTranslationScreen> {
  late final _translator = widget.translator ?? LocalTranslationService();
  late final _ocr = widget.ocr ?? LocalOcrService();
  final _source = TextEditingController();
  List<Map<String, String>> _languages = [];
  String _ocrLanguage = 'multilingual';
  String _target = '简体中文';
  String _translation = '';
  String _status = '等待翻译';
  String? _error;
  LocalOcrResult? _image;
  bool _busy = false;
  bool _translating = false;
  int _operation = 0;
  int? _translateMs;
  int? _firstTokenMs;
  List<OcrBlock> _blocks = [];
  List<OcrBlock> _translatedBlocks = [];
  String _sourceView = 'layout';

  @override
  void initState() {
    super.initState();
    _loadLanguages();
    if (widget.initialImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _readImage(widget.initialImagePath!),
      );
    }
  }

  Future<void> _loadLanguages() async {
    try {
      final languages = await _ocr.languages();
      if (mounted) setState(() => _languages = languages);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  String _friendly(Object e) => e
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');

  Future<void> _scan(Future<LocalOcrResult?> Function() operation) async {
    if (_busy) return;
    final id = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在本机识别文字…';
    });
    try {
      final result = await operation();
      if (!mounted || id != _operation) return;
      if (result == null) {
        setState(() => _status = '已取消框选 · 原有结果保留');
        return;
      }
      setState(() {
        _image = result;
        _blocks = [...result.blocks];
        _translatedBlocks = [];
        _sourceView = _blocks.isEmpty ? 'text' : 'translated';
        _source.text = result.text;
        _translation = '';
        _translateMs = null;
      });
      await _translate(id);
    } catch (e) {
      if (mounted && id == _operation) {
        setState(() {
          _error = _friendly(e);
          _status = '未完成';
        });
      }
    } finally {
      if (mounted && id == _operation) {
        setState(() {
          _busy = false;
          _translating = false;
        });
      }
    }
  }

  Future<void> _readImage(String path) =>
      _scan(() => _ocr.scanFile(path, _ocrLanguage));

  Future<void> _pickImage() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '图片',
          extensions: ['png', 'jpg', 'jpeg', 'bmp', 'webp'],
        ),
      ],
    );
    if (file != null && mounted) await _readImage(file.path);
  }

  Future<void> _startTextTranslation() async {
    if (_busy) return;
    final id = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _translate(id);
    } catch (e) {
      if (mounted && id == _operation) {
        setState(() {
          _error = _friendly(e);
          _status = '翻译未完成 · 下方可能是部分结果';
        });
      }
    } finally {
      if (mounted && id == _operation) {
        setState(() {
          _busy = false;
          _translating = false;
        });
      }
    }
  }

  Future<void> _translate(int id) async {
    setState(() {
      _translating = true;
      _translation = '';
      _translateMs = null;
      _firstTokenMs = null;
      _translatedBlocks = [];
      _status = _translator.ready ? '正在本机翻译…' : '正在加载模型…';
    });
    final target = switch (_target) {
      '简体中文' => 'Simplified Chinese',
      '英语' => 'English',
      '日语' => 'Japanese',
      '韩语' => 'Korean',
      _ => 'Simplified Chinese',
    };
    await for (final update in _translationUpdates(target, id)) {
      if (!mounted || id != _operation) return;
      setState(() {
        if (update.text.isNotEmpty) _firstTokenMs ??= update.elapsedMs;
        _translation = update.text;
        _translateMs = update.elapsedMs;
        _status = update.done ? '翻译完成' : '正在输出译文…';
      });
      if (update.done && widget.reportPath != null) {
        await File(widget.reportPath!).writeAsString(
          jsonEncode({
            'model': p.basename(_translator.modelPath),
            'device': _translator.deviceLabel,
            'ocrMs': _image?.elapsedMs,
            'firstTokenMs': _firstTokenMs,
            'translationMs': _translateMs,
            'loadMs': _translator.lastLoadMs,
            'source': _source.text,
            'translation': _translation,
            'ocrBlockCount': _blocks.length,
          }),
        );
      }
    }
  }

  Stream<TranslationUpdate> _translationUpdates(String target, int id) async* {
    if (_blocks.isEmpty) {
      yield* _translator.translate(_source.text, target);
      return;
    }
    // Translate independent text boxes, never let the model reorder columns.
    await _translator.ensureReady();
    if (!mounted || id != _operation) return;
    final clock = Stopwatch()..start();
    _translatedBlocks = _blocks.map((block) => block.withText('')).toList();
    for (var index = 0; index < _blocks.length; index++) {
      if (!mounted || id != _operation) return;
      if (_blocks[index].text.trim().isEmpty) continue;
      await for (final update in _translator.translate(
        _blocks[index].text,
        target,
      )) {
        if (!mounted || id != _operation) return;
        if (update.done &&
            LocalTranslationService.hasUntranslatedJapanese(
              update.text,
              target,
            )) {
          throw StateError('译文仍有日文假名，不能标记为翻译完成');
        }
        _translatedBlocks[index] = _blocks[index].withText(update.text);
        yield TranslationUpdate(
          layoutText(_translatedBlocks),
          clock.elapsedMilliseconds,
        );
      }
    }
    yield TranslationUpdate(
      layoutText(_translatedBlocks),
      clock.elapsedMilliseconds,
      done: true,
    );
  }

  void _cancel() {
    ++_operation;
    _translator.cancel();
    setState(() {
      _busy = false;
      _translating = false;
      _status = '已停止 · 显存已释放，下方可能是未完成译文';
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    setState(() {
      _source.text = data?.text ?? '';
      _image = null;
      _blocks = [];
      _translatedBlocks = [];
      _translation = '';
    });
  }

  Future<void> _chooseModel() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: '本地 GGUF 模型', extensions: ['gguf']),
      ],
    );
    if (file == null || !mounted) return;
    _translator.unload();
    setState(() {
      _translator.modelPath = file.path;
      _status = '本地模型已选择 · 下次翻译时加载';
    });
  }

  Future<void> _editBlock(int index) async {
    final controller = TextEditingController(text: _blocks[index].text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('校对原位置文字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // The dialog's exit animation can still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || value == null) return;
    setState(() {
      _blocks[index] = _blocks[index].withText(value);
      _source.text = layoutText(_blocks);
      _translation = '';
      _status = '原文已校对 · 文字位置不变，请重新翻译';
      _translatedBlocks = [];
    });
  }

  @override
  void dispose() {
    ++_operation;
    _translator.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '屏幕翻译',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D4ED8), Color(0xFF0891B2)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_status, style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(
                      File(_translator.modelPath).existsSync()
                          ? '模型：${p.basename(_translator.modelPath)}   |   ${_translator.deviceLabel}'
                          : '未导入翻译模型 · 请自行下载 GGUF 后点击“导入本地模型”',
                      style: const TextStyle(
                        color: Color(0xFFDDEEFF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _scan(() => _ocr.scanScreen(_ocrLanguage)),
                    icon: const Icon(Icons.crop_free_rounded),
                    label: const Text('框选屏幕翻译'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('导入图片'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _paste,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('粘贴原文'),
                  ),
                  if (_translating)
                    OutlinedButton(
                      onPressed: _cancel,
                      child: const Text('停止翻译'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _ocrLanguage,
                      decoration: const InputDecoration(labelText: 'OCR 识别语言'),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'multilingual',
                          child: Text('中 / 日 / 英'),
                        ),
                        const DropdownMenuItem(
                          value: 'ja-local',
                          child: Text('日语'),
                        ),
                        const DropdownMenuItem(
                          value: 'auto',
                          child: Text('Windows 系统语言'),
                        ),
                        ..._languages
                            .where(
                              (e) =>
                                  e['tag'] != 'multilingual' &&
                                  e['tag'] != 'ja-local',
                            )
                            .map(
                              (e) => DropdownMenuItem(
                                value: e['tag'],
                                child: Text(
                                  e['name']!,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _ocrLanguage = v!),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: _target,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '翻译为'),
                      items: ['简体中文', '英语', '日语', '韩语']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _target = v!),
                    ),
                  ),
                  SizedBox(
                    width: 175,
                    child: DropdownButtonFormField<bool>(
                      initialValue: _translator.useGpu,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '推理设备'),
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('CUDA GPU 优先'),
                        ),
                        DropdownMenuItem(value: false, child: Text('CPU')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              _translator.unload();
                              setState(() => _translator.useGpu = v!);
                            },
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _chooseModel,
                    child: const Text('导入本地模型'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _translator.unload();
                            setState(() => _status = '模型已卸载 · 显存已释放');
                          },
                    child: const Text('释放显存'),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (_image != null && _blocks.isNotEmpty) {
                    return _panel(
                      '截图对照',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'translated',
                                label: Text('译文'),
                              ),
                              ButtonSegment(
                                value: 'layout',
                                label: Text('识别原文'),
                              ),
                            ],
                            selected: {_sourceView},
                            onSelectionChanged: (value) =>
                                setState(() => _sourceView = value.first),
                          ),
                          LinkedOcrComparison(
                            preview: _image!.preview,
                            imageWidth: _image!.width,
                            imageHeight: _image!.height,
                            blocks: _sourceView == 'layout'
                                ? _blocks
                                : _translatedBlocks,
                            referenceBlocks: _blocks,
                            leftTitle: _sourceView == 'layout' ? '识别原文' : '译文',
                            onEdit: _sourceView == 'layout' && !_busy
                                ? _editBlock
                                : null,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _copyText(_source.text, '原文已复制'),
                            child: const Text('复制原文'),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _startTextTranslation,
                            child: const Text('翻译原文'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _translation.isEmpty
                                ? null
                                : () => _copyText(_translation, '译文已复制'),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('复制译文'),
                          ),
                        ],
                      ),
                    );
                  }
                  final source = _panel(
                    '原文',
                    TextField(
                      controller: _source,
                      style: translationTextStyle.copyWith(
                        inherit: true,
                        fontSize: 17,
                      ),
                      readOnly: _busy,
                      maxLines: 9,
                      minLines: 9,
                      maxLength: LocalTranslationService.maxCharacters,
                      onChanged: (_) {
                        setState(() {
                          if (_blocks.isNotEmpty) {
                            _blocks = [];
                            _translation = '';
                            _translatedBlocks = [];
                            _status = '已切换自由文本；重新识别图片可恢复坐标排版';
                          }
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: '输入原文',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _source.text.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _source.text),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('已复制原文（制表符分列）'),
                                      ),
                                    );
                                  }
                                },
                          child: const Text('复制原文'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _startTextTranslation,
                          child: const Text('翻译原文'),
                        ),
                      ],
                    ),
                  );
                  final translated = _panel(
                    '译文',
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 235),
                      child: SelectableText(
                        _translation.isEmpty ? '暂无译文' : _translation,
                        style: translationTextStyle.copyWith(
                          inherit: true,
                          fontSize: 17,
                          height: 1.6,
                          color: _translation.isEmpty
                              ? const Color(0xFF98A2B3)
                              : const Color(0xFF182230),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _translation.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _translation),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('译文已复制')),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('复制译文'),
                    ),
                  );
                  if (constraints.maxWidth < 780) {
                    return Column(
                      children: [
                        source,
                        const SizedBox(height: 16),
                        translated,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: source),
                      const SizedBox(width: 16),
                      Expanded(child: translated),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'OCR：${_image?.elapsedMs ?? '—'} ms    首字：${_firstTokenMs ?? '—'} ms    翻译：${_translateMs ?? '—'} ms    （不含模型冷启动）',
                style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
              if (_image != null && _blocks.isEmpty) ...[
                const SizedBox(height: 18),
                _panel(
                  '本次识别图像',
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 210),
                    child: Image.memory(_image!.preview, fit: BoxFit.contain),
                  ),
                  null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _panel(String title, Widget content, Widget? action) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE4E7EC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        content,
        if (action != null) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: action),
        ],
      ],
    ),
  );
}
