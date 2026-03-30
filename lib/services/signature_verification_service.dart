import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

/// Verifies Fayda QR detached JWT signatures (RS256) against the bundled issuer public key.
class SignatureVerificationService {
  const SignatureVerificationService();

  static const String _issuerRsaPublicKeyPem =
      '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxMWfApFZBq/qIotUjrkY
bdyXQcHOUgZsqZy3QUcXr50t+DfwYKkSfMnTZFHekptAWA4HM5upav6xqFuP+3Pi
KmajY2Imkl60bF4Bt9qcch74jPSObH/1CE0xs75dqLb+CfoTG1+i4n3Fz5cN9Mxp
EGE7pmvIdYtaAUCoKA/cjQ5QY426ttp4EQcnh5vmyr1e7ur9LjqVVsurfefxlsR+
sRfB2RFuaEGrLO/75UeUSY2x1nTHzOvycWYaCve1YfunHkXA8JvUy73+b33ixIgw
QuqUkOuyKhytFr5l6N1gfjTvOOysclCH5o8jy7KyzgyK17kHXPAaKuxYXH9pGtAF
0wIDAQAB
-----END PUBLIC KEY-----''';

  /// Compact JWT after `:SIGN:` with [detachedPayload] = raw text before `:SIGN:`.
  static Future<VerificationResult> verifyCredentialSignature(
    String jwtCompact, {
    String? detachedPayload,
  }) async {
    final value = jwtCompact.trim();
    if (value.isEmpty) {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        message: 'No signature to check',
      );
    }
    final segments = value.split('.');
    if (segments.length != 3 || segments[0].isEmpty) {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        message: 'Unrecognized signature format',
      );
    }
    return verifyCredentialJwt(value, detachedPayload: detachedPayload);
  }

  static Future<VerificationResult> verifyCredentialJwt(
    String jwt, {
    String? detachedPayload,
  }) async {
    final parts = _decodeJwtUnverified(jwt);
    if (parts == null) {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        message: 'Unrecognized signature format',
      );
    }
    final alg = (parts.header['alg'] ?? '').toString().toUpperCase();
    if (alg != 'RS256') {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        message: 'Unsupported signature type',
      );
    }

    final keys = _loadPemRsaPublicKeys();
    if (keys.isEmpty) {
      return const VerificationResult(
        status: VerificationStatus.unavailable,
        message: 'No verification keys configured',
      );
    }

    final kid = (parts.header['kid'] ?? '').toString();

    for (final pubKey in keys) {
      if (_verifyJwtRs256(jwt, pubKey, detachedPayload: detachedPayload)) {
        return VerificationResult(
          status: VerificationStatus.valid,
          message: 'Verified',
          keyId: kid.isNotEmpty ? kid : null,
        );
      }
    }

    return const VerificationResult(
      status: VerificationStatus.invalid,
      message: 'Not verified',
    );
  }

  static _JwtParts? _decodeJwtUnverified(String jwt) {
    final segments = jwt.split('.');
    if (segments.length != 3) return null;
    try {
      final headerJson = _decodeJsonSegment(segments[0]);
      final payloadJson = segments[1].isEmpty
          ? <String, dynamic>{}
          : _decodeJsonSegment(segments[1]);
      return _JwtParts(
        header: headerJson,
        payload: payloadJson,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decodeJsonSegment(String segment) {
    var s = segment.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad != 0) {
      s = s.padRight(s.length + (4 - pad), '=');
    }
    final bytes = base64Decode(s);
    final str = utf8.decode(bytes);
    final decoded = jsonDecode(str);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{'value': decoded};
  }

  static bool _verifyJwtRs256(
    String jwt,
    RSAPublicKey pubKey, {
    String? detachedPayload,
  }) {
    final segments = jwt.split('.');
    if (segments.length != 3) return false;

    final payloadSegment = segments[1].isEmpty && detachedPayload != null
        ? base64Url.encode(utf8.encode(detachedPayload)).replaceAll('=', '')
        : segments[1];
    final signingInput = utf8.encode('${segments[0]}.$payloadSegment');
    final signatureBytes = _decodeBase64Url(segments[2]);
    if (signatureBytes == null || signatureBytes.isEmpty) return false;

    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(pubKey));
    return verifier.verifySignature(
      Uint8List.fromList(signingInput),
      RSASignature(signatureBytes),
    );
  }

  static Uint8List? _decodeBase64Url(String input) {
    try {
      var s = input.replaceAll('-', '+').replaceAll('_', '/');
      final pad = s.length % 4;
      if (pad != 0) s = s.padRight(s.length + (4 - pad), '=');
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  static List<RSAPublicKey> _loadPemRsaPublicKeys() {
    try {
      return <RSAPublicKey>[CryptoUtils.rsaPublicKeyFromPem(_issuerRsaPublicKeyPem)];
    } catch (_) {
      return <RSAPublicKey>[];
    }
  }
}

enum VerificationStatus { valid, invalid, unavailable }

class VerificationResult {
  const VerificationResult({
    required this.status,
    required this.message,
    this.keyId,
  });

  final VerificationStatus status;
  final String message;
  final String? keyId;
}

class _JwtParts {
  const _JwtParts({required this.header, required this.payload});

  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;
}
