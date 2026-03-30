import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Center scan window — ML Kit only analyzes barcodes intersecting this region.
///
/// [viewInsets] should be [MediaQuery.paddingOf] for this subtree so the ROI stays off
/// notches and the home indicator while the preview remains full-bleed.
Rect scanWindowForLayout(
  Size layoutSize, {
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final left = viewInsets.left;
  final top = viewInsets.top;
  final right = viewInsets.right;
  final bottom = viewInsets.bottom;
  final innerW = math.max(1.0, layoutSize.width - left - right);
  final innerH = math.max(1.0, layoutSize.height - top - bottom);
  final shortest = math.min(innerW, innerH);
  // Wider square ROI — forgiving when the hand drifts; QR must still intersect this rect.
  final side = (shortest * 0.90).clamp(300.0, 480.0);
  final cx = left + innerW / 2;
  final cy = top + innerH * 0.42;
  return Rect.fromCenter(center: Offset(cx, cy), width: side, height: side);
}

/// Normalized (0–1) point at the scan window center, for [MobileScannerController.setFocusPoint].
Offset scanWindowNormalizedCenter(
  Size layoutSize, {
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  final r = scanWindowForLayout(
    layoutSize,
    viewInsets: viewInsets,
  );
  final w = math.max(1.0, layoutSize.width);
  final h = math.max(1.0, layoutSize.height);
  final nx = (r.center.dx / w).clamp(0.03, 0.97);
  final ny = (r.center.dy / h).clamp(0.03, 0.97);
  return Offset(nx, ny);
}
