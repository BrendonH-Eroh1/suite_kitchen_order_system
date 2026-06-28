import 'dart:developer' as developer;
import '../models/kitchen_ticket.dart';

/// Printing seam — deliberately a no-op in v1 (screen-only KDS).
///
/// v2 will implement [printTicket] against a network ESC/POS thermal printer
/// (Epson TM-series over TCP 9100 is the expected hardware) and the proxy
/// will stamp KITCHEN_ORDER.printed_at. Keeping the call site here means the
/// rail already invokes printing where it should — only this body changes.
class TicketPrinter {
  /// Whether a printer is configured. Always false in v1.
  static bool get isConfigured => false;

  /// Print (or, in v1, log) a ticket as it enters the rail.
  static Future<void> printTicket(KitchenTicket ticket) async {
    if (!isConfigured) {
      developer.log(
        'TicketPrinter: no printer configured — skipping print of '
        'order #${ticket.kitchenOrderId} (v1 is screen-only)',
      );
      return;
    }
    // v2: build ESC/POS bytes and send over TCP:9100.
  }
}
