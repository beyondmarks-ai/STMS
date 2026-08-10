import 'package:flutter/material.dart';

import 'app.dart';
import 'services/traffic_repository.dart';
import 'services/traffic_store.dart';

const _productionApiBaseUrl =
    'https://stmsprod-api.wonderfulgrass-31348be0.centralindia.azurecontainerapps.io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _productionApiBaseUrl,
  );
  runApp(TrafficApp(store: TrafficStore(ApiTrafficRepository(apiBaseUrl))));
}
