import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/kitchen_ticket.dart';
import '../services/device_credentials.dart';
import 'label_card.dart';
import 'label_models.dart';
import 'star_service.dart';

/// Shows the labels for an order — one per drink/cup — exactly as they'll
/// print, and prints them to the configured Star TSP654IISK. Works as a pure
/// preview even with no printer set (the Print button is just disabled), so
/// the label layout can be validated before any hardware is connected.
class LabelPreviewScreen extends StatefulWidget {
  final KitchenTicket ticket;
  const LabelPreviewScreen({super.key, required this.ticket});

  @override
  State<LabelPreviewScreen> createState() => _LabelPreviewScreenState();
}

class _LabelPreviewScreenState extends State<LabelPreviewScreen> {
  late final List<LabelData> _labels = LabelData.forTicket(widget.ticket);
  late final List<GlobalKey> _keys =
      List.generate(_labels.length, (_) => GlobalKey());
  bool _printing = false;
  bool _precached = false;

  // Force-decode the label artwork into the image cache before any capture, so
  // RepaintBoundary.toImage() never grabs a half-loaded (blank) logo/face.
  static const _assets = [
    'assets/images/adelaide_oval_logo.png',
    'assets/images/face_1.png',
    'assets/images/face_2.png',
    'assets/images/face_3.png',
    'assets/images/face_4.png',
    'assets/images/face_5.png',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final a in _assets) {
      precacheImage(AssetImage(a), context);
    }
  }

  /// Capture a label's RepaintBoundary as PNG bytes at the print resolution.
  Future<Uint8List?> _capturePng(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: kLabelCapturePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _printAll() async {
    if (!DeviceCredentials.canPrint || _printing) return;
    final ip = DeviceCredentials.printerIp!;
    setState(() => _printing = true);
    var ok = 0;
    var fail = 0;
    String? lastError;
    for (final key in _keys) {
      final png = await _capturePng(key);
      if (png == null) {
        fail++;
        continue;
      }
      final result = await StarService.printPng(png, ipAddress: ip);
      if (result.ok) {
        ok++;
      } else {
        fail++;
        lastError = result.message;
      }
      // Small gap so the printer queues each label cleanly.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(fail == 0
            ? 'Printed $ok label${ok == 1 ? '' : 's'}'
            : 'Printed $ok, $fail failed${lastError != null ? ' — $lastError' : ''}'),
        backgroundColor: fail == 0 ? Colors.green : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrint = DeviceCredentials.canPrint;
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      appBar: AppBar(
        title: Text('Print Labels (${_labels.length})'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (!canPrint)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Preview only — set the printer IP and turn printing on in '
                'Setup (⋮ → Change station / operator) to print.',
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            // Non-lazy: every label boundary is realised + painted so it can
            // be captured even when scrolled off-screen.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (var i = 0; i < _labels.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    Text('Label ${i + 1} of ${_labels.length}',
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    // RepaintBoundary at native label size = what we rasterise.
                    Material(
                      elevation: 2,
                      child: RepaintBoundary(
                        key: _keys[i],
                        child: LabelCard(data: _labels[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canPrint && !_printing ? _printAll : null,
                  icon: _printing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print),
                  label: Text(
                    _printing
                        ? 'Printing…'
                        : 'Print ${_labels.length} label${_labels.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C7BE5),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
