import '../utils/date_utils.dart' as date_utils;

/// One line on a ticket — a configured drink with its chosen modifiers.
class KitchenTicketLine {
  final String name;
  final int qty;
  // Resolved modifier option names, e.g. ["Oat", "1 Sugar", "Extra Shot"].
  final List<String> modifiers;
  final String? notes;

  const KitchenTicketLine({
    required this.name,
    required this.qty,
    required this.modifiers,
    this.notes,
  });

  factory KitchenTicketLine.fromMap(Map<String, dynamic> map) {
    final mods = (map['modifiers'] as List<dynamic>? ?? const [])
        .map((m) => (m is Map)
            ? (m['option_name'] ?? m['OPTION_NAME'])?.toString() ?? ''
            : m.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final notes = map['notes']?.toString();
    return KitchenTicketLine(
      name: map['name']?.toString() ?? '',
      qty: int.tryParse(map['qty']?.toString() ?? '1') ?? 1,
      modifiers: mods,
      notes: (notes == null || notes.isEmpty || notes == 'null') ? null : notes,
    );
  }
}

/// A kitchen order ticket on the KDS rail. Maps a KITCHEN_ORDER row plus the
/// server-computed age fields used to colour the card and drive the timer.
class KitchenTicket {
  final int kitchenOrderId;
  final int suiteId;
  final String? suiteName;
  final int itemCount;
  final String status; // NEW | IN_PROGRESS | READY | SERVED | ON_HOLD | CANCELLED
  final DateTime receivedAt;
  final DateTime? startedAt;
  final DateTime? readyAt;
  final int? prepSeconds;
  // Server-computed so colour/timer don't depend on the tablet clock.
  final int secondsSinceReceived;
  final int? secondsInPrep;
  final List<KitchenTicketLine> lines;

  const KitchenTicket({
    required this.kitchenOrderId,
    required this.suiteId,
    this.suiteName,
    required this.itemCount,
    required this.status,
    required this.receivedAt,
    this.startedAt,
    this.readyAt,
    this.prepSeconds,
    required this.secondsSinceReceived,
    this.secondsInPrep,
    required this.lines,
  });

  bool get isNew => status == 'NEW';
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isReady => status == 'READY';
  bool get isOnHold => status == 'ON_HOLD';
  bool get isServed => status == 'SERVED';

  /// Open rail = not yet finished or parked.
  bool get isOpen => isNew || isInProgress;

  factory KitchenTicket.fromMap(Map<String, dynamic> map) {
    dynamic pick(String k) => map[k.toUpperCase()] ?? map[k.toLowerCase()];

    int? safeInt(dynamic v) {
      if (v == null || v.toString() == 'null') return null;
      return int.tryParse(v.toString().split('.').first);
    }

    DateTime? safeDate(dynamic v) =>
        date_utils.DateUtils.parseSnowflakeTimestamp(v);

    final rawLines = pick('items');
    final lines = (rawLines is List)
        ? rawLines
            .map((e) => KitchenTicketLine.fromMap(
                Map<String, dynamic>.from(e as Map)))
            .toList()
        : <KitchenTicketLine>[];

    return KitchenTicket(
      kitchenOrderId: safeInt(pick('kitchen_order_id')) ?? 0,
      suiteId: safeInt(pick('suite_id')) ?? 0,
      suiteName: pick('suite_name')?.toString(),
      itemCount: safeInt(pick('item_count')) ?? 0,
      status: pick('status')?.toString() ?? 'NEW',
      receivedAt: safeDate(pick('received_at')) ?? DateTime.now(),
      startedAt: safeDate(pick('started_at')),
      readyAt: safeDate(pick('ready_at')),
      prepSeconds: safeInt(pick('prep_seconds')),
      secondsSinceReceived: safeInt(pick('seconds_since_received')) ?? 0,
      secondsInPrep: safeInt(pick('seconds_in_prep')),
      lines: lines,
    );
  }
}
