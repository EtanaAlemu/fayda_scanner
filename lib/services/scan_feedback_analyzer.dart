import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Lightweight scene hints from the barcode frame (not a separate on-device ML model).
///
/// When [returnImage] is enabled, JPEG bytes give rough luminance; otherwise only
/// [Barcode.size] vs frame size is used ("too small in frame").
class ScanFeedbackAnalyzer {
  ScanFeedbackAnalyzer._();

  /// Smallest QR bounding-box area (relative to full frame) before we suggest moving closer.
  static const double _minQrAreaRatio = 0.018;

  /// Mean luma 0–255; below → dark scene, above → likely washout / glare.
  static const double _darkLuma = 42;
  static const double _brightLuma = 208;

  /// Partial reads are prioritized; then lighting; then QR size.
  static Future<String?> analyze({
    required Uint8List? jpegFrame,
    required Size frameSize,
    Barcode? barcode,
    required bool partialPayload,
  }) async {
    if (partialPayload) {
      return 'Shaky or moving — rest elbows on your body, use light or torch (less blur), keep QR in the frame';
    }

    if (jpegFrame == null ||
        jpegFrame.isEmpty ||
        frameSize.width <= 0 ||
        frameSize.height <= 0) {
      return _sizeOnlyHint(barcode, frameSize);
    }

    final luma = await _meanLuminance(jpegFrame);
    if (luma != null) {
      if (luma < _darkLuma) {
        return 'Scene looks dark — move to brighter light or turn the torch on';
      }
      if (luma > _brightLuma) {
        return 'Very bright — tilt to reduce glare or reflections on the QR';
      }
    }

    return _sizeOnlyHint(barcode, frameSize);
  }

  static String? _sizeOnlyHint(Barcode? barcode, Size frameSize) {
    final bc = barcode;
    if (bc == null) return null;
    final w = bc.size.width;
    final h = bc.size.height;
    if (w <= 0 || h <= 0) return null;
    final qrArea = w * h;
    final frameArea = frameSize.width * frameSize.height;
    if (frameArea <= 0) return null;
    if (qrArea / frameArea < _minQrAreaRatio) {
      return 'QR looks small — move closer so it fills more of the frame';
    }
    return null;
  }

  /// Downscale aggressively to keep this cheap on the UI isolate.
  static Future<double?> _meanLuminance(Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg, targetWidth: 120);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      var sum = 0.0;
      var n = 0;
      for (var i = 0; i + 3 < bd.lengthInBytes; i += 4) {
        final r = bd.getUint8(i).toDouble();
        final g = bd.getUint8(i + 1).toDouble();
        final b = bd.getUint8(i + 2).toDouble();
        sum += 0.299 * r + 0.587 * g + 0.114 * b;
        n++;
      }
      if (n == 0) return null;
      return sum / n;
    } catch (_) {
      return null;
    }
  }
}
