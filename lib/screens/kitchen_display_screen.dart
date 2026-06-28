import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../config/app_info.dart';
import '../models/kitchen_ticket.dart';
import '../services/device_credentials.dart';
import '../services/kitchen_station_service.dart';
import '../services/ticket_printer.dart';
import 'station_setup_screen.dart';

/// The Kitchen Display System rail. A card grid of order tickets with
/// Open / Done / On Hold tabs, age-coloured headers, live elapsed timers,
/// `qty × drink` lines with modifier sub-lines, and Done / Hold actions —
/// modelled on a standard KDS layout.
class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

enum _Tab { open, done, hold }

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen> {
  // The whole active rail in one fetch: NEW + IN_PROGRESS (Open),
  // READY (Done — made, awaiting hand-off), ON_HOLD. SERVED/CANCELLED are
  // terminal and drop off the board.
  List<KitchenTicket> _active = [];
  _Tab _tab = _Tab.open;
  bool _loading = true;
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
      final active = await KitchenStationService.getTickets(_stationId);
      if (!mounted) return;
      // Fire the (v1 no-op) printer hook the first time we see a ticket.
      for (final t in active) {
        if (_printed.add(t.kitchenOrderId)) {
          TicketPrinter.printTicket(t);
        }
      }
      setState(() {
        _active = active;
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

  // Open = received + being made; Done = made & awaiting hand-off (READY);
  // Hold = parked.
  List<KitchenTicket> get _openTickets =>
      _active.where((t) => t.isNew || t.isInProgress).toList();
  List<KitchenTicket> get _doneTickets =>
      _active.where((t) => t.isReady).toList();
  List<KitchenTicket> get _holdTickets =>
      _active.where((t) => t.isOnHold).toList();

  List<KitchenTicket> get _visible {
    switch (_tab) {
      case _Tab.open:
        return _openTickets;
      case _Tab.hold:
        return _holdTickets;
      case _Tab.done:
        return _doneTickets;
    }
  }

  Future<void> _act(
    String label,
    Future<void> Function() call,
  ) async {
    try {
      await call();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmCancel(KitchenTicket t) async {
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
      await _act('Cancel',
          () => KitchenStationService.cancel(t.kitchenOrderId, _operatorId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C7BE5),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            _tabChip('${_openTickets.length} Open', _Tab.open),
            const SizedBox(width: 8),
            _tabChip('${_doneTickets.length} Done', _Tab.done),
            const SizedBox(width: 8),
            _tabChip('${_holdTickets.length} On Hold', _Tab.hold),
          ],
        ),
        actions: [
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
      onTap: () {
        setState(() => _tab = tab);
        if (tab == _Tab.done) _refresh();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF2C7BE5) : Colors.white,
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
                  : 'Nothing ready',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 290,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: tickets.length,
      itemBuilder: (context, i) => _TicketCard(
        ticket: tickets[i],
        headerColor: _headerColor(tickets[i]),
        elapsedLabel: _elapsedLabel(tickets[i]),
        onStart: () => _act('Start',
            () => KitchenStationService.start(tickets[i].kitchenOrderId, _operatorId)),
        onDone: () => _act('Done',
            () => KitchenStationService.done(tickets[i].kitchenOrderId, _operatorId)),
        onHold: () => _act('Hold',
            () => KitchenStationService.hold(tickets[i].kitchenOrderId, _operatorId)),
        onResume: () => _act('Resume',
            () => KitchenStationService.resume(tickets[i].kitchenOrderId, _operatorId)),
        onServe: () => _act('Serve',
            () => KitchenStationService.serve(tickets[i].kitchenOrderId, _operatorId)),
        onCancel: () => _confirmCancel(tickets[i]),
      ),
    );
  }

  // Header colour is driven by the ticket's age. We add the client-side
  // seconds elapsed since the last poll to the server figure so the colour
  // keeps advancing smoothly between refreshes.
  int _liveAge(KitchenTicket t) {
    final drift = DateTime.now().difference(t.receivedAt).inSeconds;
    // Prefer the larger of (server figure) and (since receivedAt) — both are
    // approximations; receivedAt drift covers the gap between polls.
    final serverPlusDrift = t.secondsSinceReceived;
    return drift > serverPlusDrift ? drift : serverPlusDrift;
  }

  Color _headerColor(KitchenTicket t) {
    if (t.isReady) return const Color(0xFF38A169); // green — made
    if (t.isOnHold) return Colors.blueGrey;
    final age = _liveAge(t);
    if (age >= _redAfter) return const Color(0xFFE53E3E); // red
    if (age >= _amberAfter) return const Color(0xFFDD9B36); // amber
    return const Color(0xFF38A169); // green — fresh
  }

  String _elapsedLabel(KitchenTicket t) {
    final age = _liveAge(t);
    final m = (age ~/ 60).toString().padLeft(2, '0');
    final s = (age % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// A single order ticket card — header strip (order #, suite, placed time +
/// elapsed timer), body of `qty × drink` lines with grey modifier sub-lines,
/// and footer action buttons that change with the ticket's state.
class _TicketCard extends StatelessWidget {
  final KitchenTicket ticket;
  final Color headerColor;
  final String elapsedLabel;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onHold;
  final VoidCallback onResume;
  final VoidCallback onServe;
  final VoidCallback onCancel;

  const _TicketCard({
    required this.ticket,
    required this.headerColor,
    required this.elapsedLabel,
    required this.onStart,
    required this.onDone,
    required this.onHold,
    required this.onResume,
    required this.onServe,
    required this.onCancel,
  });

  String _placedTime() => _fmtTime(ticket.receivedAt);

  String _fmtTime(DateTime dt) {
    final t = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tapping a NEW card starts it (matches "tap to start").
      onTap: ticket.isNew ? onStart : null,
      onLongPress: onCancel,
      child: Container(
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
            _header(),
            Expanded(child: _lines()),
            _footer(context),
          ],
        ),
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
                child: Text(
                  '#${ticket.kitchenOrderId}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
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
                    ? 'Started ${_fmtTime(ticket.startedAt!)}'
                    : _placedTime(),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _rightLabel(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Right-side header label: READY when made; a ▶ prep timer once started
  // (captures "started"); otherwise the wait-since-received age.
  String _rightLabel() {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                child: Text('${line.qty} ×',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    for (final m in line.modifiers)
                      Text(m,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12)),
                    if (line.notes != null)
                      Text('“${line.notes}”',
                          style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                              fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _footer(BuildContext context) {
    // Explicit per-status flow so "started" and "done" are distinct,
    // captured steps:
    //   NEW         → Start (begin making) + Hold
    //   IN_PROGRESS → Done (made → READY)  + Hold
    //   READY       → Serve (delivered → leaves board)
    //   ON_HOLD     → Resume
    final buttons = <Widget>[];
    if (ticket.isOnHold) {
      buttons.add(_btn('Resume', const Color(0xFF2C7BE5), onResume, filled: true));
    } else if (ticket.isReady) {
      buttons.add(_btn('Serve', const Color(0xFF38A169), onServe, filled: true));
    } else if (ticket.isInProgress) {
      buttons.add(_btn('Done', const Color(0xFF38A169), onDone, filled: true));
      buttons.add(const SizedBox(width: 8));
      buttons.add(_btn('Hold', Colors.blueGrey, onHold, filled: false));
    } else {
      // NEW — not started yet.
      buttons.add(_btn('Start', const Color(0xFF2C7BE5), onStart, filled: true));
      buttons.add(const SizedBox(width: 8));
      buttons.add(_btn('Hold', Colors.blueGrey, onHold, filled: false));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(children: buttons),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap,
      {required bool filled}) {
    return Expanded(
      child: SizedBox(
        height: 40,
        child: filled
            ? ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }
}
