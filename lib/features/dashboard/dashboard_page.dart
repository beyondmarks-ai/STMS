import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/violation.dart';
import '../../services/traffic_store.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.store,
    required this.onOpenIncidents,
  });
  final TrafficStore store;
  final VoidCallback onOpenIncidents;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => RefreshIndicator(
      onRefresh: store.load,
      child: ListView(
        padding: pagePadding(context),
        children: [
          PageHeader(
            eyebrow: 'Operations center · Live',
            title: 'Traffic overview',
            description:
                'Human-reviewed incident intelligence across configured cameras.',
            action: IconButton.filledTonal(
              onPressed: store.load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          if (store.error != null) ...[
            const SizedBox(height: 18),
            _ErrorBanner(message: store.error!),
          ],
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1050
                  ? 4
                  : constraints.maxWidth > 330
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _MetricCard(
                    width: width,
                    title: 'Pending review',
                    value: '${store.pendingCount}',
                    icon: Icons.fact_check_outlined,
                    color: AppColors.warning,
                    trend: 'Operator action required',
                  ),
                  _MetricCard(
                    width: width,
                    title: 'No helmet',
                    value: '${store.count(ViolationType.noHelmet)}',
                    icon: Icons.sports_motorsports_outlined,
                    color: AppColors.danger,
                    trend: 'Across processed clips',
                  ),
                  _MetricCard(
                    width: width,
                    title: 'Wrong side',
                    value: '${store.count(ViolationType.wrongSide)}',
                    icon: Icons.swap_vert_circle_outlined,
                    color: AppColors.blue,
                    trend: 'Direction-calibrated',
                  ),
                  _MetricCard(
                    width: width,
                    title: 'Videos processed',
                    value:
                        '${store.jobs.where((j) => j.status == JobStatus.completed).length}',
                    icon: Icons.video_library_outlined,
                    color: AppColors.success,
                    trend: 'Azure ML-ready pipeline',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Latest incidents',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'AI suggestions awaiting accountable review',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: onOpenIncidents,
                        child: const Text('View all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (store.loading && store.incidents.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (store.incidents.isEmpty)
                    const _EmptyState()
                  else
                    for (final incident in store.incidents.take(5))
                      _IncidentRow(incident: incident),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.trend,
  });
  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String trend;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 7, height: 7),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 7),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              trend,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident});
  final ViolationIncident incident;

  Color get color => switch (incident.type) {
    ViolationType.noHelmet => AppColors.danger,
    ViolationType.tripleRiding => AppColors.warning,
    ViolationType.wrongSide => AppColors.blue,
  ViolationType.ambulanceObstruction => const Color(0xFF8A64D6),
  ViolationType.tamperedPlate => AppColors.warning,
};

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.warning_amber_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incident.type.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${incident.camera}  ·  ${incident.plate}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${(incident.confidence * 100).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          if (!compact) const SizedBox(width: 14),
          if (!compact)
            StatusPill(
              label: incident.status.label,
              color: incident.status == ReviewStatus.pending
                  ? AppColors.warning
                  : incident.status == ReviewStatus.approved
                  ? AppColors.success
                  : AppColors.muted,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(40),
    child: Center(
      child: Text(
        'No incidents yet.',
        style: TextStyle(color: AppColors.muted),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}
