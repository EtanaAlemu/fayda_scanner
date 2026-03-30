import 'dart:io';
import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fayda_scanner/services/parser_service.dart';
import 'package:fayda_scanner/utils/scanner_image_utils.dart';

final class _GalleryScanCancelled implements Exception {}

String _shortPath(String path, [int maxTail = 28]) {
  final tail = path.split('/').where((p) => p.isNotEmpty).last;
  if (tail.length <= maxTail) return tail;
  return tail.substring(0, maxTail);
}

/// Pick, crop, and analyze a gallery image for a Fayda-style QR payload.
final class ScannerGalleryFlow {
  static const bool _preferPreciseScan = true;

  ScannerGalleryFlow({
    required this.context,
    required this.controller,
    required this.mounted,
    required this.log,
    required this.setProcessing,
    required this.parsePayloadAndNavigate,
    required this.resumeScannerAfterGallery,
  });

  final BuildContext context;
  final MobileScannerController controller;
  final bool Function() mounted;
  final void Function(String message) log;
  final void Function(bool value) setProcessing;
  final Future<void> Function(String value) parsePayloadAndNavigate;
  final Future<void> Function() resumeScannerAfterGallery;

  final ImagePicker _picker = ImagePicker();

  Barcode? _pickBestSquareLikeCandidate(
    List<Barcode> barcodes,
    Size captureSize,
  ) {
    Barcode? best;
    var bestScore = -1.0;

    for (final b in barcodes) {
      if (b.corners.length < 3) continue;
      final points = b.corners;
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

      final w = (maxX - minX).abs();
      final h = (maxY - minY).abs();
      if (w <= 0 || h <= 0) continue;

      final maxSide = math.max(w, h);
      final minSide = math.min(w, h);
      final aspect = minSide / maxSide; // 1.0 = perfect square

      final area = w * h;
      final captureArea = (captureSize.width > 0 && captureSize.height > 0)
          ? captureSize.width * captureSize.height
          : 1.0;
      final areaRatio = (area / captureArea).clamp(0.0, 1.0);

      // Favor square-ish, reasonably large detections.
      final score = (aspect * 0.75) + (math.sqrt(areaRatio) * 0.25);
      if (score > bestScore) {
        bestScore = score;
        best = b;
      }
    }
    return best;
  }

