/// SEP proxy connection config.
///
/// Auth lives in `DeviceCredentials` (per-device PAT, scanned via QR
/// from the SiS admin app or pushed via MDM Managed Configuration).
/// There is no bundled fallback PAT — every API call requires the
/// per-device PAT and `ApiClient` throws `NotProvisionedException` if
/// it isn't present.
///
/// `baseUrl` can be overridden at build time with
///   --dart-define=SEP_PROXY_URL=https://your-other-proxy
/// e.g. to point a DEV build at a test proxy during development.
class ProxyConfig {
  /// SPCS public ingress for the SEP proxy. Stable across deploys when
  /// using `ALTER SERVICE FROM SPECIFICATION` (only changes on full
  /// DROP+CREATE).
  static const String baseUrl = String.fromEnvironment(
    'SEP_PROXY_URL',
    defaultValue: 'https://eczkad-aosma-sp79574.snowflakecomputing.app',
  );
}

// SVD configuration is no longer hardcoded here. The tablet now fetches
// per-suite AV config (host_url, group_id, player_ids, pin) at runtime
// from the SPCS proxy at GET /v1/av/config?suite_id=N. See
// `lib/features/av_control/state/av_config_store.dart`.
