import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-device provisioning credentials — `device_id` + Snowflake PAT, plus
/// the kitchen station this KDS tablet is bound to. PAT is issued by the SiS
/// admin app and scanned/entered at setup; the station is chosen from
/// GET /v1/kitchen/stations. Stored locally in SharedPreferences.
///
/// Loaded once at app startup via `load()` so subsequent reads are
/// synchronous from the in-memory cache.
class DeviceCredentials {
  static const String _deviceIdKey = 'sep_device_id';
  static const String _patKey = 'sep_device_pat';
  // KDS-specific: the kitchen station this tablet is bound to. The display
  // only ever shows tickets routed to this station.
  static const String _stationIdKey = 'kds_station_id';
  static const String _stationNameKey = 'kds_station_name';
  // The operator (barista) staff id stamped on ticket actions for audit.
  static const String _operatorStaffIdKey = 'kds_operator_staff_id';
  // Brother label printer (QL-810W) — WiFi IP + whether printing is enabled.
  static const String _printerIpKey = 'kds_printer_ip';
  static const String _printerEnabledKey = 'kds_printer_enabled';

  static String? _deviceId;
  static String? _pat;
  static int? _stationId;
  static String? _stationName;
  static int? _operatorStaffId;
  static String? _printerIp;
  static bool _printerEnabled = false;

  /// True when both auth fields are present in storage.
  static bool get hasCredentials =>
      _pat != null && _pat!.isNotEmpty &&
      _deviceId != null && _deviceId!.isNotEmpty;

  /// A KDS tablet is fully provisioned only once it also has a station.
  static bool get hasStation => _stationId != null;

  static String? get deviceId => _deviceId;
  static String? get pat => _pat;
  static int? get stationId => _stationId;
  static String? get stationName => _stationName;
  static int? get operatorStaffId => _operatorStaffId;
  static String? get printerIp => _printerIp;
  static bool get printerEnabled => _printerEnabled;

  /// True when label printing is switched on and an IP is set.
  static bool get canPrint =>
      _printerEnabled && _printerIp != null && _printerIp!.trim().isNotEmpty;

  /// Read from SharedPreferences into the in-memory cache. Call once at
  /// app startup before `runApp`.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    _pat = prefs.getString(_patKey);
    _stationId = prefs.getInt(_stationIdKey);
    _stationName = prefs.getString(_stationNameKey);
    _operatorStaffId = prefs.getInt(_operatorStaffIdKey);
    _printerIp = prefs.getString(_printerIpKey);
    _printerEnabled = prefs.getBool(_printerEnabledKey) ?? false;
  }

  static Future<void> savePrinter({
    required bool enabled,
    required String? ip,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_printerEnabledKey, enabled);
    if (ip == null || ip.trim().isEmpty) {
      await prefs.remove(_printerIpKey);
      _printerIp = null;
    } else {
      await prefs.setString(_printerIpKey, ip.trim());
      _printerIp = ip.trim();
    }
    _printerEnabled = enabled;
  }

  static Future<void> save({
    required String deviceId,
    required String pat,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, deviceId);
    await prefs.setString(_patKey, pat);
    _deviceId = deviceId;
    _pat = pat;
  }

  static Future<void> saveStation({
    required int stationId,
    required String stationName,
    required int operatorStaffId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stationIdKey, stationId);
    await prefs.setString(_stationNameKey, stationName);
    await prefs.setInt(_operatorStaffIdKey, operatorStaffId);
    _stationId = stationId;
    _stationName = stationName;
    _operatorStaffId = operatorStaffId;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_patKey);
    await prefs.remove(_stationIdKey);
    await prefs.remove(_stationNameKey);
    await prefs.remove(_operatorStaffIdKey);
    _deviceId = null;
    _pat = null;
    _stationId = null;
    _stationName = null;
    _operatorStaffId = null;
  }

  /// Expiry of the per-device PAT. Returns null if not provisioned or
  /// the PAT is malformed.
  static DateTime? get currentPatExpiry {
    final pat = _pat;
    if (pat == null || pat.isEmpty) return null;
    return _decodeJwtExpiry(pat);
  }

  static DateTime? _decodeJwtExpiry(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    try {
      var payload = parts[1];
      payload += '=' * ((4 - payload.length % 4) % 4);
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      final exp = json['exp'];
      if (exp is! int) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }
}
