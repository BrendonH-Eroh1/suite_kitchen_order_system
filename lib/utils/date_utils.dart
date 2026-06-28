class DateUtils {
  /// Current time as ISO8601 with the device's local timezone offset.
  /// Tablets are fixed at Adelaide Oval, so the offset is ACST (+09:30) or
  /// ACDT (+10:30) depending on DST — Dart reads it from the OS automatically.
  /// Example: '2026-04-29T11:24:43.729908+09:30'
  static String nowLocalIso() {
    final now = DateTime.now();
    final base = now.toIso8601String();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$base$sign$hours:$minutes';
  }

  static DateTime? parseSnowflakeTimestamp(dynamic value) {
    if (value == null || value.toString() == 'null') {
      return null;
    }

    try {
      var str = value.toString().trim();

      // Snowflake SQL API compact TIMESTAMP_TZ format:
      //   "<seconds>.<nanos> <offset_minutes + 1440>"
      // e.g. "1778248800.000000000 2010" — epoch is already UTC, the
      // trailing number is the source timezone offset (informational).
      final compact =
          RegExp(r'^(\d+(?:\.\d+)?)\s+(\d+)$').firstMatch(str);
      if (compact != null) {
        final epoch = double.tryParse(compact.group(1)!);
        if (epoch != null) {
          return DateTime.fromMillisecondsSinceEpoch(
            (epoch * 1000).round(),
            isUtc: true,
          );
        }
      }

      // Snowflake textual format: "2026-04-18 07:00:00.000 -0700"
      if (str.contains(' ') && !str.contains('T') && str.contains('-')) {
        final parts = str.split(' ');
        if (parts.length >= 2) {
          final datePart = parts[0];
          final timePart = parts[1];
          final tzPart = parts.length > 2 ? parts.sublist(2).join('') : '';
          str = '${datePart}T$timePart$tzPart';
        }
      }

      // Try ISO8601
      try {
        return DateTime.parse(str);
      } catch (_) {}

      // "<seconds>:<nanos>" style
      if (str.contains(':') && !str.contains('-')) {
        final parts = str.split(':');
        try {
          final seconds = int.parse(parts[0].trim());
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        } catch (_) {}
      }

      // Plain epoch seconds (with optional fractional)
      try {
        final seconds = double.parse(str.split(' ').first);
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round(),
          isUtc: true,
        );
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }
}
