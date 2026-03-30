import 'dart:convert';
import 'dart:typed_data';

import 'package:fayda_scanner/models/parsed_qr_data.dart';

/// Parses QR raw strings of the form:
/// `[BASE64_WEBP]:DLT:[FULL_NAME]:V:[VERSION]:G:[GENDER]:M:A:[ID_NUMBER]:D:[DOB]:SIGN:[JWT]`
class ParserService {
  static const String _delimiter = ':DLT:';

  /// Rejects obviously partial reads from the scanner pipeline.
  static bool looksLikeCompletePayload(String raw) {
    final t = raw.trim();
    return t.contains(_delimiter) && t.contains(':SIGN:');
  }

  /// [decodeImage]: when `false`, skips Base64 decode and sets [ParsedQRData.pendingImageBase64] instead.
  static ParsedQRData parse(String raw, {bool decodeImage = true}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty QR payload');
    }

    final dltIndex = trimmed.indexOf(_delimiter);
    if (dltIndex < 0) {
      throw const FormatException('Invalid QR format');
    }

    final imagePart = trimmed.substring(0, dltIndex).trim();
    final tail = trimmed.substring(dltIndex + _delimiter.length).trim();
    if (tail.isEmpty) {
      throw const FormatException('Invalid QR format');
    }

    Uint8List imageBytes = Uint8List(0);
    var imageOk = false;
    String? pendingB64;

    final normalized = _normalizeBase64(imagePart);

    if (decodeImage) {
      try {
        if (normalized.isNotEmpty) {
          imageBytes = base64Decode(normalized);
          imageOk = true;
        }
      } on FormatException {
        imageOk = false;
        imageBytes = Uint8List(0);
      }
    } else {
      pendingB64 = normalized.isNotEmpty ? normalized : null;
    }

    final signMarker = ':SIGN:';
    final signIndex = trimmed.indexOf(signMarker);
    final rawSignedPayload = signIndex > 0
        ? trimmed.substring(0, signIndex)
        : '$imagePart$_delimiter$tail';

    final parts = tail.split(':');
    if (parts.isEmpty) {
      throw const FormatException('Invalid QR format');
    }

    var fullName = parts.first.trim();
    var version = '';
    var gender = '';
    var idNumber = '';
    var dob = '';
    var signature = '';

    var i = 1;
    while (i < parts.length) {
      final key = parts[i].trim();
      if (key == 'SIGN') {
        signature = parts.sublist(i + 1).join(':').trim();
        break;
      }

      if (key == 'M' &&
          i + 2 < parts.length &&
          parts[i + 1].trim() == 'A') {
        idNumber = parts[i + 2].trim();
        i += 3;
        continue;
      }

      if (i + 1 >= parts.length) {
        break;
      }
      final value = parts[i + 1].trim();
      switch (key) {
        case 'V':
          version = value;
          break;
        case 'G':
          gender = value;
          break;
        case 'A':
          idNumber = value;
          break;
        case 'D':
          dob = value;
          break;
        default:
          break;
      }
      i += 2;
    }

    return ParsedQRData(
      imageBytes: imageBytes,
      imageDecodedSuccessfully: imageOk,
      fullName: fullName,
      version: version,
      gender: gender,
      idNumber: idNumber,
      dob: dob,
      signature: signature,
      rawPayloadTail: tail,
      rawSignedPayload: rawSignedPayload,
      pendingImageBase64: pendingB64,
    );
  }

  static String _normalizeBase64(String input) {
    var s = input.replaceAll(RegExp(r'\s'), '');
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad != 0) {
      s = s.padRight(s.length + (4 - pad), '=');
    }
    return s;
  }
}

/// Result of [parseQrPayloadInIsolate] for use with [compute].
class ParserComputeResult {
  ParserComputeResult.success(this.data) : errorMessage = null;

  ParserComputeResult.failure(this.errorMessage) : data = null;

  final ParsedQRData? data;
  final String? errorMessage;
}

/// Top-level for [compute] — field parsing + Base64 normalization off UI isolate; image bytes decoded on result screen.
ParserComputeResult parseQrPayloadInIsolate(String raw) {
  try {
    return ParserComputeResult.success(
      ParserService.parse(raw, decodeImage: false),
    );
  } on FormatException catch (e) {
    return ParserComputeResult.failure(
      e.message.isEmpty ? 'Invalid QR format' : e.message,
    );
  }
}

/// Top-level for [compute] — WebP Base64 decode only.
Uint8List? decodeQrImageInIsolate(String normalizedBase64) {
  try {
    if (normalizedBase64.isEmpty) return null;
    return base64Decode(normalizedBase64);
  } on FormatException {
    return null;
  }
}
