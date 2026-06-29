import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

/// Outcome of a print attempt.
class StarPrintResult {
  final bool ok;
  final String message;
  const StarPrintResult(this.ok, this.message);
}

/// Network printing for the Star TSP654IISK (80 mm) over raw TCP 9100.
///
/// We build an ESC/POS raster job (pure Dart — no native plugin, so it stays
/// compatible with current Flutter) and stream it to the printer. The
/// TSP654II must be in **ESC/POS emulation** mode (set once via Star's setup
/// utility / the printer's config) — Star Line Mode is the factory default and
/// will not render these bytes.
///
/// Everything is guarded so an unreachable printer never crashes the KDS.
class StarService {
  static const int port = 9100;
  static const int printWidthDots = 576; // 80 mm @ 203 dpi

  /// Print one rasterised label (PNG bytes) to the printer at [ipAddress].
  static Future<StarPrintResult> printPng(
    Uint8List png, {
    required String ipAddress,
  }) async {
    Socket? socket;
    try {
      final decoded = img.decodePng(png) ?? img.decodeImage(png);
      if (decoded == null) {
        return const StarPrintResult(false, 'Could not decode label image');
      }
      // Keep within the 80 mm head width.
      final image = decoded.width > printWidthDots
          ? img.copyResize(decoded, width: printWidthDots)
          : decoded;

      final profile = await CapabilityProfile.load();
      final gen = Generator(PaperSize.mm80, profile);
      final bytes = <int>[
        ...gen.reset(),
        ...gen.imageRaster(image, align: PosAlign.center),
        ...gen.feed(2),
        ...gen.cut(mode: PosCutMode.partial),
      ];

      socket = await Socket.connect(
        ipAddress.trim(),
        port,
        timeout: const Duration(seconds: 6),
      );
      socket.add(bytes);
      await socket.flush();
      // Give the printer a moment to consume the job before we close.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return const StarPrintResult(true, 'Printed');
    } on SocketException catch (e) {
      developer.log('Star socket error: $e');
      return StarPrintResult(false, 'Cannot reach printer: ${e.message}');
    } catch (e) {
      developer.log('Star print failed: $e');
      return StarPrintResult(false, 'Print failed: $e');
    } finally {
      socket?.destroy();
    }
  }
}
