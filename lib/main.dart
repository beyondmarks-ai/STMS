import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/traffic_repository.dart';
import 'services/traffic_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  final useEmulatorApi =
      apiBaseUrl.isEmpty &&
      kDebugMode &&
      defaultTargetPlatform == TargetPlatform.android;
  final repository = apiBaseUrl.isNotEmpty
      ? ApiTrafficRepository(apiBaseUrl)
      : useEmulatorApi
      ? ApiTrafficRepository('http://10.0.2.2:8001')
      : DemoTrafficRepository();
  runApp(TrafficApp(store: TrafficStore(repository)));
}
