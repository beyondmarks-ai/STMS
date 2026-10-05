import 'package:flutter/material.dart';

import 'app.dart';
import 'services/traffic_repository.dart';
import 'services/traffic_store.dart';

const _productionApiBaseUrl =
    'http://stms-prod-alb-1785449816.ap-south-1.elb.amazonaws.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _productionApiBaseUrl,
  );
  runApp(TrafficApp(store: TrafficStore(ApiTrafficRepository(apiBaseUrl))));
}
