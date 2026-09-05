import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/input_test_tracker.dart';

class InputTesterScreen extends StatefulWidget {
  const InputTesterScreen({super.key});

  @override
  State<InputTesterScreen> createState() => _InputTesterScreenState();
}

class _InputTesterScreenState extends State<InputTesterScreen> {
  final _focusNode = FocusNode(debugLabel: '键鼠检测输入焦点');
  final _clock = Stopwatch()..start();
  final _tracker = InputTestTracker();
  final List<_InputLogEntry> _events = <_InputLogEntry>[];
  String _status = '等待输入';
  bool _lastWasDouble = false;

  static final List<List<_KeySpec>> _functionRows = [
    [
      _key(LogicalKeyboardKey.escape, 'Esc'),
      _space(.6),
      _key(LogicalKeyboardKey.f1, 'F1'),
      _key(LogicalKeyboardKey.f2, 'F2'),
      _key(LogicalKeyboardKey.f3, 'F3'),
      _key(LogicalKeyboardKey.f4, 'F4'),
      _space(.4),
      _key(LogicalKeyboardKey.f5, 'F5'),
      _key(LogicalKeyboardKey.f6, 'F6'),
      _key(LogicalKeyboardKey.f7, 'F7'),
      _key(LogicalKeyboardKey.f8, 'F8'),
      _space(.4),
      _key(LogicalKeyboardKey.f9, 'F9'),
      _key(LogicalKeyboardKey.f10, 'F10'),
      _key(LogicalKeyboardKey.f11, 'F11'),
      _key(LogicalKeyboardKey.f12, 'F12'),
      _space(.6),
    ],
  ];

