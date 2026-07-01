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
  /// build portal). Staging today; swap to app.fdbkinsights.com for prod.
  static const String scanHost = 'https://staging.app.fdbkinsights.com';

  /// FDBK store code shared by all Adelaide Oval corporate suites.
  static const String storeCode = 'OF5CJ8R8OX';

  /// Survey tag for coffee requests.
  static const String coffeeTag = 'coffee';

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
