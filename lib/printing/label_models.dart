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

  /// Kitchen order id.
  final int orderId;

  /// 1-based label index within this order, and the order's total label count.
  final int seq;
  final int seqTotal;

  /// When the order was placed (printed as Date & Time).
  final DateTime placedAt;

  /// QR payload (FDBK, coded by suite).
  final String qrData;

  const LabelData({
    required this.suiteName,
    required this.productName,
    required this.variants,
    required this.orderId,
    required this.seq,
    required this.seqTotal,
    required this.placedAt,
    required this.qrData,
    this.notes,
  });

  /// A sensible, human-traceable transaction id: order id + this label's
  /// sequence (unique per printed sticker), e.g. "AO-1042-2".
  String get txnId => 'AO-$orderId-$seq';

  /// One label per unit: a 2× Latte line yields two labels (one sticker per
  /// cup); a 3-product order yields 3+ labels.
  static List<LabelData> forTicket(KitchenTicket ticket) {
    final suite = ticket.suiteName ?? 'Suite ${ticket.suiteId}';
    final qr = FdbkConfig.qrDataForSuite(
      suiteId: ticket.suiteId,
      suiteName: ticket.suiteName,
    );
    final total = ticket.lines
        .fold<int>(0, (s, l) => s + (l.qty < 1 ? 1 : l.qty));
    final out = <LabelData>[];
    var seq = 0;
    for (final line in ticket.lines) {
      final units = line.qty < 1 ? 1 : line.qty;
      for (var i = 0; i < units; i++) {
        seq++;
        out.add(LabelData(
          suiteName: suite,
          productName: line.name,
          variants: line.modifiers,
          notes: line.notes,
          orderId: ticket.kitchenOrderId,
          seq: seq,
          seqTotal: total,
          placedAt: ticket.receivedAt,
          qrData: qr,
        ));
      }
    }
    return out;
  }
}
