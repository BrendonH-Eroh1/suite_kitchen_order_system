import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/proxy_config.dart';
import 'device_credentials.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Raised when the device has no per-device PAT scanned. Caller should
/// route the user to `DeviceSetupScreen` to provision via QR.
class NotProvisionedException implements Exception {
  @override
  String toString() => 'NotProvisionedException: device not provisioned';
}

/// Thin HTTP client for the SEP SPCS proxy. Adds the Snowflake PAT auth
/// header on every request and parses JSON responses.
///
/// Auth: requires a per-device PAT scanned via the SiS admin app and
/// stored in DeviceCredentials. No bundled fallback — fresh installs
/// must provision before any API call will succeed.
///
/// Retries: transient infra errors (502 / 503 / 504, and connection
/// failures) are silently retried with exponential backoff so a brief
/// SPCS cold-start or DNS hiccup doesn't bubble a red error to the
/// user. Idempotent by design — retries are safe because (a) GETs are
/// read-only and (b) every POST that mutates state carries a
/// `client_idempotency_key` UUID that the proxy de-dupes on.
class ApiClient {
  /// How many TOTAL attempts (1 original + retries). With the
  /// `_baseBackoff` of 600ms and exponential growth, 5 attempts spans
  /// roughly 600ms + 1.2s + 2.4s + 4.8s ≈ 9s of backoff — long enough
  /// to cover an SPCS warm-up tick (typically 5-8s once the compute
  /// pool has nodes) without leaving the operator staring at a frozen
  /// button forever.
  static const int _maxAttempts = 5;
  static const Duration _baseBackoff = Duration(milliseconds: 600);

  static String _authHeader() {
    final pat = DeviceCredentials.pat;
    if (pat == null || pat.isEmpty) {
      throw NotProvisionedException();
    }
    return 'Snowflake Token="$pat"';
  }

  /// Status codes that indicate the request did NOT reach our FastAPI
  /// code — the Snowflake SPCS gateway returned them because the
  /// service had no live hosts at the moment, or an upstream load
  /// balancer rejected. These are safe to retry on any verb.
  static bool _isRetryableStatus(int code) =>
      code == 502 || code == 503 || code == 504;

  /// Network-level failures we silently retry. SocketException covers
  /// DNS failures (incl. the SPCS `nxdomain.invalid` CNAME during
  /// recreation), connection-refused, and dropped sockets. HTTP
  /// client errors and timeouts also qualify.
  static bool _isRetryableError(Object error) =>
      error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException ||
      error is HandshakeException;

  /// Runs [send] up to `_maxAttempts` times with exponential backoff
  /// when a transient failure is detected. `label` is just for log
  /// readability so a developer scanning the device log can see which
  /// endpoint was retrying.
  static Future<http.Response> _withRetry(
    String label,
    Future<http.Response> Function() send,
  ) async {
    Object? lastError;
    http.Response? lastResponse;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await send();
        if (!_isRetryableStatus(response.statusCode)) {
          return response;
        }
        lastResponse = response;
        developer.log(
          'Retry $attempt/$_maxAttempts on $label '
          '— ${response.statusCode} (transient)',
        );
      } catch (e) {
        if (!_isRetryableError(e)) rethrow;
        lastError = e;
        developer.log('Retry $attempt/$_maxAttempts on $label — $e');
      }
      if (attempt < _maxAttempts) {
        // 600ms → 1.2s → 2.4s → 4.8s — geometric, no jitter (a single
        // tablet retrying its own calls doesn't need to spread load).
        final delay = _baseBackoff * (1 << (attempt - 1));
        await Future<void>.delayed(delay);
      }
    }
    if (lastResponse != null) return lastResponse;
    throw lastError ?? Exception('retry exhausted on $label');
  }

  static Future<dynamic> getJson(String path) async {
    final uri = Uri.parse('${ProxyConfig.baseUrl}$path');
    final response = await _withRetry(
      'GET $path',
      () => http.get(
        uri,
        headers: {
          'Authorization': _authHeader(),
          'Accept': 'application/json',
        },
      ),
    );
    if (response.statusCode != 200) {
      developer.log(
        'Proxy GET $path failed: ${response.statusCode} ${response.body}',
      );
      throw ApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body);
  }

  static Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ProxyConfig.baseUrl}$path');
    final encoded = jsonEncode(body);
    final response = await _withRetry(
      'POST $path',
      () => http.post(
        uri,
        headers: {
          'Authorization': _authHeader(),
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: encoded,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      developer.log(
        'Proxy POST $path failed: ${response.statusCode} ${response.body}',
      );
      throw ApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }
}
