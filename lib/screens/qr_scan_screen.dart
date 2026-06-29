import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Result of a successful provisioning scan.
class ScannedCredentials {
  final String deviceId;
  final String pat;
  const ScannedCredentials({required this.deviceId, required this.pat});
}

/// Full-screen QR scanner for KDS provisioning. Reads the same payload the
/// SiS admin app issues for the suite app:
///   {"device_id": "...", "pat": "eyJ..."}
/// (`batch_id` accepted as an alias for `device_id`; any extra fields such
/// as `device_type` are ignored — the KDS doesn't use them.) Pops with a
/// [ScannedCredentials] on success, or null on back/cancel.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _camera;
  bool _processed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processed) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _processed = true;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('expected a JSON object');
        }
        final deviceId =
            (decoded['device_id'] ?? decoded['batch_id'])?.toString() ?? '';
        final pat = decoded['pat']?.toString() ?? '';
        if (deviceId.isEmpty || pat.isEmpty) {
          throw const FormatException('missing device_id/batch_id or pat');
        }
        Navigator.of(context).pop(
          ScannedCredentials(deviceId: deviceId, pat: pat),
        );
        return;
      } catch (e) {
        developer.log('KDS QR decode failed: $e');
        if (!mounted) return;
        setState(() {
          _error = 'Invalid QR — expected a provisioning code';
          _processed = false;
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final box = (size.shortestSide * 0.55).clamp(180.0, 360.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Provisioning QR'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _camera, onDetect: _onDetect),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          Center(
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Scan the QR from the admin app to provision this '
                    'kitchen tablet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
