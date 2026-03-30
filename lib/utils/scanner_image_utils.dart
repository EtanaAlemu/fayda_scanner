import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

typedef ScannerLog = void Function(String message);

Future<void> logDecodedImageDimensions(
  ScannerLog log,
  String label,
  String path,
) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    log('$label dimensions=${img.width}x${img.height}');
  } catch (e) {
    log('$label dimensions read failed: $e');
  }
}

/// Center-crop square, optional quarter-turn rotation, upscale to [targetSidePx] PNG.
Future<String?> renderCenteredSquareCropPng({
  required String inputPath,
  required double fractionOfMinSide,
  required int targetSidePx,
  required int rotateQuarterTurns,
  required ScannerLog log,
}) async {
  try {
    final srcBytes = await File(inputPath).readAsBytes();

    final codec = await ui.instantiateImageCodec(srcBytes);
    final frame = await codec.getNextFrame();
    final ui.Image srcImage = frame.image;

    final minSide = math.min(srcImage.width, srcImage.height);
    final cropSide =
        (minSide * fractionOfMinSide).clamp(150.0, minSide.toDouble());

    final srcLeft =
        ((srcImage.width - cropSide) / 2).clamp(0.0, double.infinity);
    final srcTop =
        ((srcImage.height - cropSide) / 2).clamp(0.0, double.infinity);
    final srcRect = ui.Rect.fromLTWH(srcLeft, srcTop, cropSide, cropSide);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final center = targetSidePx / 2.0;
    canvas.translate(center, center);
    final angle = rotateQuarterTurns % 4;
    final rad = (angle == 1
        ? math.pi / 2
        : angle == 2
            ? math.pi
            : angle == 3
                ? 3 * math.pi / 2
                : 0.0);
    if (rad != 0.0) {
      canvas.rotate(rad);
    }
    canvas.translate(-center, -center);

    canvas.drawImageRect(
      srcImage,
      srcRect,
      ui.Rect.fromLTWH(0, 0, targetSidePx.toDouble(), targetSidePx.toDouble()),
      ui.Paint(),
    );

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(targetSidePx, targetSidePx);
    final outBytes = await outImage.toByteData(format: ui.ImageByteFormat.png);
    if (outBytes == null) return null;

    final outPath =
        '${Directory.systemTemp.path}/qr_crop_${DateTime.now().microsecondsSinceEpoch}_${rotateQuarterTurns}_f${fractionOfMinSide.toStringAsFixed(2)}.png';
    await File(outPath).writeAsBytes(outBytes.buffer.asUint8List());
    return outPath;
  } catch (e) {
    log('renderCenteredSquareCropPng(): failed $e');
    return null;
  }
}

/// Auto-crop around detected barcode corners from an analyzed gallery image.
///
/// [corners] can be normalized (0..1) or in camera-space pixels relative to [captureSize].
Future<String?> renderFocusedCropFromCornersPng({
  required String inputPath,
  required List<ui.Offset> corners,
  required ui.Size captureSize,
  double paddingFactor = 0.30,
  int minSidePx = 900,
  ScannerLog? log,
}) async {
  try {
    if (corners.length < 3) return null;

    final srcBytes = await File(inputPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(srcBytes);
    final frame = await codec.getNextFrame();
    final ui.Image srcImage = frame.image;
    final srcW = srcImage.width.toDouble();
    final srcH = srcImage.height.toDouble();

    final isNormalized = corners.every(
      (p) => p.dx >= 0 && p.dy >= 0 && p.dx <= 1.2 && p.dy <= 1.2,
    );

    final points = corners
        .map((p) {
          if (isNormalized) {
            return ui.Offset(
              p.dx.clamp(0.0, 1.0) * srcW,
              p.dy.clamp(0.0, 1.0) * srcH,
            );
          }
          final cw = captureSize.width <= 0 ? srcW : captureSize.width;
          final ch = captureSize.height <= 0 ? srcH : captureSize.height;
          return ui.Offset(
            (p.dx / cw).clamp(0.0, 1.0) * srcW,
            (p.dy / ch).clamp(0.0, 1.0) * srcH,
          );
        })
        .toList(growable: false);

    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points.skip(1)) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    var w = (maxX - minX).abs();
    var h = (maxY - minY).abs();
    if (w < 8 || h < 8) return null;

    final pad = math.max(w, h) * paddingFactor;
    minX = (minX - pad).clamp(0.0, srcW - 1);
    maxX = (maxX + pad).clamp(1.0, srcW);
    minY = (minY - pad).clamp(0.0, srcH - 1);
    maxY = (maxY + pad).clamp(1.0, srcH);
    w = (maxX - minX).clamp(1.0, srcW);
    h = (maxY - minY).clamp(1.0, srcH);

    final targetW = math.max(minSidePx, w.round());
    final targetH = math.max(minSidePx, h.round());

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      srcImage,
      ui.Rect.fromLTWH(minX, minY, w, h),
      ui.Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
      ui.Paint(),
    );

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(targetW, targetH);
    final outBytes = await outImage.toByteData(format: ui.ImageByteFormat.png);
    if (outBytes == null) return null;
    final outPath =
        '${Directory.systemTemp.path}/qr_focus_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(outPath).writeAsBytes(outBytes.buffer.asUint8List());
    log?.call('renderFocusedCropFromCornersPng(): out=${targetW}x$targetH');
    return outPath;
  } catch (e) {
    log?.call('renderFocusedCropFromCornersPng(): failed $e');
    return null;
  }
}

Future<void> deleteFileIfExists(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}
