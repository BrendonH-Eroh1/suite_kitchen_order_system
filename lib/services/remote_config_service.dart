import 'dart:developer' as developer;

import '../printing/fdbk_config.dart';
import 'api_client.dart';

/// Loads backend-owned runtime config (`GET /v1/config`) and applies it, so
/// the coffee label's FDBK feedback host + store code are venue-configurable
/// without an app rebuild. Best-effort: failures leave the compile-time
/// defaults in place.
class RemoteConfigService {
  RemoteConfigService._();

  static Future<void> load() async {
    try {
      final data = await ApiClient.getJson('/v1/config');
      if (data is! Map) return;
      final fdbk = data['fdbk'];
      if (fdbk is Map) {
        FdbkConfig.configure(
          scanHost: fdbk['scan_host']?.toString(),
          storeCode: fdbk['store_code']?.toString(),
        );
      }
    } catch (e) {
      developer.log('RemoteConfigService.load failed (using defaults): $e');
    }
  }
}
