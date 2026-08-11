import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/penalty.dart';
import '../../services/traffic_store.dart';

class PenaltiesPage extends StatefulWidget {
  const PenaltiesPage({super.key, required this.store});
  final TrafficStore store;

  @override
  State<PenaltiesPage> createState() => _PenaltiesPageState();
}

class _PenaltiesPageState extends State<PenaltiesPage> {
  final searchController = TextEditingController();
  PenaltyStatus? status;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final needle = searchController.text.trim().toLowerCase();
      final records = widget.store.penalties.where((penalty) {
        final matchesSearch =
            needle.isEmpty ||
            penalty.plate.toLowerCase().contains(needle) ||
            penalty.violationLabel.toLowerCase().contains(needle) ||
            penalty.camera.toLowerCase().contains(needle);
        return matchesSearch && (status == null || penalty.status == status);
      }).toList();
      final active = widget.store.penalties
          .where((item) => item.status != PenaltyStatus.voided)
          .toList();
      final pendingAmount = active
          .where((item) => item.status == PenaltyStatus.pending)
          .fold<int>(0, (sum, item) => sum + item.amount);
      final confirmedAmount = active
          .where((item) => item.status == PenaltyStatus.confirmed)
          .fold<int>(0, (sum, item) => sum + item.amount);

      return RefreshIndicator(
        onRefresh: widget.store.load,
        child: ListView(
          padding: pagePadding(context),
          children: [
            const PageHeader(
              eyebrow: 'Enforcement ledger',
              title: 'Vehicle penalties',
              description:
                  'OCR-linked fines grouped by registration number. Unreadable plates are automatically skipped.',
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final itemWidth = width >= 760 ? (width - 24) / 3 : width;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      width: itemWidth,
                      icon: Icons.directions_car_filled_rounded,
                      label: 'Vehicles identified',
                      value: '${widget.store.vehiclePenaltySummaries.length}',
                      color: AppColors.blue,
                    ),
                    _MetricCard(
                      width: itemWidth,
                      icon: Icons.schedule_rounded,
                      label: 'Pending review',
                      value: _money(pendingAmount),
                      color: AppColors.warning,
                    ),
                    _MetricCard(
                      width: itemWidth,
                      icon: Icons.verified_rounded,
                      label: 'Confirmed penalties',
                      value: _money(confirmedAmount),
                      color: AppColors.success,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            _VehicleSummarySection(
              summaries: widget.store.vehiclePenaltySummaries,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Penalty records',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'One record per incident. Reprocessing the same incident cannot duplicate a penalty.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search plate, violation or camera',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: status == null,
                            onTap: () => setState(() => status = null),
                          ),
                          for (final item in PenaltyStatus.values) ...[
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: item.label,
                              selected: status == item,
                              onTap: () => setState(() => status = item),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.store.loading && records.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (records.isEmpty)
                      const _EmptyPenalties()
                    else
                      for (final record in records) _PenaltyRow(record: record),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _TariffSchedule(),
          ],
        ),
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 3),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VehicleSummarySection extends StatelessWidget {
  const _VehicleSummarySection({required this.summaries});
  final List<VehiclePenaltySummary> summaries;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.ink,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle penalty totals',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Repeat violations accumulate under the same normalized OCR plate.',
            style: TextStyle(color: AppColors.mutedOnInk),
          ),
          const SizedBox(height: 14),
          if (summaries.isEmpty)
            const Text(
              'No readable registration numbers have penalties yet.',
              style: TextStyle(color: AppColors.mutedOnInk),
            )
          else
            for (final summary in summaries.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.plate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${summary.penaltyCount} penalties · ${summary.pendingCount} pending',
                            style: const TextStyle(
                              color: AppColors.mutedOnInk,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _money(summary.totalAmount),
                      style: const TextStyle(
                        color: AppColors.lime,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    ),
  );
}

class _PenaltyRow extends StatelessWidget {
  const _PenaltyRow({required this.record});
  final PenaltyRecord record;

  Color get statusColor => switch (record.status) {
    PenaltyStatus.pending => AppColors.warning,
    PenaltyStatus.confirmed => AppColors.success,
    PenaltyStatus.voided => AppColors.muted,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.receipt_long_rounded, color: statusColor, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    record.plate,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  StatusPill(label: record.status.label, color: statusColor),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                record.violationLabel,
                style: const TextStyle(color: AppColors.text),
              ),
              Text(
                '${record.camera} · ${_date(record.detectedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _money(record.amount),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

class _EmptyPenalties extends StatelessWidget {
  const _EmptyPenalties();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 34),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.no_crash_outlined, size: 36, color: AppColors.muted),
          SizedBox(height: 10),
          Text('No OCR-linked penalties match these filters.'),
        ],
      ),
    ),
  );
}

class _TariffSchedule extends StatelessWidget {
  const _TariffSchedule();
  static const tariffs = [
    ('No helmet', 1000),
    ('Triple riding', 1000),
    ('Wrong-side driving', 500),
    ('Ambulance obstruction', 10000),
  ];

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fixed tariff schedule',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          const Text(
            'Pilot configuration in INR. Confirm applicable local rules before production enforcement.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          for (final tariff in tariffs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 7, color: AppColors.lime),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tariff.$1)),
                  Text(
                    _money(tariff.$2),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

String _money(int amount) {
  final digits = amount.toString();
  if (digits.length <= 3) return '₹$digits';
  final tail = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (head.length > 2) {
    groups.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) groups.insert(0, head);
  return '₹${groups.join(',')},$tail';
}

String _date(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}
