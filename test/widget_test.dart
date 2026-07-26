import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stms/app.dart';
import 'package:stms/services/traffic_repository.dart';
import 'package:stms/services/traffic_store.dart';

void main() {
  testWidgets('renders the STMS operator overview', (
    tester,
  ) async {
    await tester.pumpWidget(
      TrafficApp(store: TrafficStore(DemoTrafficRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Traffic overview'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets(
    'phone navigation renders every primary screen without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        TrafficApp(store: TrafficStore(DemoTrafficRepository())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Incidents'));
      await tester.pumpAndSettle();
      expect(find.text('Incident review'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Video jobs'));
      await tester.pumpAndSettle();
      expect(find.text('Processing jobs'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('System settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
