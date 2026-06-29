import '../models/kitchen_ticket.dart';
import 'fdbk_config.dart';

/// The content of one printed adhesive label (one per drink/cup).
class LabelData {
  /// Heading — e.g. "Corporate Suite 05".
  final String suiteName;

  /// The drink, e.g. "Latte".
  final String productName;

  /// Chosen variants in order — e.g. ["Large", "Oat", "1 Sugar", "Extra Shot"].
  final List<String> variants;

  /// Free-text note on the line, if any.
  final String? notes;

  /// Kitchen order id, printed small for traceability.
  final int orderId;

  /// QR payload (FDBK, coded by suite).
  final String qrData;

  const LabelData({
    required this.suiteName,
    required this.productName,
    required this.variants,
    required this.orderId,
    required this.qrData,
    this.notes,
  });

  /// One label per unit: a 2× Latte line yields two labels (one sticker per
  /// cup); a 3-product order yields 3+ labels.
  static List<LabelData> forTicket(KitchenTicket ticket) {
    final suite = ticket.suiteName ?? 'Suite ${ticket.suiteId}';
    final qr = FdbkConfig.qrDataForSuite(
      suiteId: ticket.suiteId,
      suiteName: ticket.suiteName,
    );
    final out = <LabelData>[];
    for (final line in ticket.lines) {
      final units = line.qty < 1 ? 1 : line.qty;
      for (var i = 0; i < units; i++) {
        out.add(LabelData(
          suiteName: suite,
          productName: line.name,
          variants: line.modifiers,
          notes: line.notes,
          orderId: ticket.kitchenOrderId,
          qrData: qr,
        ));
      }
    }
    return out;
  }
}
