import 'package:flutter/material.dart';

/// Timing, camera targets, and tuning for [ScannerScreen] / gallery resume.
///
/// Tuned for **fast decode** and **shaky hands**: wide ROI, rare AF nudges, aggressive ML Kit rate.
abstract final class ScannerConstants {
  static const Duration onDetectThrottle = Duration(milliseconds: 200);
  static const Duration stabilizationBeforeParse = Duration(milliseconds: 50);

  /// Max-ish analysis target; plugin picks closest supported size per device.
  static const Size cameraResolution = Size(4032, 3024);

  static const Duration galleryNativeSettle = Duration(milliseconds: 400);
  static const Duration afterScannerStopSettle = Duration(milliseconds: 200);
  static const Duration disposeOldScannerDefer = Duration(milliseconds: 150);

  /// Rare pulses — constant [setFocusPoint] can fight continuous AF and soften frames when moving.
  static const Duration autoFocusPulseInterval = Duration(milliseconds: 5500);
}