  Future<void> pickFromGallery() async {
    if (!mounted()) return;
    final messenger = ScaffoldMessenger.of(context);
    final statusText = ValueNotifier<String>('Preparing...');
    var statusVisible = false;
    Route<void>? statusRoute;
    var cancelRequested = false;

    void throwIfCancelled() {
      if (cancelRequested) {
        throw _GalleryScanCancelled();
      }
    }

    Future<void> showStatus(String message) async {
      throwIfCancelled();
      if (!mounted() || !context.mounted) return;
      statusText.value = message;
      if (statusVisible) return;
      statusVisible = true;
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: true,
          onPopInvokedWithResult: (_, _) {
            cancelRequested = true;
          },
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: statusText,
                    builder: (_, value, _) => Text(value),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      statusRoute = route;
      unawaited(
        navigator.push(route).whenComplete(() {
          if (identical(statusRoute, route)) {
            statusRoute = null;
          }
          statusVisible = false;
        }),
      );
    }

    Future<void> clearStatus() async {
      if (!statusVisible || !context.mounted) return;
      final route = statusRoute;
      if (route == null) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      try {
        navigator.removeRoute(route);
      } catch (_) {}
      statusRoute = null;
      statusVisible = false;
    }

    try {
      await showStatus('Opening gallery...');
      log('pickFromGallery(): pickImage()');
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
        maxWidth: _preferPreciseScan ? 4096 : 3200,
        maxHeight: _preferPreciseScan ? 4096 : 3200,
      );
      throwIfCancelled();
      if (xFile == null || !mounted()) return;
      final originalPath = xFile.path;
      log('pickFromGallery(): picked path=${_shortPath(xFile.path)}');
      try {
        final s = await File(originalPath).length();
        log('pickFromGallery(): picked file size=$s bytes');
      } catch (_) {}

      setProcessing(true);
      try {
        await showStatus('Preparing scanner...');
        log('pickFromGallery(): controller.stop()');
        await controller.stop();
        throwIfCancelled();
      } catch (_) {}

      try {
        BarcodeCapture? capture;
        try {
          await showStatus('Analyzing selected image...');
          // Analyze the original image first.
          log('pickFromGallery(): analyzeImage(original) qrOnly');
          capture = await controller.analyzeImage(
            originalPath,
            formats: const [BarcodeFormat.qrCode],
          );
          throwIfCancelled();
          log('pickFromGallery(): analyze done barcodes=${capture?.barcodes.length} (original qrOnly)');

          if (capture == null || capture.barcodes.isEmpty) {
            // Geometry pass: allow all formats to recover corner points even if QR decode fails.
            log('pickFromGallery(): qrOnly=0 -> geometry pass (all formats)');
            capture = await controller.analyzeImage(originalPath);
            throwIfCancelled();
            log('pickFromGallery(): geometry pass barcodes=${capture?.barcodes.length}');
          }

          final geometryCapture = capture;
          if (geometryCapture != null && geometryCapture.barcodes.isNotEmpty) {
            final candidate = _pickBestSquareLikeCandidate(
              geometryCapture.barcodes,
              geometryCapture.size,
            );
            if (candidate != null) {
              await showStatus('Detected code shape. Focusing crop...');
              // Deterministic ML-guided retries: same shape, two paddings.
              final paddings = _preferPreciseScan
                  ? <double>[0.22, 0.36]
                  : <double>[0.30];
              for (final padding in paddings) {
                final focusedPath = await renderFocusedCropFromCornersPng(
                  inputPath: originalPath,
                  corners: candidate.corners,
                  captureSize: geometryCapture.size,
                  paddingFactor: padding,
                  minSidePx: _preferPreciseScan ? 1400 : 900,
                  log: log,
                );
                if (focusedPath == null) continue;
                try {
                  capture = await controller.analyzeImage(
                    focusedPath,
                    formats: const [BarcodeFormat.qrCode],
                  );
                  throwIfCancelled();
                  log(
                    'pickFromGallery(): focused-crop(pad=$padding) barcodes=${capture?.barcodes.length}',
                  );
                } finally {
                  await deleteFileIfExists(focusedPath);
                }
                if (capture != null && capture.barcodes.isNotEmpty) break;
              }
            } else {
              log('pickFromGallery(): geometry found, but no square-like candidate');
            }
          }

          // Manual crop as final fallback only (no random rotation/crop attempts).
          if (capture == null || capture.barcodes.isEmpty) {
            await showStatus('No QR yet. Opening crop tool...');
            await clearStatus();
            log('pickFromGallery(): opening manual crop (final fallback)');
            final cropped = await ImageCropper().cropImage(
              sourcePath: originalPath,
              compressFormat: ImageCompressFormat.jpg,
              compressQuality: 98,
              uiSettings: [
                AndroidUiSettings(
                  toolbarTitle: 'Crop QR',
                  lockAspectRatio: true,
                  initAspectRatio: CropAspectRatioPreset.square,
                ),
                IOSUiSettings(title: 'Crop QR'),
              ],
            );
            throwIfCancelled();
            log('pickFromGallery(): crop result=${cropped == null ? 'null' : _shortPath(cropped.path)}');

            if (cropped == null) {
              await clearStatus();
              if (context.mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('No QR detected. Try a tighter crop.')),
                );
              }
            } else {
              await showStatus('Analyzing cropped image...');
              capture = await controller.analyzeImage(
                cropped.path,
                formats: const [BarcodeFormat.qrCode],
              );
              throwIfCancelled();
              log('pickFromGallery(): analyze done barcodes=${capture?.barcodes.length} (cropped qrOnly)');

              if (capture == null || capture.barcodes.isEmpty) {
                await showStatus('Deep analysis on cropped image...');
                log('pickFromGallery(): cropped qrOnly=0 -> geometry pass (all formats)');
                capture = await controller.analyzeImage(cropped.path);
                throwIfCancelled();
                log('pickFromGallery(): cropped geometry pass barcodes=${capture?.barcodes.length}');
              }

              final croppedGeometry = capture;
              if (croppedGeometry != null && croppedGeometry.barcodes.isNotEmpty) {
                final candidate = _pickBestSquareLikeCandidate(
                  croppedGeometry.barcodes,
                  croppedGeometry.size,
                );
                if (candidate != null) {
                  final paddings = _preferPreciseScan
                      ? <double>[0.16, 0.26, 0.36, 0.48]
                      : <double>[0.26, 0.36];
                  for (final padding in paddings) {
                    await showStatus(
                      'Refining cropped focus (pad ${(padding * 100).round()}%)...',
                    );
                    final focusedPath = await renderFocusedCropFromCornersPng(
                      inputPath: cropped.path,
                      corners: candidate.corners,
                      captureSize: croppedGeometry.size,
                      paddingFactor: padding,
                      minSidePx: _preferPreciseScan ? 1400 : 900,
                      log: log,
                    );
                    if (focusedPath == null) continue;
                    try {
                      capture = await controller.analyzeImage(
                        focusedPath,
                        formats: const [BarcodeFormat.qrCode],
                      );
                      throwIfCancelled();
                      log(
                        'pickFromGallery(): cropped-focused(pad=$padding) barcodes=${capture?.barcodes.length}',
                      );
                    } finally {
                      await deleteFileIfExists(focusedPath);
                    }
                    if (capture != null && capture.barcodes.isNotEmpty) break;
                  }
                } else {
                  log('pickFromGallery(): cropped geometry found, but no square-like candidate');
                }
              }
            }
          }

          if (capture == null || capture.barcodes.isEmpty) {
            await clearStatus();
          }
        } on Exception catch (e) {
          if (context.mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not read QR from image: $e')),
            );
          }
          log('pickFromGallery(): analyzeImage threw $e');
        }

        String? value;
        if (capture != null) {
          for (final b in capture.barcodes) {
            final raw = b.rawValue;
            if (raw != null && raw.trim().isNotEmpty) {
              value = raw;
              break;
            }
          }
        }

        if (value != null) {
          log('pickFromGallery(): extracted rawValue len=${value.length}');
        }
        if (value != null && ParserService.looksLikeCompletePayload(value)) {
          await showStatus('QR recognized. Decoding data...');
          log('pickFromGallery(): got complete payload len=${value.length}');
          await parsePayloadAndNavigate(value);
          throwIfCancelled();
          await clearStatus();
        } else if (context.mounted) {
          await clearStatus();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                value == null
                    ? 'No QR code found in that image.'
                    : 'QR looks incomplete — crop tighter or pick another photo.',
              ),
            ),
          );
          log('pickFromGallery(): payload invalid; valueNull=${value == null} rawLen=${value?.length}');
        }
      } on _GalleryScanCancelled {
        await clearStatus();
      } finally {
        await clearStatus();
        if (mounted()) {
          log('pickFromGallery(): finally -> resumeScannerAfterGallery()');
          await resumeScannerAfterGallery();
        }
      }
    } catch (e) {
      await clearStatus();
      if (mounted() && context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Gallery error: $e')));
        log('pickFromGallery(): outer catch $e');
        await resumeScannerAfterGallery();
      }
    } finally {
      statusText.dispose();
    }
  }
}
