class InputTriggerResult {
  const InputTriggerResult({
    required this.accepted,
    required this.isDoubleTap,
    required this.pressCount,
    required this.doubleTapCount,
  });

  const InputTriggerResult.ignored()
    : accepted = false,
      isDoubleTap = false,
      pressCount = 0,
      doubleTapCount = 0;

  final bool accepted;
  final bool isDoubleTap;
  final int pressCount;
  final int doubleTapCount;
}

class InputTestTracker {
  InputTestTracker({this.doubleTapThresholdMs = 300});

  int doubleTapThresholdMs;

  final Set<int> activeKeyboardKeys = <int>{};
  final Set<int> testedKeyboardKeys = <int>{};
  final Map<int, int> keyboardPressCounts = <int, int>{};
  final Map<int, int> keyboardDoubleTapCounts = <int, int>{};
  final Map<int, int> _keyboardCandidateAt = <int, int>{};

  final Set<int> activeMouseButtons = <int>{};
  final Set<int> testedMouseButtons = <int>{};
  final Map<int, int> mousePressCounts = <int, int>{};
  final Map<int, int> mouseDoubleTapCounts = <int, int>{};
  final Map<int, int> _mouseCandidateAt = <int, int>{};

  int scrollUpCount = 0;
  int scrollDownCount = 0;

  int get keyboardTotalPresses => keyboardPressCounts.values.fold(0, _sum);
  int get keyboardDoubleTapTotal =>
      keyboardDoubleTapCounts.values.fold(0, _sum);
  int get mouseTotalPresses => mousePressCounts.values.fold(0, _sum);
  int get mouseDoubleTapTotal => mouseDoubleTapCounts.values.fold(0, _sum);

  InputTriggerResult keyboardDown({
    required int keyId,
    required int timestampMs,
    bool isRepeat = false,
  }) {
    if (isRepeat || activeKeyboardKeys.contains(keyId)) {
      return const InputTriggerResult.ignored();
    }
    activeKeyboardKeys.add(keyId);
    testedKeyboardKeys.add(keyId);
    final presses = (keyboardPressCounts[keyId] ?? 0) + 1;
    keyboardPressCounts[keyId] = presses;
    final isDouble = _recordCandidate(
      candidates: _keyboardCandidateAt,
      inputId: keyId,
      timestampMs: timestampMs,
    );
    var doubles = keyboardDoubleTapCounts[keyId] ?? 0;
    if (isDouble) {
      doubles++;
      keyboardDoubleTapCounts[keyId] = doubles;
    }
    return InputTriggerResult(
      accepted: true,
      isDoubleTap: isDouble,
      pressCount: presses,
      doubleTapCount: doubles,
    );
  }

  void keyboardUp(int keyId) => activeKeyboardKeys.remove(keyId);

  InputTriggerResult mouseDown({
    required int button,
    required int timestampMs,
  }) {
    if (activeMouseButtons.contains(button)) {
      return const InputTriggerResult.ignored();
    }
    activeMouseButtons.add(button);
    testedMouseButtons.add(button);
    final presses = (mousePressCounts[button] ?? 0) + 1;
    mousePressCounts[button] = presses;
    final isDouble = _recordCandidate(
      candidates: _mouseCandidateAt,
      inputId: button,
      timestampMs: timestampMs,
    );
    var doubles = mouseDoubleTapCounts[button] ?? 0;
    if (isDouble) {
      doubles++;
      mouseDoubleTapCounts[button] = doubles;
    }
    return InputTriggerResult(
      accepted: true,
      isDoubleTap: isDouble,
      pressCount: presses,
      doubleTapCount: doubles,
    );
  }

  void mouseButtonsChanged(Set<int> currentButtons) {
    activeMouseButtons.removeWhere(
      (button) => !currentButtons.contains(button),
    );
  }

  void recordScroll(double deltaY) {
    if (deltaY < 0) {
      scrollUpCount++;
    } else if (deltaY > 0) {
      scrollDownCount++;
    }
  }

  void reset() {
    activeKeyboardKeys.clear();
    testedKeyboardKeys.clear();
    keyboardPressCounts.clear();
    keyboardDoubleTapCounts.clear();
    _keyboardCandidateAt.clear();
    activeMouseButtons.clear();
    testedMouseButtons.clear();
    mousePressCounts.clear();
    mouseDoubleTapCounts.clear();
    _mouseCandidateAt.clear();
    scrollUpCount = 0;
    scrollDownCount = 0;
  }

  bool _recordCandidate({
    required Map<int, int> candidates,
    required int inputId,
    required int timestampMs,
  }) {
    final previous = candidates[inputId];
    if (previous != null &&
        timestampMs >= previous &&
        timestampMs - previous <= doubleTapThresholdMs) {
      candidates.remove(inputId);
      return true;
    }
    candidates[inputId] = timestampMs;
    return false;
  }

  static int _sum(int total, int value) => total + value;
}
