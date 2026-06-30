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
  final DateTime? servedAt;
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
    this.servedAt,
    this.prepSeconds,
    required this.secondsSinceReceived,
    this.secondsInPrep,
    required this.lines,
  });

  bool get isNew => status == 'NEW';
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isReady => status == 'READY';
  bool get isOnHold => status == 'ON_HOLD';
  bool get isPickedUp => status == 'PICKED_UP';
  bool get isServed => status == 'SERVED';

  /// Completed from the kitchen's view: handed to a runner (PICKED_UP) or
  /// delivered (SERVED).
  bool get isCompleted => isPickedUp || isServed;

  /// Open rail = not yet finished or parked.
  bool get isOpen => isNew || isInProgress;

  /// How many forward stages are complete: NEW=0, IN_PROGRESS=1, READY=2,
  /// PICKED_UP=3, SERVED=4. Drives the Start/Made/Picked-Up progress control
  /// and the Back step.
  int get doneCount {
    switch (status) {
      case 'IN_PROGRESS':
        return 1;
      case 'READY':
        return 2;
      case 'PICKED_UP':
        return 3;
      case 'SERVED':
        return 4;
      default:
        return 0;
    }
  }

  /// Local copy with overrides — used for optimistic UI updates so a tapped
  /// action reflects instantly before the background write confirms. The
  /// `clear*` flags null a timestamp out (a copyWith can't otherwise tell
  /// "leave as-is" from "set to null").
  KitchenTicket copyWith({
    String? status,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? readyAt,
    bool clearReadyAt = false,
    DateTime? servedAt,
    bool clearServedAt = false,
  }) {
    return KitchenTicket(
      kitchenOrderId: kitchenOrderId,
      suiteId: suiteId,
      suiteName: suiteName,
      itemCount: itemCount,
      status: status ?? this.status,
      receivedAt: receivedAt,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      readyAt: clearReadyAt ? null : (readyAt ?? this.readyAt),
      servedAt: clearServedAt ? null : (servedAt ?? this.servedAt),
      prepSeconds: prepSeconds,
      secondsSinceReceived: secondsSinceReceived,
      secondsInPrep: secondsInPrep,
      lines: lines,
    );
  }

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
      servedAt: safeDate(pick('served_at')),
      prepSeconds: safeInt(pick('prep_seconds')),
      secondsSinceReceived: safeInt(pick('seconds_since_received')) ?? 0,
      secondsInPrep: safeInt(pick('seconds_in_prep')),
      lines: lines,
    );
  }
}
