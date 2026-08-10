import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/incidents/incidents_page.dart';
import 'features/jobs/jobs_page.dart';
import 'features/settings/settings_page.dart';
import 'features/vehicles/vehicles_page.dart';
import 'services/traffic_store.dart';

class TrafficApp extends StatelessWidget {
  const TrafficApp({super.key, required this.store});
  final TrafficStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'STMS',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: OperatorShell(store: store),
  );
}

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key, required this.store});
  final TrafficStore store;

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int index = 0;

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.grid_view_rounded),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'Overview',
    ),
    NavigationDestination(
      icon: Icon(Icons.warning_amber_rounded),
      selectedIcon: Icon(Icons.warning_rounded),
      label: 'Incidents',
    ),
    NavigationDestination(
      icon: Icon(Icons.directions_car_outlined),
      selectedIcon: Icon(Icons.directions_car_filled_rounded),
      label: 'Vehicles',
    ),
    NavigationDestination(
      icon: Icon(Icons.video_file_outlined),
      selectedIcon: Icon(Icons.video_file_rounded),
      label: 'Video jobs',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_rounded),
      selectedIcon: Icon(Icons.tune_rounded),
      label: 'Settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    widget.store.load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        store: widget.store,
        onOpenIncidents: () => setState(() => index = 1),
      ),
      IncidentsPage(store: widget.store),
      VehiclesPage(store: widget.store),
      JobsPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = IndexedStack(index: index, children: pages);
        if (!wide) {
          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 62,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 18,
              title: const _MobileBrand(),
              actions: const [_LiveIndicator(), SizedBox(width: 18)],
            ),
            body: SafeArea(child: content),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: destinations,
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 238,
                color: AppColors.ink,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Brand(),
                      const SizedBox(height: 24),
                      for (var i = 0; i < destinations.length; i++)
                        _SideDestination(
                          destination: destinations[i],
                          selected: i == index,
                          onTap: () => setState(() => index = i),
                        ),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: _SystemStatus(),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: SafeArea(child: content)),
            ],
          ),
        );
      },
    );
  }
}

class _MobileBrand extends StatelessWidget {
  const _MobileBrand();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        child: Image(
          image: AssetImage('assets/branding/stms_logo_256.png'),
          width: 34,
          height: 34,
        ),
      ),
      SizedBox(width: 10),
      Text('STMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    ],
  );
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 7, height: 7),
        ),
        SizedBox(width: 6),
        Text(
          'LIVE',
          style: TextStyle(
            color: AppColors.success,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
      ],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 24, 16, 0),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          child: Image(
            image: AssetImage('assets/branding/stms_logo_256.png'),
            width: 44,
            height: 44,
          ),
        ),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STMS',
              style: TextStyle(
                color: AppColors.lime,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            Text(
              'Control Centre',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SideDestination extends StatelessWidget {
  const _SideDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });
  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Material(
      color: selected ? Colors.white.withValues(alpha: .1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              IconTheme(
                data: IconThemeData(
                  color: selected ? AppColors.lime : AppColors.mutedOnInk,
                  size: 21,
                ),
                child: destination.icon,
              ),
              const SizedBox(width: 13),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.mutedOnInk,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SystemStatus extends StatelessWidget {
  const _SystemStatus();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: 8, height: 8),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All systems normal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Azure-ready services',
                style: TextStyle(color: AppColors.mutedOnInk, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
