import 'package:flutter/material.dart';

/// Dimmed overlay with a rounded cutout for the scan window.
class ScannerOverlayPainter extends CustomPainter {
  ScannerOverlayPainter({required this.color, required this.scanRect});

  final Color color;
  final Rect scanRect;

  @override
  void paint(Canvas canvas, Size size) {
    final cutOut = RRect.fromRectAndRadius(scanRect, const Radius.circular(16));

    final overlay = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(cutOut);
    final mask = Path.combine(PathOperation.difference, overlay, hole);

    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(cutOut, borderPaint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scanRect != scanRect;
}
