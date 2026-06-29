import 'package:flutter/material.dart';
import '../config/app_info.dart';
import '../services/device_credentials.dart';
import '../services/kitchen_station_service.dart';
import 'kitchen_display_screen.dart';
import 'qr_scan_screen.dart';

/// One-time KDS provisioning: enter the device PAT (issued by the SiS admin
/// app), pick the kitchen station this tablet serves, and set the operator
/// id stamped on ticket actions. Persisted in DeviceCredentials so the app
/// boots straight to the display next time.
///
/// v1 takes the PAT via paste; QR scanning (mobile_scanner) is the planned
/// v2 enhancement, matching the suite app's DeviceSetupScreen.
class StationSetupScreen extends StatefulWidget {
  const StationSetupScreen({super.key});

  @override
  State<StationSetupScreen> createState() => _StationSetupScreenState();
}

class _StationSetupScreenState extends State<StationSetupScreen> {
  final _deviceIdCtl = TextEditingController(
      text: DeviceCredentials.deviceId ?? '');
  final _patCtl = TextEditingController();
  final _operatorCtl = TextEditingController();

  List<KitchenStation> _stations = [];
  int? _selectedStationId;
  bool _loadingStations = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (DeviceCredentials.hasCredentials) {
      _loadStations();
    }
  }

  @override
  void dispose() {
    _deviceIdCtl.dispose();
    _patCtl.dispose();
    _operatorCtl.dispose();
    super.dispose();
  }

  /// Open the camera scanner; on a valid provisioning QR, fill the fields
  /// and immediately save + load stations (same as the manual Save button).
  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<ScannedCredentials>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (scanned == null || !mounted) return;
    _deviceIdCtl.text = scanned.deviceId;
    _patCtl.text = scanned.pat;
    await _saveCredentials();
  }

  Future<void> _saveCredentials() async {
    final deviceId = _deviceIdCtl.text.trim();
    final pat = _patCtl.text.trim();
    if (deviceId.isEmpty || pat.isEmpty) {
      setState(() => _error = 'Device ID and PAT are both required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await DeviceCredentials.save(deviceId: deviceId, pat: pat);
    setState(() => _saving = false);
    await _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _loadingStations = true;
      _error = null;
    });
    try {
      final stations = await KitchenStationService.getStations();
      setState(() {
        _stations = stations;
        _selectedStationId ??= DeviceCredentials.stationId ??
            (stations.isNotEmpty ? stations.first.stationId : null);
      });
    } catch (e) {
      setState(() => _error = 'Could not load stations: $e');
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _finish() async {
    final stationId = _selectedStationId;
    final operatorId = int.tryParse(_operatorCtl.text.trim());
    if (stationId == null) {
      setState(() => _error = 'Select a station');
      return;
    }
    if (operatorId == null || operatorId <= 0) {
      setState(() => _error = 'Enter a valid operator ID');
      return;
    }
    final station =
        _stations.firstWhere((s) => s.stationId == stationId);
    await DeviceCredentials.saveStation(
      stationId: stationId,
      stationName: station.stationName,
      operatorStaffId: operatorId,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const KitchenDisplayScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCreds = DeviceCredentials.hasCredentials;
    return Scaffold(
      appBar: AppBar(
        title: const Text('$kProductName · Setup'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                ),
                const SizedBox(height: 16),
              ],
              const Text('1 · Device credentials',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              // Primary path: scan the provisioning QR (device_id + PAT).
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan provisioning QR',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C7BE5),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or enter manually',
                        style: TextStyle(color: Colors.grey.shade500)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceIdCtl,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _patCtl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText:
                      hasCreds ? 'PAT (already provisioned)' : 'Snowflake PAT',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _saving ? null : _saveCredentials,
                child: Text(_saving ? 'Saving…' : 'Save & Load Stations'),
              ),
              const Divider(height: 40),
              const Text('2 · Station & operator',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_loadingStations)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_stations.isEmpty)
                const Text('Save credentials to load stations.',
                    style: TextStyle(color: Colors.grey))
              else
                DropdownButtonFormField<int>(
                  initialValue: _selectedStationId,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen station',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in _stations)
                      DropdownMenuItem(
                        value: s.stationId,
                        child: Text('${s.stationName} (#${s.stationId})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedStationId = v),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _operatorCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Operator (barista) staff ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed:
                      _stations.isEmpty || _saving ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Open Kitchen Display',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text('Ver. $kAppVersion',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
