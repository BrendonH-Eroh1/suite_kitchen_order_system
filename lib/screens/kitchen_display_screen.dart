import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../config/app_info.dart';
import '../models/kitchen_ticket.dart';
import '../printing/label_preview_screen.dart';
import '../services/device_credentials.dart';
import '../services/kitchen_station_service.dart';
import '../services/ticket_printer.dart';
import 'station_setup_screen.dart';

const _kBlue = Color(0xFF2C7BE5); // Start
const _kAmber = Color(0xFFDD9B36); // Made (being prepared)
const _kGreen = Color(0xFF38A169); // Serve (ready to hand off)
const _kServeGreen = Color(0xFF2F855A);

/// The Kitchen Display System rail. A card grid of order tickets with
/// Open / Done / On Hold tabs, age-coloured headers and live timers, a
/// Start → Done → Serve progress control (with a Back step), and a tap-to-open
/// detail modal. Writes are optimistic — the UI advances instantly and the
/// proxy call runs in the background.
class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

enum _Tab { open, completed, hold }

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen> {
  // Active rail (Open): NEW + IN_PROGRESS + READY — one ticket cycles
  // Start → Made → Serve here on the main board. ON_HOLD lives here too.
  List<KitchenTicket> _active = [];
  // Completed (delivered) orders for the Completed tab — fetched separately
  // since SERVED is terminal and not part of the active feed.
  List<KitchenTicket> _served = [];
  _Tab _tab = _Tab.open;
  bool _loading = true;
  bool _syncing = false; // a background write is in flight
  String? _error;
  Timer? _poll;
  Timer? _tick; // 1s repaint so on-card timers advance between polls
  final Set<int> _printed = {};

  // Age thresholds (seconds) for header colour: green → amber → red.
  static const int _amberAfter = 180; // 3 min
  static const int _redAfter = 360; // 6 min

  int get _stationId => DeviceCredentials.stationId ?? 0;
  int get _operatorId => DeviceCredentials.operatorStaffId ?? 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      // Active board + completed list in parallel. "Completed" = handed to a
      // runner (PICKED_UP) or delivered (SERVED).
      final results = await Future.wait([
        KitchenStationService.getTickets(_stationId),
        KitchenStationService.getTickets(_stationId, status: 'PICKED_UP,SERVED'),
      ]);
      final active = results[0];
      // Newest first for the completed screen.
      final served = results[1].reversed.toList();
      if (!mounted) return;
      for (final t in active) {
        if (_printed.add(t.kitchenOrderId)) {
          TicketPrinter.printTicket(t);
        }
      }
      setState(() {
        _active = active;
        _served = served;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      developer.log('KDS refresh failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  // ---- Optimistic writes ----------------------------------------------------

  /// Apply a status change to the in-memory list instantly so the UI feels
  /// immediate; the server write follows in the background.
  void _optimistic(KitchenTicket t, String s) {
    final now = DateTime.now();
    final updated = t.copyWith(
      status: s,
      startedAt: s == 'IN_PROGRESS' && t.startedAt == null ? now : t.startedAt,
      clearStartedAt: s == 'NEW',
      readyAt: s == 'READY' ? now : t.readyAt,
      clearReadyAt: s == 'IN_PROGRESS' || s == 'NEW' || s == 'ON_HOLD',
      servedAt: s == 'SERVED' ? now : t.servedAt,
      clearServedAt: s != 'SERVED',
    );
    bool notThis(KitchenTicket x) => x.kitchenOrderId != t.kitchenOrderId;
    setState(() {
      if (s == 'CANCELLED') {
        _active = _active.where(notThis).toList();
        _served = _served.where(notThis).toList();
      } else if (s == 'PICKED_UP' || s == 'SERVED') {
        // Off the board into the Completed list (picked up / delivered).
        _active = _active.where(notThis).toList();
        _served = [updated, ..._served.where(notThis)];
      } else {
        // An active state (including reopening a served ticket).
        _served = _served.where(notThis).toList();
        if (_active.any((x) => x.kitchenOrderId == t.kitchenOrderId)) {
          _active = [
            for (final x in _active)
              x.kitchenOrderId == t.kitchenOrderId ? updated : x,
          ];
        } else {
          _active = [updated, ..._active];
        }
      }
    });
  }

  /// Optimistically move the ticket, then fire the write in the background.
  /// On success we quietly reconcile with server truth (timestamps,
  /// prep_seconds); on failure we revert by re-fetching and flag it.
  void _do(KitchenTicket t, String optimisticStatus,
      Future<void> Function() call) {
    _optimistic(t, optimisticStatus);
    setState(() => _syncing = true);
    call().then((_) {
      if (mounted) {
        setState(() => _syncing = false);
        _refresh();
      }
    }).catchError((Object e) {
      // Transient/timing hiccup — the optimistic state is reconciled by the
      // refresh below (and the 12s poll), so don't bother the operator with a
      // banner. Just log it and quietly resync.
      developer.log('KDS write failed, reconciling: $e');
      if (!mounted) return;
      setState(() => _syncing = false);
      _refresh();
    });
  }

  void _start(KitchenTicket t) => _do(t, 'IN_PROGRESS',
      () => KitchenStationService.start(t.kitchenOrderId, _operatorId));
  void _done(KitchenTicket t) => _do(t, 'READY',
      () => KitchenStationService.done(t.kitchenOrderId, _operatorId));
  // Kitchen hands the made drink to a runner (READY -> PICKED_UP). The order
  // then lives on the fulfillment delivery list; the runner marks it
  // delivered (serve). So the KDS "Serve" button means "picked up", not
  // "delivered".
  void _pickup(KitchenTicket t) => _do(t, 'PICKED_UP',
      () => KitchenStationService.pickup(t.kitchenOrderId, _operatorId));
  void _hold(KitchenTicket t) => _do(t, 'ON_HOLD',
      () => KitchenStationService.hold(t.kitchenOrderId, _operatorId));
  void _resume(KitchenTicket t) => _do(t, 'IN_PROGRESS',
      () => KitchenStationService.resume(t.kitchenOrderId, _operatorId));

  static String? _prevStatus(String s) {
    switch (s) {
      case 'SERVED':
        return 'READY';
      case 'READY':
        return 'IN_PROGRESS';
      case 'IN_PROGRESS':
        return 'NEW';
      case 'ON_HOLD':
        return 'IN_PROGRESS';
      default:
        return null;
    }
  }

  static String _prevStageName(String s) {
    switch (s) {
      case 'SERVED':
        return 'Ready';
      case 'READY':
        return 'In progress';
      case 'IN_PROGRESS':
        return 'New (not started)';
      case 'ON_HOLD':
        return 'In progress';
      default:
        return '';
    }
  }

  Future<void> _stepBack(KitchenTicket t) async {
    final prev = _prevStatus(t.status);
    if (prev == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Step order #${t.kitchenOrderId} back?'),
        content: Text('Move it back to “${_prevStageName(t.status)}”.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
            child: const Text('Step back'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _do(t, prev,
          () => KitchenStationService.back(t.kitchenOrderId, _operatorId));
    }
  }

  Future<void> _cancel(KitchenTicket t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancel order #${t.kitchenOrderId}?'),
        content: Text(t.suiteName ?? 'Suite ${t.suiteId}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _do(t, 'CANCELLED',
          () => KitchenStationService.cancel(t.kitchenOrderId, _operatorId));
    }
  }

  // ---- Detail modal ---------------------------------------------------------

  void _openTicket(KitchenTicket t) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _TicketModal(
        ticket: t,
        headerColor: _headerColor(t),
        onStart: () {
          Navigator.pop(ctx);
          _start(t);
        },
        onDone: () {
          Navigator.pop(ctx);
          _done(t);
        },
        onServe: () {
          Navigator.pop(ctx);
          _pickup(t);
        },
        onHold: () {
          Navigator.pop(ctx);
          _hold(t);
        },
        onResume: () {
          Navigator.pop(ctx);
          _resume(t);
        },
        onBack: () {
          Navigator.pop(ctx);
          _stepBack(t);
        },
        onCancel: () {
          Navigator.pop(ctx);
          _cancel(t);
        },
      ),
    );
  }

  // ---- Tabs / lists ---------------------------------------------------------

  // Open board carries the whole live lifecycle — NEW, IN_PROGRESS and READY
  // — so one ticket cycles Start → Made → Serve in place. Completed = served.
  List<KitchenTicket> get _openTickets =>
      _active.where((t) => t.isNew || t.isInProgress || t.isReady).toList();
  List<KitchenTicket> get _holdTickets =>
      _active.where((t) => t.isOnHold).toList();

  List<KitchenTicket> get _visible {
    switch (_tab) {
      case _Tab.open:
        return _openTickets;
      case _Tab.hold:
        return _holdTickets;
      case _Tab.completed:
        return _served;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      appBar: AppBar(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            _tabChip('${_openTickets.length} Open', _Tab.open),
            const SizedBox(width: 8),
            _tabChip('${_served.length} Completed', _Tab.completed),
            const SizedBox(width: 8),
            _tabChip('${_holdTickets.length} On Hold', _Tab.hold),
          ],
        ),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            ),
          IconButton(
            tooltip: DeviceCredentials.stationName ?? 'Station',
            icon: const Icon(Icons.kitchen),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'switch') {
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => const StationSetupScreen()));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'station',
                enabled: false,
                child: Text(
                    '${DeviceCredentials.stationName ?? 'Station'} · v$kAppVersion'),
              ),
              const PopupMenuItem(
                  value: 'switch', child: Text('Change station / operator')),
            ],
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _tabChip(String label, _Tab tab) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kBlue : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not reach the kitchen feed\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      );
    }
    final tickets = _visible;
    if (tickets.isEmpty) {
      return Center(
        child: Text(
          _tab == _Tab.open
              ? 'No open orders'
              : _tab == _Tab.hold
                  ? 'Nothing on hold'
                  : 'No completed orders',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340, // wider, to fit Back + 3 stage buttons
        mainAxisExtent: 320,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final t = tickets[i];
        return _TicketCard(
          ticket: t,
          headerColor: _headerColor(t),
          elapsedLabel: _elapsedLabel(t),
          onOpen: () => _openTicket(t),
          onStart: () => _start(t),
          onDone: () => _done(t),
          onServe: () => _pickup(t),
          onResume: () => _resume(t),
          onBack: () => _stepBack(t),
        );
      },
    );
  }

  int _liveAge(KitchenTicket t) {
    final drift = DateTime.now().difference(t.receivedAt).inSeconds;
    final serverPlusDrift = t.secondsSinceReceived;
    return drift > serverPlusDrift ? drift : serverPlusDrift;
  }

  Color _headerColor(KitchenTicket t) {
    if (t.isCompleted) return const Color(0xFF718096); // slate — completed
    if (t.isReady) return _kGreen;
    if (t.isOnHold) return Colors.blueGrey;
    final age = _liveAge(t);
    if (age >= _redAfter) return const Color(0xFFE53E3E);
    if (age >= _amberAfter) return const Color(0xFFDD9B36);
    return _kGreen;
  }

  String _elapsedLabel(KitchenTicket t) {
    final age = _liveAge(t);
    final m = (age ~/ 60).toString().padLeft(2, '0');
    final s = (age % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

String fmtClock(DateTime dt) {
  final t = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

(String, Color) statusChip(String status) {
  switch (status) {
    case 'IN_PROGRESS':
      return ('In progress', Colors.orange.shade800);
    case 'READY':
      return ('Ready', _kGreen);
    case 'ON_HOLD':
      return ('On hold', Colors.blueGrey);
    case 'PICKED_UP':
      return ('Picked up', _kServeGreen);
    case 'SERVED':
      return ('Served', _kServeGreen);
    default:
      return ('New', Colors.grey.shade600);
  }
}

/// A single forward-action button that cycles through the lifecycle on the
/// same button, changing label + colour at each state:
///   Start (blue) → Made (amber) → Serve (green).
/// A leading Back step reverses one stage. Used on the card and (larger) in
/// the detail modal.
class _ActionBar extends StatelessWidget {
  final KitchenTicket ticket;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onServe;
  final VoidCallback onBack;
  final double height;

  const _ActionBar({
    required this.ticket,
    required this.onStart,
    required this.onDone,
    required this.onServe,
    required this.onBack,
    this.height = 44,
  });

  /// (label, colour, action) for the current forward step.
  (String, Color, VoidCallback)? _forward() {
    switch (ticket.status) {
      case 'NEW':
        return ('Start', _kBlue, onStart);
      case 'IN_PROGRESS':
        return ('Made', _kAmber, onDone);
      case 'READY':
        // "Picked Up" — handed to the runner; delivery is the runner's job.
        return ('Picked Up', _kGreen, onServe);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fwd = _forward();
    final canBack = ticket.doneCount > 0;
    final fontSize = height >= 50 ? 18.0 : 15.0;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          // Back — step one stage backwards. Always shown so the control is
          // consistent; greyed (not actionable) on NEW, which has no prior
          // stage to return to.
          SizedBox(
            width: height,
            height: height,
            child: OutlinedButton(
              onPressed: canBack ? onBack : null,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: Colors.blueGrey.shade700,
                backgroundColor:
                    canBack ? const Color(0xFFEDF2F7) : Colors.grey.shade50,
                disabledForegroundColor: Colors.grey.shade400,
                side: BorderSide(
                    color: canBack
                        ? Colors.blueGrey.shade400
                        : Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Icon(Icons.arrow_back, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // The one cycling action button.
          Expanded(
            child: fwd == null
                ? const SizedBox.shrink()
                : ElevatedButton(
                    onPressed: fwd.$3,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fwd.$2,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(fwd.$1,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: fontSize)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A single order ticket card. Tap the body to open the full order modal;
/// the footer carries the Start/Done/Serve progress + Back. Long-press also
/// steps back (with confirm).
class _TicketCard extends StatelessWidget {
  final KitchenTicket ticket;
  final Color headerColor;
  final String elapsedLabel;
  final VoidCallback onOpen;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onServe;
  final VoidCallback onResume;
  final VoidCallback onBack;

  const _TicketCard({
    required this.ticket,
    required this.headerColor,
    required this.elapsedLabel,
    required this.onOpen,
    required this.onStart,
    required this.onDone,
    required this.onServe,
    required this.onResume,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final canBack = ticket.doneCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            onLongPress: canBack ? onBack : null,
            child: _header(),
          ),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              onLongPress: canBack ? onBack : null,
              child: _lines(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: ticket.isOnHold
                ? SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  )
                : ticket.isCompleted
                    ? _completedFooter()
                    : _ActionBar(
                        ticket: ticket,
                        onStart: onStart,
                        onDone: onDone,
                        onServe: onServe,
                        onBack: onBack,
                      ),
          ),
        ],
      ),
    );
  }

  // Completed-tab footer: picked up by a runner / delivered, + a Reopen
  // (step back) for a mistaken tap.
  Widget _completedFooter() {
    final delivered = ticket.isServed;
    final when = ticket.servedAt ?? ticket.readyAt;
    final label = delivered
        ? (when != null ? 'Served ${fmtClock(when)}' : 'Served')
        : 'Picked up';
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Icon(delivered ? Icons.check_circle : Icons.directions_run,
              color: _kServeGreen, size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  color: _kServeGreen, fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reopen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blueGrey,
              side: const BorderSide(color: Colors.blueGrey),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: headerColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${ticket.kitchenOrderId}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              Flexible(
                child: Text(
                  ticket.suiteName ?? 'Suite ${ticket.suiteId}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ticket.isInProgress && ticket.startedAt != null
                    ? 'Started ${fmtClock(ticket.startedAt!)}'
                    : fmtClock(ticket.receivedAt),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(_rightLabel(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  String _rightLabel() {
    if (ticket.isServed) return 'SERVED';
    if (ticket.isPickedUp) return 'PICKED UP';
    if (ticket.isReady) return 'READY';
    if (ticket.isInProgress) {
      final started = ticket.startedAt;
      if (started != null) {
        var secs = DateTime.now().difference(started).inSeconds;
        if (secs < 0) secs = 0;
        final m = (secs ~/ 60).toString().padLeft(2, '0');
        final s = (secs % 60).toString().padLeft(2, '0');
        return '▶ $m:$s';
      }
      return '▶ in prep';
    }
    return elapsedLabel;
  }

  Widget _lines() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final line in ticket.lines) ...[
          _LineRow(line: line),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// One `qty × drink` line with its modifier sub-lines and any note.
class _LineRow extends StatelessWidget {
  final KitchenTicketLine line;
  final double fontSize;
  const _LineRow({required this.line, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Text('${line.qty} ×',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: fontSize)),
              for (final m in line.modifiers)
                Text(m,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: fontSize - 2)),
              if (line.notes != null)
                Text('“${line.notes}”',
                    style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: fontSize - 2,
                        fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-order detail modal — the place the operator reads the order. Shows
/// every line + modifier + note, the timeline, and the full action set
/// (Start/Done/Serve + Back, Hold/Resume, Cancel).
class _TicketModal extends StatelessWidget {
  final KitchenTicket ticket;
  final Color headerColor;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onServe;
  final VoidCallback onHold;
  final VoidCallback onResume;
  final VoidCallback onBack;
  final VoidCallback onCancel;

  const _TicketModal({
    required this.ticket,
    required this.headerColor,
    required this.onStart,
    required this.onDone,
    required this.onServe,
    required this.onHold,
    required this.onResume,
    required this.onBack,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = statusChip(ticket.status);
    final size = MediaQuery.of(context).size;
    return SizedBox(
      height: size.height * 0.85,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: headerColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: headerColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Text('#${ticket.kitchenOrderId}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(ticket.suiteName ?? 'Suite ${ticket.suiteId}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
                const SizedBox(width: 4),
                // Print the order's labels (one per drink/cup).
                IconButton(
                  tooltip: 'Print labels',
                  icon: const Icon(Icons.print),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => LabelPreviewScreen(ticket: ticket)),
                  ),
                ),
              ],
            ),
          ),
          // Timeline
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _stamp('Placed', fmtClock(ticket.receivedAt)),
                _stamp('Started',
                    ticket.startedAt != null ? fmtClock(ticket.startedAt!) : '—'),
                _stamp('Ready',
                    ticket.readyAt != null ? fmtClock(ticket.readyAt!) : '—'),
                _stamp('Served',
                    ticket.servedAt != null ? fmtClock(ticket.servedAt!) : '—'),
              ],
            ),
          ),
          const Divider(height: 20),
          // Lines
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final line in ticket.lines) ...[
                  _LineRow(line: line, fontSize: 17),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          // Actions
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ticket.isCompleted
                  // Completed (picked up / delivered): just a Reopen step-back.
                  ? SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.undo),
                        label: const Text('Reopen order',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                          side: const BorderSide(color: Colors.blueGrey),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        if (ticket.isOnHold)
                          SizedBox(
                            height: 52,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: onResume,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Resume',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _kBlue,
                                  foregroundColor: Colors.white),
                            ),
                          )
                        else
                          _ActionBar(
                            ticket: ticket,
                            onStart: onStart,
                            onDone: onDone,
                            onServe: onServe,
                            onBack: onBack,
                            height: 54,
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (!ticket.isOnHold)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: onHold,
                                  icon: const Icon(Icons.pause),
                                  label: const Text('Hold'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blueGrey,
                                      side: const BorderSide(
                                          color: Colors.blueGrey)),
                                ),
                              ),
                            if (!ticket.isOnHold) const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onCancel,
                                icon: const Icon(Icons.close),
                                label: const Text('Cancel'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: BorderSide(color: Colors.red.shade300)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stamp(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
