import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fdbk_config.dart';
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

/// One adhesive label, rendered as a pure black-on-white widget suited to a
/// thermal label printer. The same widget is used for the on-screen preview
/// and for the rasterised image sent to the printer.
class LabelCard extends StatelessWidget {
  final LabelData data;
  const LabelCard({super.key, required this.data});

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
          // Heading — Suite name on a solid bar for prominence.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Colors.black,
            child: Text(
              data.suiteName.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Product
          Text(
            data.productName,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          if (data.variants.isNotEmpty) ...[
            const SizedBox(height: 4),
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
            const SizedBox(height: 4),
            Text(
              '“${data.notes!.trim()}”',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(height: 2, color: Colors.black),
          const SizedBox(height: 10),
          // Feedback + QR
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FdbkConfig.servicePrompt,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Scan to tell us',
                      style: TextStyle(color: Colors.black, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // QR area — driven by FDBK payload (placeholder for now).
              QrImageView(
                data: data.qrData,
                version: QrVersions.auto,
                size: 104,
                gapless: true,
                backgroundColor: Colors.white,
                // ignore: deprecated_member_use — keep wide plugin compatibility
                foregroundColor: Colors.black,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Order #${data.orderId}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
