/// Feedback (FDBK) configuration for the printed coffee label's QR code.
///
/// FDBK serves scans from the public *app* host under a fixed store code for
/// all Adelaide Oval corporate suites, following FDBK's documented scan-URL
/// convention:
///
///   {host}/s/{storeCode}/{tag}?device_id={device_id}
///
/// The coffee label uses the `coffee` tag (its own survey) and keys
/// `device_id` to the suite barcode (e.g. 'AOC002') so feedback attributes to
/// the right suite and accumulates across events:
///
///   https://staging.app.fdbkinsights.com/s/OF5CJ8R8OX/coffee?device_id=AOC002
class FdbkConfig {
  /// The line printed above the QR.
  static const String servicePrompt = 'How was our Service?';

  /// Public scan host (the *app* host that serves scans — not the dashboard
  /// build portal). Staging default; the real value is backend-owned and
  /// loaded from `GET /v1/config` at startup (see [configure]) so a venue can
  /// change it without an app rebuild.
  static String scanHost = _kScanHostDefault;

  /// FDBK store code for this venue's suites. Backend-owned (see [scanHost]).
  static String storeCode = _kStoreCodeDefault;

  /// Survey tag for coffee requests.
  static const String coffeeTag = 'coffee';

  /// Compile-time fallbacks — used until [configure] runs, and if `/v1/config`
  /// is unreachable. Keep in step with the proxy's `config._DEFAULTS`.
  static const String _kScanHostDefault = 'https://staging.app.fdbkinsights.com';
  static const String _kStoreCodeDefault = 'OF5CJ8R8OX';

  /// Apply backend config fetched from `GET /v1/config`. Blank values ignored
  /// so a partial payload never wipes a working default.
  static void configure({String? scanHost, String? storeCode}) {
    if (scanHost != null && scanHost.trim().isNotEmpty) {
      FdbkConfig.scanHost = scanHost.trim();
    }
    if (storeCode != null && storeCode.trim().isNotEmpty) {
      FdbkConfig.storeCode = storeCode.trim();
    }
  }

  /// Coffee-survey QR URL for a suite, keyed to its barcode as device_id.
  /// Falls back to the tag-only URL (no device_id) if the barcode is unknown.
  static String qrDataForSuite({
    required int suiteId,
    String? suiteCode,
    String? suiteName,
  }) {
    final base = '$scanHost/s/$storeCode/$coffeeTag';
    final code = suiteCode?.trim() ?? '';
    return code.isEmpty
        ? base
        : '$base?device_id=${Uri.encodeQueryComponent(code)}';
  }
}
