import 'dart:async';

import 'package:flutter/foundation.dart' show compute, kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fayda_scanner/screens/result_screen.dart';
import 'package:fayda_scanner/screens/scan_window_layout.dart';
import 'package:fayda_scanner/screens/scanner_constants.dart';
import 'package:fayda_scanner/screens/scanner_controller_factory.dart';
import 'package:fayda_scanner/screens/scanner_gallery_flow.dart';
import 'package:fayda_scanner/screens/scanner_overlay_painter.dart';
import 'package:fayda_scanner/services/parser_service.dart';
import 'package:fayda_scanner/widgets/scanner_bottom_controls.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late MobileScannerController _controller;
  int _cameraGeneration = 0;

  bool _mountLivePreview = true;
  Timer? _autoFocusTimer;

  /// Body [LayoutBuilder] size + [MediaQuery.paddingOf] — matches scan window coords.
  Size _scannerBodySize = Size.zero;
  EdgeInsets _scannerSafePadding = EdgeInsets.zero;

  bool _processing = false;
  DateTime? _lastProcessWindowStart;

  static const bool _logEnabled = true;
  DateTime? _lastOnDetectLogAt;

  void _log(String message) {
    if (!_logEnabled || !kDebugMode) return;
    debugPrint('[Scanner] ${DateTime.now().toIso8601String()} $message');
  }

  String _truncate(String s, [int max = 80]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  void _logControllerState(String where) {
    final s = _controller.value;
    _log(
      '$where controller: initialized=${s.isInitialized} isStarting=${s.isStarting} isRunning=${s.isRunning} zoom=${s.zoomScale.toStringAsFixed(2)} torch=${s.torchState} error=${s.error?.errorCode}',
    );
  }

  @override
  void initState() {
    super.initState();
    _mountLivePreview = true;
    _controller = createScannerController();
    _log('initState(): created controller');
    if (!kIsWeb) {
      _autoFocusTimer = Timer.periodic(
        ScannerConstants.autoFocusPulseInterval,
        (_) => unawaited(_pulseFocusAtScanWindowCenter()),
      );
    }
  }

  Future<void> _pulseFocusAtScanWindowCenter() async {
    if (!mounted || _processing || kIsWeb) return;
    if (!_controller.value.isInitialized || !_controller.value.isRunning) {
      return;
    }
    if (_scannerBodySize.width < 8 || _scannerBodySize.height < 8) return;
    final p = scanWindowNormalizedCenter(
      _scannerBodySize,
      viewInsets: _scannerSafePadding,
    );
    try {
      await _controller.setFocusPoint(p);
    } catch (e) {
      _log('pulseFocusAtScanWindowCenter(): $e');
    }
  }

  void _setProcessing(bool value) {
    if (_processing == value) return;
    if (!mounted) {
      _processing = value;
      return;
    }
    setState(() {
      _processing = value;
    });
    _log('processing=$_processing');
  }

  Future<void> _resumeLiveScanner() async {
    if (!mounted) return;
    try {
      _log('resumeLiveScanner(): start()');
      _logControllerState('before start()');
      await _controller.start();
      _setProcessing(false);
      _log('resumeLiveScanner(): start() OK');
      _logControllerState('after start()');
    } catch (_) {
      _setProcessing(false);
      _log('resumeLiveScanner(): start() threw; recreating controller');
      await _recreateScannerController();
      return;
    }
    _lastProcessWindowStart = null;
  }

  Future<void> _recreateScannerController() async {
    if (!mounted) return;
    _log('recreateScannerController(): begin');
    final old = _controller;
    try {
      _logControllerState('recreateScannerController(): before stop()');
      await old.stop();
      _logControllerState('recreateScannerController(): after stop()');
    } catch (_) {}
    await Future<void>.delayed(ScannerConstants.afterScannerStopSettle);
    if (!mounted) return;

    setState(() {
      _controller = createScannerController();
      _cameraGeneration++;
    });
    _log('recreateScannerController(): new controller; generation=$_cameraGeneration');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(ScannerConstants.disposeOldScannerDefer, () async {
        try {
          old.dispose();
        } catch (_) {}
        if (!mounted) return;
        _setProcessing(false);
        _lastProcessWindowStart = null;
        _log('recreateScannerController(): old disposed');
      });
    });
  }

  Future<void> _resumeScannerAfterGallery() async {
    if (!mounted) return;
    if (kIsWeb) {
      _log('resumeScannerAfterGallery(): web');
      await _resumeLiveScanner();
      return;
    }
    _log('resumeScannerAfterGallery(): waiting native settle');
    await Future<void>.delayed(ScannerConstants.galleryNativeSettle);
    if (!mounted) return;
    try {
      _log('resumeScannerAfterGallery(): resumeLiveScanner()');
      await _resumeLiveScanner();
    } catch (_) {
      _log('resumeScannerAfterGallery(): resumeLiveScanner threw; recreating');
      await _recreateScannerController();
    }
  }

  Future<void> _parsePayloadAndNavigate(String value) async {
    _log('parsePayloadAndNavigate(): start len=${value.length}');
    await Future<void>.delayed(ScannerConstants.stabilizationBeforeParse);
    if (!mounted) return;
    final result = await compute(parseQrPayloadInIsolate, value);
    if (!mounted) return;
    if (result.data != null) {
      final d = result.data!;
      _log(
        'parsePayloadAndNavigate(): parsed OK name="${d.fullName}" version=${d.version} '
        'signatureLen=${d.signature.length} '
        'imageBytesLen=${d.imageBytes.length} pendingImageB64Len=${d.pendingImageBase64?.length ?? 0} '
        '(lazy: WebP bytes load on result screen if pending)',
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(data: result.data!),
        ),
      );
    } else {
      _log('parsePayloadAndNavigate(): parse FAILED error="${result.errorMessage}"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Invalid QR format')),
      );
    }
  }

  @override
  void dispose() {
    _autoFocusTimer?.cancel();
    _log('dispose(): disposing controller');
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRawPayload(String value) async {
    if (_processing) return;
    if (!ParserService.looksLikeCompletePayload(value)) return;

    _log('handleRawPayload(): len=${value.length}');

    final now = DateTime.now();
    if (_lastProcessWindowStart != null &&
        now.difference(_lastProcessWindowStart!) <
            ScannerConstants.onDetectThrottle) {
      return;
    }
    _lastProcessWindowStart = now;
    _setProcessing(true);

    try {
      _log('handleRawPayload(): stop()');
      _logControllerState('before stop()');
      await _controller.stop();
      _logControllerState('after stop()');
    } catch (_) {}

    try {
      _log('handleRawPayload(): parsePayloadAndNavigate()');
      await _parsePayloadAndNavigate(value);
    } finally {
      if (mounted) {
        _log('handleRawPayload(): resumeLiveScanner()');
        await _resumeLiveScanner();
      }
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;

    String? value;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;

    final now = DateTime.now();
    final preview = _truncate(value);
    if (_lastOnDetectLogAt == null ||
        now.difference(_lastOnDetectLogAt!) >
            const Duration(milliseconds: 350)) {
      _lastOnDetectLogAt = now;
      _log('onDetect(): rawLen=${value.length} preview="$preview" complete=${ParserService.looksLikeCompletePayload(value)}');
    }

    if (!ParserService.looksLikeCompletePayload(value)) return;

    await _handleRawPayload(value);
  }

  Future<void> _pickFromGallery() async {
    if (_processing || kIsWeb) {
      if (kIsWeb && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gallery scan is not supported on web.'),
          ),
        );
      }
      return;
    }

    await ScannerGalleryFlow(
      context: context,
      controller: _controller,
      mounted: () => mounted,
      log: _log,
      setProcessing: _setProcessing,
      parsePayloadAndNavigate: _parsePayloadAndNavigate,
      resumeScannerAfterGallery: _resumeScannerAfterGallery,
    ).pickFromGallery();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'Scan from gallery (crop optional)',
              onPressed: _processing ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
            ),
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: _processing
                ? null
                : () {
                    _log('UI: toggleTorch');
                    _controller.toggleTorch();
                  },
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on);
                  case TorchState.auto:
                    return const Icon(Icons.flash_auto);
                  case TorchState.off:
                  case TorchState.unavailable:
                    return const Icon(Icons.flash_off);
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _processing
                ? null
                : () {
                    _log('UI: switchCamera');
                    _controller.switchCamera();
                  },
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layoutSize = constraints.biggest;
          final safe = MediaQuery.paddingOf(context);
          _scannerBodySize = layoutSize;
          _scannerSafePadding = safe;
          final scanWindow = scanWindowForLayout(
            layoutSize,
            viewInsets: safe,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: _mountLivePreview
                    ? MobileScanner(
                        key: ValueKey<int>(_cameraGeneration),
                        controller: _controller,
                        fit: BoxFit.cover,
                        useAppLifecycleState: false,
                        tapToFocus: !kIsWeb,
                        scanWindow: kIsWeb ? null : scanWindow,
                        scanWindowUpdateThreshold: 24,
                        onDetect: _onDetect,
                      )
                    : const ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
              ),
              RepaintBoundary(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ScannerOverlayPainter(
                      color: primary.withValues(alpha: 0.9),
                      scanRect: scanWindow,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ScannerBottomControls(),
              ),
            ],
          );
        },
      ),
    );
  }
}
