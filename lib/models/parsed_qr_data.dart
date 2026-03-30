import 'dart:convert';
import 'dart:typed_data';

/// Structured data extracted from the custom QR delimiter format.
class ParsedQRData {
  ParsedQRData({
    required this.imageBytes,
    required this.imageDecodedSuccessfully,
    required this.fullName,
    required this.version,
    required this.gender,
    required this.idNumber,
    required this.dob,
    required this.signature,
    required this.rawPayloadTail,
    required this.rawSignedPayload,
    this.pendingImageBase64,
  });

  /// Raw WebP bytes when [imageDecodedSuccessfully] is true; otherwise empty.
  final Uint8List imageBytes;
  final bool imageDecodedSuccessfully;

  final String fullName;
  final String version;
  final String gender;
  final String idNumber;
  final String dob;
  final String signature;

  /// Part after `:DLT:` before field parsing (useful for debugging).
  final String rawPayloadTail;

  /// Exact raw bytes (as UTF-8 text) that appear before `:SIGN:`.
  final String rawSignedPayload;

  /// Normalized Base64 for the image segment when using lazy decode; clear after [applyDecodedImage].
  final String? pendingImageBase64;

  bool get hasPendingImage =>
      pendingImageBase64 != null && pendingImageBase64!.isNotEmpty;

  bool get hasDisplayableImage =>
      imageDecodedSuccessfully && imageBytes.isNotEmpty;

  /// Canonical string RS256 verification would sign over (image + fields, no JWT).
  String get canonicalSigningPayload {
    final b64 = (pendingImageBase64 != null && pendingImageBase64!.isNotEmpty)
        ? pendingImageBase64!
        : base64Encode(imageBytes);
    return '$b64:DLT:$fullName:V:$version:G:$gender:A:$idNumber:D:$dob';
  }

  ParsedQRData applyDecodedImage(
    Uint8List decoded, {
    required bool success,
  }) {
    return ParsedQRData(
      imageBytes: decoded,
      imageDecodedSuccessfully: success && decoded.isNotEmpty,
      fullName: fullName,
      version: version,
      gender: gender,
      idNumber: idNumber,
      dob: dob,
      signature: signature,
      rawPayloadTail: rawPayloadTail,
      rawSignedPayload: rawSignedPayload,
      pendingImageBase64: null,
    );
  }

  Map<String, dynamic> toJson() => {
        'imageDecodedSuccessfully': imageDecodedSuccessfully,
        'imageByteLength': imageBytes.length,
        'pendingImageBase64Length': pendingImageBase64?.length,
        'fullName': fullName,
        'version': version,
        'gender': gender,
        'idNumber': idNumber,
        'dob': dob,
        'signature': signature,
        'rawPayloadTail': rawPayloadTail,
        'rawSignedPayload': rawSignedPayload,
      };
}
