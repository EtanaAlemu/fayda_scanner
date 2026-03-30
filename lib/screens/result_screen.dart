import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fayda_scanner/models/parsed_qr_data.dart';
import 'package:fayda_scanner/services/parser_service.dart';
import 'package:fayda_scanner/services/signature_verification_service.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.data});

  final ParsedQRData data;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _imageDecodeBusy = false;
  bool _signatureVerifyBusy = false;
  VerificationResult? _signatureResult;

  late ParsedQRData _data;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    if (_data.hasPendingImage) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _decodePendingImage(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifySignature());
  }

  Future<void> _decodePendingImage() async {
    final pending = _data.pendingImageBase64;
    if (pending == null || pending.isEmpty || !mounted) return;
    setState(() => _imageDecodeBusy = true);
    final bytes = await compute(decodeQrImageInIsolate, pending);
    if (!mounted) return;
    setState(() {
      _imageDecodeBusy = false;
      _data = _data.applyDecodedImage(
        bytes ?? Uint8List(0),
        success: bytes != null && bytes.isNotEmpty,
      );
    });
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _verifySignature() async {
    final sig = _data.signature.trim();
    if (sig.isEmpty || !mounted) return;
    setState(() => _signatureVerifyBusy = true);
    final result = await SignatureVerificationService.verifyCredentialSignature(
      sig,
      detachedPayload: _data.rawSignedPayload,
    );
    if (!mounted) return;
    setState(() {
      _signatureVerifyBusy = false;
      _signatureResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan result'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (_data.hasDisplayableImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _data.imageBytes,
                          height: 200,
                          width: 200,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: 300,
                          errorBuilder: (context, error, stackTrace) =>
                              _ImageFallback(theme: theme),
                        ),
                      )
                    else if (_data.hasPendingImage && _imageDecodeBusy)
                      const SizedBox(
                        height: 200,
                        width: 200,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _ImageFallback(theme: theme),
                    const SizedBox(height: 16),
                    Text(
                      _data.fullName.isEmpty ? '—' : _data.fullName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Gender',
              value: _data.gender.isEmpty ? '—' : _data.gender,
            ),
            _InfoRow(
              label: 'Date of birth',
              value: _data.dob.isEmpty ? '—' : _data.dob,
            ),
            _InfoRow(
              label: 'ID number',
              value: _data.idNumber.isEmpty ? '—' : _data.idNumber,
              trailing: _data.idNumber.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () => _copy('ID number', _data.idNumber),
                    ),
            ),
            _InfoRow(
              label: 'Version',
              value: _data.version.isEmpty ? '—' : _data.version,
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Signature', style: theme.textTheme.labelLarge),
                subtitle: _signatureVerifyBusy
                    ? const Text('Checking…')
                    : Text(
                        switch (_signatureResult?.status) {
                          VerificationStatus.valid => 'Verified',
                          VerificationStatus.invalid => 'Not verified',
                          _ => 'Could not verify',
                        },
                        style: theme.textTheme.bodyLarge,
                      ),
                trailing: _signatureVerifyBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        switch (_signatureResult?.status) {
                          VerificationStatus.valid => Icons.verified,
                          VerificationStatus.invalid => Icons.error_outline,
                          _ => Icons.help_outline,
                        },
                        color: switch (_signatureResult?.status) {
                          VerificationStatus.valid => Colors.green,
                          VerificationStatus.invalid => Colors.red,
                          _ => theme.colorScheme.outline,
                        },
                      ),
              ),
            ),
            if ((_signatureResult?.keyId ?? '').isNotEmpty &&
                _signatureResult!.status == VerificationStatus.valid)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Key ID: ${_signatureResult!.keyId}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            if (_signatureResult?.status == VerificationStatus.unavailable &&
                (_signatureResult?.message ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _signatureResult!.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Scan another'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text('Image unavailable', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label, style: theme.textTheme.labelLarge),
        subtitle: Text(value, style: theme.textTheme.bodyLarge),
        trailing: trailing,
      ),
    );
  }
}
