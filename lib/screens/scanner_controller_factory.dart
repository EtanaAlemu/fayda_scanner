import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fayda_scanner/screens/scanner_constants.dart';

/// [autoZoom] is off — handheld ID scans use full preview width (no digital zoom).
///
/// [returnImage] on native feeds [ScanFeedbackAnalyzer] (dark scene → torch hint). Brighter scenes
/// shorten exposure, which reduces motion blur with an unsteady hand.
MobileScannerController createScannerController() {
  return MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    torchEnabled: false,
    cameraResolution: ScannerConstants.cameraResolution,
    autoZoom: false,
    initialZoom: 0,
    returnImage: !kIsWeb,
  );
}
