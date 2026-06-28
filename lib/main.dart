import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/app_info.dart';
import 'screens/kitchen_display_screen.dart';
import 'screens/station_setup_screen.dart';
import 'services/device_credentials.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // KDS is a fixed bench/wall tablet — landscape only.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await DeviceCredentials.load();
  runApp(const KitchenApp());
}

class KitchenApp extends StatelessWidget {
  const KitchenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Boot straight to the display when fully provisioned (PAT + station);
    // otherwise show setup.
    final provisioned =
        DeviceCredentials.hasCredentials && DeviceCredentials.hasStation;
    return MaterialApp(
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2C7BE5),
        useMaterial3: true,
      ),
      home: provisioned
          ? const KitchenDisplayScreen()
          : const StationSetupScreen(),
    );
  }
}