  static final List<List<_KeySpec>> _mainRows = [
    [
      _key(LogicalKeyboardKey.backquote, '`'),
      _key(LogicalKeyboardKey.digit1, '1'),
      _key(LogicalKeyboardKey.digit2, '2'),
      _key(LogicalKeyboardKey.digit3, '3'),
      _key(LogicalKeyboardKey.digit4, '4'),
      _key(LogicalKeyboardKey.digit5, '5'),
      _key(LogicalKeyboardKey.digit6, '6'),
      _key(LogicalKeyboardKey.digit7, '7'),
      _key(LogicalKeyboardKey.digit8, '8'),
      _key(LogicalKeyboardKey.digit9, '9'),
      _key(LogicalKeyboardKey.digit0, '0'),
      _key(LogicalKeyboardKey.minus, '-'),
      _key(LogicalKeyboardKey.equal, '='),
      _key(LogicalKeyboardKey.backspace, 'Backspace', units: 2),
    ],
    [
      _key(LogicalKeyboardKey.tab, 'Tab', units: 1.5),
      _key(LogicalKeyboardKey.keyQ, 'Q'),
      _key(LogicalKeyboardKey.keyW, 'W'),
      _key(LogicalKeyboardKey.keyE, 'E'),
      _key(LogicalKeyboardKey.keyR, 'R'),
      _key(LogicalKeyboardKey.keyT, 'T'),
      _key(LogicalKeyboardKey.keyY, 'Y'),
      _key(LogicalKeyboardKey.keyU, 'U'),
      _key(LogicalKeyboardKey.keyI, 'I'),
      _key(LogicalKeyboardKey.keyO, 'O'),
      _key(LogicalKeyboardKey.keyP, 'P'),
      _key(LogicalKeyboardKey.bracketLeft, '['),
      _key(LogicalKeyboardKey.bracketRight, ']'),
      _key(LogicalKeyboardKey.backslash, r'\', units: 1.5),
    ],
    [
      _key(LogicalKeyboardKey.capsLock, 'Caps', units: 1.8),
      _key(LogicalKeyboardKey.keyA, 'A'),
      _key(LogicalKeyboardKey.keyS, 'S'),
      _key(LogicalKeyboardKey.keyD, 'D'),
      _key(LogicalKeyboardKey.keyF, 'F'),
      _key(LogicalKeyboardKey.keyG, 'G'),
      _key(LogicalKeyboardKey.keyH, 'H'),
      _key(LogicalKeyboardKey.keyJ, 'J'),
      _key(LogicalKeyboardKey.keyK, 'K'),
      _key(LogicalKeyboardKey.keyL, 'L'),
      _key(LogicalKeyboardKey.semicolon, ';'),
      _key(LogicalKeyboardKey.quoteSingle, "'"),
      _key(LogicalKeyboardKey.enter, 'Enter', units: 2.2),
    ],
    [
      _key(LogicalKeyboardKey.shiftLeft, 'Shift', units: 2.3),
      _key(LogicalKeyboardKey.keyZ, 'Z'),
      _key(LogicalKeyboardKey.keyX, 'X'),
      _key(LogicalKeyboardKey.keyC, 'C'),
      _key(LogicalKeyboardKey.keyV, 'V'),
      _key(LogicalKeyboardKey.keyB, 'B'),
      _key(LogicalKeyboardKey.keyN, 'N'),
      _key(LogicalKeyboardKey.keyM, 'M'),
      _key(LogicalKeyboardKey.comma, ','),
      _key(LogicalKeyboardKey.period, '.'),
      _key(LogicalKeyboardKey.slash, '/'),
      _key(LogicalKeyboardKey.shiftRight, 'Shift', units: 2.7),
    ],
    [
      _key(LogicalKeyboardKey.controlLeft, 'Ctrl', units: 1.4),
      _key(LogicalKeyboardKey.metaLeft, 'Win', units: 1.2),
      _key(LogicalKeyboardKey.altLeft, 'Alt', units: 1.2),
      _key(LogicalKeyboardKey.space, 'Space', units: 6.4),
      _key(LogicalKeyboardKey.altRight, 'Alt', units: 1.2),
      _key(LogicalKeyboardKey.metaRight, 'Win', units: 1.2),
      _key(LogicalKeyboardKey.contextMenu, 'Menu', units: 1.2),
      _key(LogicalKeyboardKey.controlRight, 'Ctrl', units: 1.4),
    ],
  ];

  static final List<List<_KeySpec>> _navigationRows = [
    [
      _key(LogicalKeyboardKey.insert, 'Ins'),
      _key(LogicalKeyboardKey.home, 'Home'),
      _key(LogicalKeyboardKey.pageUp, 'PgUp'),
    ],
    [
      _key(LogicalKeyboardKey.delete, 'Del'),
      _key(LogicalKeyboardKey.end, 'End'),
      _key(LogicalKeyboardKey.pageDown, 'PgDn'),
    ],
    [_space(3)],
    [_space(1), _key(LogicalKeyboardKey.arrowUp, '↑'), _space(1)],
    [
      _key(LogicalKeyboardKey.arrowLeft, '←'),
      _key(LogicalKeyboardKey.arrowDown, '↓'),
      _key(LogicalKeyboardKey.arrowRight, '→'),
    ],
  ];

  static final List<List<_KeySpec>> _numpadRows = [
    [
      _key(LogicalKeyboardKey.numLock, 'Num'),
      _key(LogicalKeyboardKey.numpadDivide, '/'),
      _key(LogicalKeyboardKey.numpadMultiply, '*'),
      _key(LogicalKeyboardKey.numpadSubtract, '-'),
    ],
    [
      _key(LogicalKeyboardKey.numpad7, '7'),
      _key(LogicalKeyboardKey.numpad8, '8'),
      _key(LogicalKeyboardKey.numpad9, '9'),
      _key(LogicalKeyboardKey.numpadAdd, '+'),
    ],
    [
      _key(LogicalKeyboardKey.numpad4, '4'),
      _key(LogicalKeyboardKey.numpad5, '5'),
      _key(LogicalKeyboardKey.numpad6, '6'),
      _space(1),
    ],
    [
      _key(LogicalKeyboardKey.numpad1, '1'),
      _key(LogicalKeyboardKey.numpad2, '2'),
      _key(LogicalKeyboardKey.numpad3, '3'),
      _key(LogicalKeyboardKey.numpadEnter, 'Enter'),
    ],
    [
      _key(LogicalKeyboardKey.numpad0, '0', units: 2),
      _key(LogicalKeyboardKey.numpadDecimal, '.'),
      _space(1),
    ],
  ];

  static final List<_KeySpec> _systemKeys = [
    _key(LogicalKeyboardKey.printScreen, 'PrtSc'),
    _key(LogicalKeyboardKey.scrollLock, 'ScrLk'),
    _key(LogicalKeyboardKey.pause, 'Pause'),
  ];

  static final Set<int> _displayedKeyIds = {
    for (final row in [
      ..._functionRows,
      ..._mainRows,
      ..._navigationRows,
      ..._numpadRows,
      _systemKeys,
    ])
      for (final spec in row)
        if (spec.key != null) spec.key!.keyId,
  };

  static const List<_MouseButtonSpec> _mouseButtons = [
    _MouseButtonSpec(kPrimaryMouseButton, '鼠标左键'),
    _MouseButtonSpec(kMiddleMouseButton, '鼠标中键'),
    _MouseButtonSpec(kSecondaryMouseButton, '鼠标右键'),
    _MouseButtonSpec(kBackMouseButton, '鼠标侧键 后退'),
    _MouseButtonSpec(kForwardMouseButton, '鼠标侧键 前进'),
  ];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final keyId = event.logicalKey.keyId;
    if (event is KeyUpEvent) {
      setState(() => _tracker.keyboardUp(keyId));
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    final result = _tracker.keyboardDown(
      keyId: keyId,
      timestampMs: _clock.elapsedMilliseconds,
    );
    if (!result.accepted) return KeyEventResult.handled;
    final label = _keyLabel(event.logicalKey);
    setState(() {
      _lastWasDouble = result.isDoubleTap;
      _status = result.isDoubleTap
          ? '检测到键盘双击：$label · 此键累计 ${result.doubleTapCount} 次'
          : '按键已触发：$label · 按下 ${result.pressCount} 次';
      _addEvent(
        result.isDoubleTap ? '键盘双击' : '键盘按下',
        label,
        result.isDoubleTap,
      );
    });
    return KeyEventResult.handled;
  }

  void _handlePointerDown(PointerEvent event) {
    final newButtons = <int>{
      for (final spec in _mouseButtons)
        if ((event.buttons & spec.button) != 0 &&
            !_tracker.activeMouseButtons.contains(spec.button))
          spec.button,
    };
    final buttons = _buttonSet(event.buttons);
    if (newButtons.isEmpty &&
        buttons.length == _tracker.activeMouseButtons.length &&
        buttons.containsAll(_tracker.activeMouseButtons)) {
      return;
    }
    setState(() {
      _tracker.mouseButtonsChanged(
        buttons.intersection(_tracker.activeMouseButtons),
      );
      for (final button in newButtons) {
        final result = _tracker.mouseDown(
          button: button,
          timestampMs: _clock.elapsedMilliseconds,
        );
        final label = _mouseLabel(button);
        _lastWasDouble = result.isDoubleTap;
        _status = result.isDoubleTap
            ? '检测到鼠标双击：$label · 累计 ${result.doubleTapCount} 次'
            : '鼠标按键已触发：$label · 点击 ${result.pressCount} 次';
        _addEvent(
          result.isDoubleTap ? '鼠标双击' : '鼠标点击',
          label,
          result.isDoubleTap,
        );
      }
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    setState(() => _tracker.mouseButtonsChanged(_buttonSet(event.buttons)));
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final label = event.scrollDelta.dy < 0 ? '滚轮向上' : '滚轮向下';
    setState(() {
      _tracker.recordScroll(event.scrollDelta.dy);
      _lastWasDouble = false;
      _status =
          '$label已触发 · 上 ${_tracker.scrollUpCount} / 下 ${_tracker.scrollDownCount}';
      _addEvent('鼠标滚轮', label, false);
    });
  }

  Set<int> _buttonSet(int buttons) => {
    for (final spec in _mouseButtons)
      if ((buttons & spec.button) != 0) spec.button,
  };

  void _addEvent(String type, String input, bool warning) {
    _events.insert(
      0,
      _InputLogEntry(
        time: _formatElapsed(_clock.elapsedMilliseconds),
        type: type,
        input: input,
        warning: warning,
      ),
    );
    if (_events.length > 20) _events.removeLast();
  }

  void _reset() {
    setState(() {
      _tracker.reset();
      _events.clear();
      _lastWasDouble = false;
      _status = '测试记录已重置 · 等待新的键盘或鼠标输入';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _focusNode.requestFocus,
        child: ColoredBox(
          color: const Color(0xFFF5F7FA),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final inset = compact ? 16.0 : 28.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    inset,
                    compact ? 16 : 24,
                    inset,
                    28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(compact),
                      const SizedBox(height: 16),
                      _buildStatusBanner(),
                      const SizedBox(height: 16),
                      _buildSummary(),
                      const SizedBox(height: 18),
                      _buildKeyboardPanel(),
                      const SizedBox(height: 18),
                      _buildLowerPanels(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '键盘与鼠标检测',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
    final reset = OutlinedButton.icon(
      onPressed: _reset,
      icon: const Icon(Icons.restart_alt_rounded),
      label: const Text('重置测试'),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 12), reset],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        reset,
      ],
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: _lastWasDouble
            ? const Color(0xFFFFF1F0)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _lastWasDouble
              ? const Color(0xFFF97066)
              : const Color(0xFF93C5FD),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _lastWasDouble
                ? Icons.warning_amber_rounded
                : Icons.sensors_rounded,
            color: _lastWasDouble
                ? const Color(0xFFD92D20)
                : const Color(0xFF2563EB),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              key: const ValueKey('input-test-status'),
              style: TextStyle(
                color: _lastWasDouble
                    ? const Color(0xFFB42318)
                    : const Color(0xFF1D4ED8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            '正在监听',
            style: TextStyle(
              color: Color(0xFF027A48),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final tested = _tracker.testedKeyboardKeys
        .intersection(_displayedKeyIds)
        .length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryChip(
          icon: Icons.keyboard_rounded,
          label: '已测键位',
          value: '$tested / ${_displayedKeyIds.length}',
        ),
        _SummaryChip(
          icon: Icons.touch_app_rounded,
          label: '键盘触发',
          value: '${_tracker.keyboardTotalPresses}',
        ),
        _SummaryChip(
          icon: Icons.warning_amber_rounded,
          label: '键盘双击',
          value: '${_tracker.keyboardDoubleTapTotal} 次',
          warning: _tracker.keyboardDoubleTapTotal > 0,
        ),
        _SummaryChip(
          icon: Icons.mouse_rounded,
          label: '鼠标双击',
          value: '${_tracker.mouseDoubleTapTotal} 次',
          warning: _tracker.mouseDoubleTapTotal > 0,
        ),
      ],
    );
  }

  Widget _buildKeyboardPanel() {
    return _Panel(
      title: '全键盘键位检测',
      icon: Icons.keyboard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 14,
            runSpacing: 7,
            children: [
              _KeyboardLegend(color: Colors.white, label: '未触发'),
              _KeyboardLegend(color: Color(0xFF2563EB), label: '正在按下'),
              _KeyboardLegend(color: Color(0xFFECFDF3), label: '已经触发'),
              _KeyboardLegend(
                color: Color(0xFFFFF1F0),
                borderColor: Color(0xFFF04438),
                label: '检测到双击',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1040,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 694, child: _buildRows(_functionRows)),
                      const SizedBox(width: 16),
                      SizedBox(width: 134, child: _buildKeyRow(_systemKeys)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 694, child: _buildRows(_mainRows)),
                      const SizedBox(width: 16),
                      SizedBox(width: 134, child: _buildRows(_navigationRows)),
                      const SizedBox(width: 16),
                      SizedBox(width: 180, child: _buildRows(_numpadRows)),
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

  Widget _buildRows(List<List<_KeySpec>> rows) {
    return Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          _buildKeyRow(rows[index]),
          if (index != rows.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildKeyRow(List<_KeySpec> specs) {
    const unit = 42.0;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          for (var index = 0; index < specs.length; index++) ...[
            SizedBox(
              width: specs[index].units * unit,
              child: specs[index].key == null
                  ? const SizedBox.shrink()
                  : _KeyboardKeycap(
                      spec: specs[index],
                      active: _tracker.activeKeyboardKeys.contains(
                        specs[index].key!.keyId,
                      ),
                      tested: _tracker.testedKeyboardKeys.contains(
                        specs[index].key!.keyId,
                      ),
                      presses:
                          _tracker.keyboardPressCounts[specs[index]
                              .key!
                              .keyId] ??
                          0,
                      doubles:
                          _tracker.keyboardDoubleTapCounts[specs[index]
                              .key!
                              .keyId] ??
                          0,
                    ),
            ),
            if (index != specs.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildLowerPanels() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mouse = _buildMousePanel();
        final diagnostics = _buildDiagnosticsPanel();
        if (constraints.maxWidth < 900) {
          return Column(
            children: [mouse, const SizedBox(height: 18), diagnostics],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 430, child: mouse),
            const SizedBox(width: 18),
            Expanded(child: diagnostics),
          ],
        );
      },
    );
  }

  Widget _buildMousePanel() {
    return _Panel(
      title: '鼠标键位检测',
      icon: Icons.mouse_rounded,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        onPointerCancel: (_) =>
            setState(() => _tracker.mouseButtonsChanged(const <int>{})),
        onPointerSignal: _handlePointerSignal,
        child: Container(
          key: const ValueKey('mouse-test-area'),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 245),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD0D5DD)),
          ),
          child: Column(
            children: [
              _MouseDiagram(tracker: _tracker),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final spec in _mouseButtons)
                    _MouseStatPill(
                      label: spec.label,
                      count: _tracker.mousePressCounts[spec.button] ?? 0,
                      active: _tracker.activeMouseButtons.contains(spec.button),
                    ),
                  _MouseStatPill(
                    label: '滚轮 ↑',
                    count: _tracker.scrollUpCount,
                    active: false,
                  ),
                  _MouseStatPill(
                    label: '滚轮 ↓',
                    count: _tracker.scrollDownCount,
                    active: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    return _Panel(
      title: '双击判定与触发记录',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('双击间隔', style: TextStyle(fontWeight: FontWeight.w700)),
              Expanded(
                child: Slider(
                  value: _tracker.doubleTapThresholdMs.toDouble(),
                  min: 150,
                  max: 600,
                  divisions: 18,
                  label: '${_tracker.doubleTapThresholdMs} ms',
                  onChanged: (value) => setState(
                    () => _tracker.doubleTapThresholdMs = value.round(),
                  ),
                ),
              ),
              SizedBox(
                width: 66,
                child: Text(
                  '${_tracker.doubleTapThresholdMs} ms',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          if (_events.isEmpty)
            const SizedBox(
              height: 170,
              child: Center(
                child: Text(
                  '尚无触发记录',
                  style: TextStyle(color: Color(0xFF98A2B3)),
                ),
              ),
            )
          else
            SizedBox(
              height: 170,
              child: ListView.separated(
                itemCount: _events.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            event.time,
                            style: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 82,
                          child: Text(
                            event.type,
                            style: TextStyle(
                              color: event.warning
                                  ? const Color(0xFFD92D20)
                                  : const Color(0xFF475467),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            event.input,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _keyLabel(LogicalKeyboardKey key) {
    for (final row in [
      ..._functionRows,
      ..._mainRows,
      ..._navigationRows,
      ..._numpadRows,
      _systemKeys,
    ]) {
      for (final spec in row) {
        if (spec.key?.keyId == key.keyId) return spec.label;
      }
    }
    final label = key.keyLabel.trim();
    return label.isEmpty ? (key.debugName ?? '未知按键') : label;
  }

  String _mouseLabel(int button) {
    return _mouseButtons
        .firstWhere(
          (spec) => spec.button == button,
          orElse: () => _MouseButtonSpec(button, '鼠标按键 $button'),
        )
        .label;
  }

  static String _formatElapsed(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static _KeySpec _key(
    LogicalKeyboardKey key,
    String label, {
    double units = 1,
  }) => _KeySpec(key: key, label: label, units: units);

  static _KeySpec _space(double units) =>
      _KeySpec(key: null, label: '', units: units);
}

class _KeySpec {
  const _KeySpec({required this.key, required this.label, required this.units});

  final LogicalKeyboardKey? key;
  final String label;
  final double units;
}

class _KeyboardKeycap extends StatelessWidget {
  const _KeyboardKeycap({
    required this.spec,
    required this.active,
    required this.tested,
    required this.presses,
    required this.doubles,
  });

  final _KeySpec spec;
  final bool active;
  final bool tested;
  final int presses;
  final int doubles;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFF2563EB)
        : tested
        ? const Color(0xFFECFDF3)
        : Colors.white;
    final foreground = active
        ? Colors.white
        : tested
        ? const Color(0xFF027A48)
        : const Color(0xFF344054);
    return AnimatedContainer(
      key: ValueKey('keyboard-key-${spec.key!.keyId}'),
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: doubles > 0
              ? const Color(0xFFF04438)
              : active
              ? const Color(0xFF1D4ED8)
              : tested
              ? const Color(0xFF6CE9A6)
              : const Color(0xFFD0D5DD),
          width: doubles > 0 ? 1.5 : 1,
        ),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Color(0x332563EB),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: foreground,
                fontSize: spec.label.length > 5 ? 9 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (presses > 0)
            Positioned(
              left: 4,
              bottom: 2,
              child: Text(
                '$presses',
                style: TextStyle(
                  color: active ? Colors.white70 : const Color(0xFF98A2B3),
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (doubles > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFD92D20),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$doubles',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyboardLegend extends StatelessWidget {
  const _KeyboardLegend({
    required this.color,
    required this.label,
    this.borderColor = const Color(0xFFD0D5DD),
  });

  final Color color;
  final Color borderColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
        ),
      ],
    );
  }
}

class _MouseDiagram extends StatelessWidget {
  const _MouseDiagram({required this.tracker});

  final InputTestTracker tracker;

  @override
  Widget build(BuildContext context) {
    Color colorFor(int button) {
      if (tracker.activeMouseButtons.contains(button)) {
        return const Color(0xFF2563EB);
      }
      if (tracker.testedMouseButtons.contains(button)) {
        return const Color(0xFFD1FADF);
      }
      return Colors.white;
    }

    return SizedBox(
      width: 180,
      height: 125,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 32,
            top: 2,
            child: Container(
              width: 116,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: const Color(0xFF98A2B3), width: 1.5),
              ),
            ),
          ),
          Positioned(
            left: 33,
            top: 3,
            child: Container(
              width: 56,
              height: 58,
              decoration: BoxDecoration(
                color: colorFor(kPrimaryMouseButton),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(46),
                  bottomRight: Radius.circular(9),
                ),
              ),
            ),
          ),
          Positioned(
            right: 33,
            top: 3,
            child: Container(
              width: 56,
              height: 58,
              decoration: BoxDecoration(
                color: colorFor(kSecondaryMouseButton),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(46),
                  bottomLeft: Radius.circular(9),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            child: Container(
              width: 19,
              height: 38,
              decoration: BoxDecoration(
                color: colorFor(kMiddleMouseButton),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF667085)),
              ),
              child: const Icon(Icons.unfold_more_rounded, size: 13),
            ),
          ),
          Positioned(
            left: 16,
            top: 66,
            child: _SideMouseButton(
              label: '后退',
              active: tracker.activeMouseButtons.contains(kBackMouseButton),
              tested: tracker.testedMouseButtons.contains(kBackMouseButton),
            ),
          ),
          Positioned(
            left: 16,
            top: 92,
            child: _SideMouseButton(
              label: '前进',
              active: tracker.activeMouseButtons.contains(kForwardMouseButton),
              tested: tracker.testedMouseButtons.contains(kForwardMouseButton),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMouseButton extends StatelessWidget {
  const _SideMouseButton({
    required this.label,
    required this.active,
    required this.tested,
  });

  final String label;
  final bool active;
  final bool tested;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF2563EB)
            : tested
            ? const Color(0xFFD1FADF)
            : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFF98A2B3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : const Color(0xFF475467),
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF1F0) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: warning ? const Color(0xFFFDA29B) : const Color(0xFFE4E7EC),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: warning ? const Color(0xFFD92D20) : const Color(0xFF2563EB),
          ),
          const SizedBox(width: 7),
          Text('$label  ', style: const TextStyle(color: Color(0xFF667085))),
          Text(
            value,
            style: TextStyle(
              color: warning
                  ? const Color(0xFFD92D20)
                  : const Color(0xFF101828),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MouseStatPill extends StatelessWidget {
  const _MouseStatPill({
    required this.label,
    required this.count,
    required this.active,
  });

  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2563EB) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: active ? const Color(0xFF2563EB) : const Color(0xFFD0D5DD),
        ),
      ),
      child: Text(
        '$label  $count',
        style: TextStyle(
          color: active ? Colors.white : const Color(0xFF475467),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MouseButtonSpec {
  const _MouseButtonSpec(this.button, this.label);

  final int button;
  final String label;
}

class _InputLogEntry {
  const _InputLogEntry({
    required this.time,
    required this.type,
    required this.input,
    required this.warning,
  });

  final String time;
  final String type;
  final String input;
  final bool warning;
}
