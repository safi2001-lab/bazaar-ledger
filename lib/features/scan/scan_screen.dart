import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Reading a barcode off a packet with the phone camera.
///
/// Pops the scanned string, or null if the shopkeeper backed out. It knows
/// nothing about items: the caller looks the code up, because the same string
/// means "put this on the bill" at the counter and "this is the code for this
/// item" in the editor.
///
/// ## Why the camera at all, when a USB gun is faster
///
/// Because most shops in this bracket do not own a gun. A hardware wedge is
/// four thousand rupees on top of a printer, and the phone is already in the
/// shopkeeper's hand. The wedge path stays the fast one — it is a keyboard,
/// it types into the search field, and a scan is one event and no taps — and
/// this is what a shop without one uses.
///
/// ## One scan, once
///
/// ML Kit reports the same symbol on every frame it can see it, which is
/// thirty times a second. Without a latch the counter would add thirty of the
/// same tin to the bill in the second it takes to move the packet away. The
/// detection is therefore taken exactly once and the screen closes on it.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    // The formats a Pakistani shop actually meets. Narrowing the set makes
    // detection faster and, more usefully, stops the camera reading a QR code
    // on a poster behind the counter as if it were a packet.
    //
    // DataMatrix is here early on purpose: it is what the DRAP track-and-trace
    // mandate puts on medicine packaging, and a pharmacy scanning one should
    // get a code rather than nothing long before the parsing for it lands.
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.dataMatrix,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );

  /// Taken exactly once. See the class comment: without this the counter gains
  /// thirty of the same tin per second.
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .firstOrNull;
    if (code == null) return;

    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Scaffold(
      backgroundColor: t.ink,
      appBar: AppBar(
        title: Text(s.scanTitle),
        actions: [
          BlIconButton(
            icon: Icons.flashlight_on_outlined,
            label: s.scanTorch,
            // A shop aisle in the evening with the shutter half down is the
            // normal case, not the exception.
            onPressed: () => unawaited(_controller.toggleTorch()),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // A permission refusal or a phone with no camera is a sentence,
            // not a stack trace. Both are things a shopkeeper can act on:
            // grant it, or use the search box instead.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(BlTokens.space4),
                child: BlEmpty(
                  icon: Icons.no_photography_outlined,
                  title: switch (error.errorCode) {
                    MobileScannerErrorCode.permissionDenied => s.scanDenied,
                    _ => s.scanNoCamera,
                  },
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                left: BlTokens.space4,
                right: BlTokens.space4,
                bottom:
                    MediaQuery.viewPaddingOf(context).bottom + BlTokens.space5,
              ),
              child: Text(
                s.scanHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: t.paper, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
