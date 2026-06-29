import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:another_brother/printer_info.dart';
import 'package:another_brother/label_info.dart' show QL700;

/// Outcome of a print attempt.
class BrotherPrintResult {
  final bool ok;
  final String message;
  const BrotherPrintResult(this.ok, this.message);
}

/// Thin wrapper over the Brother SDK (another_brother) for the QL-810W over
/// WiFi. Everything is guarded so a missing/unreachable printer never crashes
/// the KDS — it returns a failure the caller can surface.
///
/// Media defaults to 62 mm continuous (DK-22205). If you load a different
/// tape, change [_labelId].
class BrotherService {
  // QL700.W62 = 62 mm continuous. Swap for another QL700.* if the tape differs.
  static int get _labelId => QL700.ordinalFromID(QL700.W62.getId());

  static PrinterInfo _info(String ipAddress) {
    final info = PrinterInfo();
    info.printerModel = Model.QL_810W;
    info.printMode = PrintMode.FIT_TO_PAGE;
    info.isAutoCut = true;
    info.port = Port.NET;
    info.ipAddress = ipAddress;
    info.labelNameIndex = _labelId;
    return info;
  }

  /// Print one rasterised label image to the printer at [ipAddress].
  static Future<BrotherPrintResult> printImage(
    ui.Image image, {
    required String ipAddress,
  }) async {
    try {
      final printer = Printer();
      Printer.setUserPrinterInfo(_info(ipAddress));
      final status = await printer.printImage(image);
      final ok = status.errorCode == ErrorCode.ERROR_NONE;
      return BrotherPrintResult(
        ok,
        ok ? 'Printed' : 'Printer error: ${status.errorCode.getName()}',
      );
    } catch (e) {
      developer.log('Brother print failed: $e');
      return BrotherPrintResult(false, 'Print failed: $e');
    }
  }

  /// Discover QL-810W printers on the local network (for the setup screen's
  /// "Find printer" helper). Returns their IP addresses.
  static Future<List<String>> discover() async {
    try {
      final printer = Printer();
      Printer.setUserPrinterInfo(_info(''));
      final found = await printer.getNetPrinters([Model.QL_810W.getName()]);
      return found
          .map((p) => p.ipAddress)
          .where((ip) => ip.trim().isNotEmpty)
          .toList();
    } catch (e) {
      developer.log('Brother discover failed: $e');
      return const [];
    }
  }
}
