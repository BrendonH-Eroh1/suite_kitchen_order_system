/// Feedback (FDBK) configuration for the printed label's QR code.
///
/// The real per-suite QR payload/URL will be supplied by FDBK later — when it
/// arrives, replace the body of [qrDataForSuite] (and [servicePrompt] if the
/// wording changes). Everything else on the label is already wired to call
/// this, so swapping in the real scheme is a one-function change.
class FdbkConfig {
  /// The line printed above the QR.
  static const String servicePrompt = 'How was our Service?';

  /// Placeholder QR payload, coded by suite. Uses the venue-space code when
  /// available, else the numeric suite id.
  // TODO(fdbk): replace with the real FDBK URL/payload provided per suite.
  static String qrDataForSuite({
    required int suiteId,
    String? venueSpaceId,
    String? suiteName,
  }) {
    final code = (venueSpaceId != null && venueSpaceId.trim().isNotEmpty)
        ? venueSpaceId.trim()
        : 'suite-$suiteId';
    return 'https://feedback.example/box-seat/$code';
  }
}
