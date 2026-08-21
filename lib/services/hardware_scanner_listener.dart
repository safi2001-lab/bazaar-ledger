import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intercepts hardware barcode scanner (Keyboard Wedge) keystrokes
/// and dispatches the scanned barcode string.
class HardwareScannerListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<String> onBarcodeScanned;
  final Duration maxInterKeystrokeDelay;

  const HardwareScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.maxInterKeystrokeDelay = const Duration(milliseconds: 50),
  });

  @override
  State<HardwareScannerListener> createState() => _HardwareScannerListenerState();
}

class _HardwareScannerListenerState extends State<HardwareScannerListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeystrokeTime;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final now = DateTime.now();
    final logicalKey = event.logicalKey;

    // Enter key signals end of barcode transmission from hardware scanner
    if (logicalKey == LogicalKeyboardKey.enter || logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.isNotEmpty) {
        final code = _buffer.toString().trim();
        _buffer.clear();
        if (code.length >= 3) {
          widget.onBarcodeScanned(code);
        }
      }
      return;
    }

    // Measure time between keystrokes
    if (_lastKeystrokeTime != null &&
        now.difference(_lastKeystrokeTime!) > widget.maxInterKeystrokeDelay) {
      // Manual typing detected (too slow to be a hardware laser scanner) -> reset buffer
      _buffer.clear();
    }
    _lastKeystrokeTime = now;

    // Append character if printable
    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      _buffer.write(char);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
