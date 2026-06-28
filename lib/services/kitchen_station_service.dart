import 'dart:developer' as developer;
import '../models/kitchen_ticket.dart';
import 'api_client.dart';

/// Kitchen-side calls for the KDS: the station list (provisioning), the
/// live ticket feed for a station, and the lifecycle transitions a barista
/// drives from the rail. Mirrors the suite app's BeverageOrderService shape.
class KitchenStationService {
  /// Active kitchen stations — used by the setup screen's station picker.
  static Future<List<KitchenStation>> getStations() async {
    final body = await ApiClient.getJson('/v1/kitchen/stations');
    final list = body as List<dynamic>;
    return list
        .map((e) => KitchenStation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Tickets for [stationId]. Pass [status] (comma-separated, e.g. "SERVED")
  /// to fetch a specific tab; omit for the active rail.
  static Future<List<KitchenTicket>> getTickets(
    int stationId, {
    String? status,
  }) async {
    var path = '/v1/kitchen/orders?station_id=$stationId';
    if (status != null && status.isNotEmpty) {
      path += '&status=$status';
    }
    final body = await ApiClient.getJson(path);
    final list = body as List<dynamic>;
    return list
        .map((e) => KitchenTicket.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _action(int id, String verb, int staffId) async {
    await ApiClient.postJson('/v1/kitchen/orders/$id/$verb', {
      'staff_id': staffId,
    });
    developer.log('Kitchen order $id -> $verb by $staffId');
  }

  static Future<void> start(int id, int staffId) => _action(id, 'start', staffId);
  static Future<void> done(int id, int staffId) => _action(id, 'done', staffId);
  static Future<void> hold(int id, int staffId) => _action(id, 'hold', staffId);
  static Future<void> resume(int id, int staffId) => _action(id, 'resume', staffId);
  static Future<void> serve(int id, int staffId) => _action(id, 'serve', staffId);

  static Future<void> cancel(int id, int staffId, {String? reason}) async {
    final body = <String, dynamic>{'staff_id': staffId};
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    await ApiClient.postJson('/v1/kitchen/orders/$id/cancel', body);
    developer.log('Kitchen order $id cancelled by $staffId');
  }
}

class KitchenStation {
  final int stationId;
  final String stationName;
  final String? venueId;

  const KitchenStation({
    required this.stationId,
    required this.stationName,
    this.venueId,
  });

  factory KitchenStation.fromMap(Map<String, dynamic> map) {
    dynamic pick(String k) => map[k.toUpperCase()] ?? map[k.toLowerCase()];
    return KitchenStation(
      stationId: int.tryParse(pick('station_id').toString()) ?? 0,
      stationName: pick('station_name')?.toString() ?? 'Station',
      venueId: pick('venue_id')?.toString(),
    );
  }
}
