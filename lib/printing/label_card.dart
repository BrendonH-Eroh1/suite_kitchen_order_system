import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'label_models.dart';

/// Logical width the label is laid out at. The capture step scales this up to
/// the printer's dot width (see [kPrintWidthDots]) for a crisp raster.
const double kLabelLogicalWidth = 384;

/// Printable dot width of the target media. Star TSP654IISK @ 203 dpi:
///   80 mm linerless sticky paper = 576 printable dots.
/// Change this if you move to a different printer/paper width.
const int kPrintWidthDots = 576;

/// pixelRatio for RepaintBoundary.toImage() to reach [kPrintWidthDots].
const double kLabelCapturePixelRatio = kPrintWidthDots / kLabelLogicalWidth;

/// QR size on the label (centred); the 5 feedback faces sit vertically beside.
const double _kQrSize = 168;
const double _kFaceSize = 28;

/// One adhesive label, rendered black-on-white for a thermal printer:
///   [Adelaide Oval logo]
///   Suite name (large)
///   ──────────────
///   Order detail (drink + variants + notes)
///   ──────────────
///   Date & time   ·   transaction id
///   ──────────────
///   QR code
///   [5 B&W faces]  FDBK
class LabelCard extends StatelessWidget {
  final LabelData data;
  const LabelCard({super.key, required this.data});

  static const List<String> _faceAssets = [
    'assets/images/face_1.png', // happiest
    'assets/images/face_2.png',
    'assets/images/face_3.png',
    'assets/images/face_4.png',
    'assets/images/face_5.png', // angriest
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kLabelLogicalWidth,
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Adelaide Oval logo, forced solid black so it prints crisp (not a
          // dithered grey) — the whole label is black-on-white.
          Center(
            child: ColorFiltered(
              colorFilter:
                  const ColorFilter.mode(Colors.black, BlendMode.srcIn),
              child: Image.asset(
                'assets/images/adelaide_oval_logo.png',
                height: 46,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Suite name — large.
          Text(
            data.suiteName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          _rule(),
          // Order detail.
          Text(
            data.productName,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          if (data.variants.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              data.variants.join('  ·  '),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
          if (data.notes != null && data.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              '“${data.notes!.trim()}”',
              style: const TextStyle(
                  color: Colors.black, fontSize: 14, fontStyle: FontStyle.italic),
            ),
          ],
          _rule(),
          // Date & time + transaction id.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dateTime(data.placedAt),
                  style: const TextStyle(color: Colors.black, fontSize: 13)),
              Text(data.txnId,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          _rule(),
          // Feedback: prompt above, big centred QR, faces stacked beside it.
          const Center(
            child: Text(
              'Provide your Feedback',
              style: TextStyle(
                color: Colors.black,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left spacer balances the faces column so the QR sits centred.
              const SizedBox(width: _kFaceSize + 12),
              QrImageView(
                data: data.qrData,
                version: QrVersions.auto,
                size: _kQrSize,
                gapless: true,
                backgroundColor: Colors.white,
                // ignore: deprecated_member_use — wide plugin compatibility
                foregroundColor: Colors.black,
              ),
              const SizedBox(width: 12),
              // 5 faces vertical (happy → angry).
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in _faceAssets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _bwFace(f),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A full-width black rule with breathing room.
  Widget _rule() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(height: 2, color: Colors.black),
      );

  /// A feedback face forced to solid black (the source art is coloured
  /// line-art on transparency, so srcIn gives a clean monochrome icon).
  Widget _bwFace(String asset) => ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
        child: Image.asset(asset, height: _kFaceSize, fit: BoxFit.contain),
      );

  static String _dateTime(DateTime dt) {
    final t = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year}  ${two(t.hour)}:${two(t.minute)}';
  }
}
