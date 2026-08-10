import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/violation.dart';
import '../../services/traffic_store.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key, required this.store});

  final TrafficStore store;

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  String query = '';
  bool readableOnly = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final needle = query.trim().toLowerCase();
      final vehicles = widget.store.incidents.where((incident) {
        final readable = _hasReadablePlate(incident);
        final matchesQuery =
            needle.isEmpty ||
            incident.plate.toLowerCase().contains(needle) ||
            incident.camera.toLowerCase().contains(needle) ||
            _vehicleSummary(incident).toLowerCase().contains(needle);
        return (!readableOnly || readable) && matchesQuery;
      }).toList();
      final readableCount = widget.store.incidents
          .where(_hasReadablePlate)
          .length;
      final cropCount = widget.store.incidents
          .where(
            (incident) =>
                incident.plateCropUrl != null || incident.faceCropUrl != null,
          )
          .length;

      return RefreshIndicator(
        onRefresh: widget.store.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pagePadding(context),
          children: [
            const PageHeader(
              eyebrow: 'OCR evidence',
              title: 'Vehicle intelligence',
              description:
                  'Review detected registrations, vehicle attributes and rider evidence before any registry lookup.',
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  label: 'Vehicle detections',
                  value: '${widget.store.incidents.length}',
                  icon: Icons.directions_car_filled_outlined,
                  color: AppColors.blue,
                ),
                _SummaryCard(
                  label: 'Readable OCR',
                  value: '$readableCount',
                  icon: Icons.pin_outlined,
                  color: AppColors.success,
                ),
                _SummaryCard(
                  label: 'Evidence crops',
                  value: '$cropCount',
                  icon: Icons.crop_free_rounded,
                  color: AppColors.violet,
                ),
                const _SummaryCard(
                  label: 'DataFlag registry',
                  value: 'Not connected',
                  icon: Icons.cloud_off_outlined,
                  color: AppColors.warning,
                  compactValue: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _DataFlagNotice(),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 600
                      ? MediaQuery.sizeOf(context).width - 36
                      : 340,
                  child: TextField(
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search OCR plate, camera or vehicle',
                    ),
                  ),
                ),
                FilterChip(
                  selected: readableOnly,
                  onSelected: (value) => setState(() => readableOnly = value),
                  avatar: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Readable plates only'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (widget.store.loading && widget.store.incidents.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (vehicles.isEmpty)
              const _EmptyVehicles()
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 3
                      : constraints.maxWidth >= 680
                      ? 2
                      : 1;
                  const gap = 14.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final incident in vehicles)
                        SizedBox(
                          width: width,
                          child: _VehicleCard(
                            incident: incident,
                            onTap: () => _openDetails(context, incident),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      );
    },
  );

  Future<void> _openDetails(BuildContext context, ViolationIncident incident) =>
      showDialog<void>(
        context: context,
        builder: (context) => _VehicleDetails(incident: incident),
      );
}

bool _hasReadablePlate(ViolationIncident incident) {
  final value = incident.plate.trim().toLowerCase();
  return value.isNotEmpty && value != 'unreadable' && value != 'unknown';
}

String _vehicleSummary(ViolationIncident incident) {
  final values = [
    incident.vehicleColor,
    incident.vehicleMake,
    incident.vehicleModel,
    incident.vehicleBodyStyle,
    incident.vehicleType,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
  return values.isEmpty ? 'Vehicle details pending' : values.join(' · ');
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compactValue;

  @override
  Widget build(BuildContext context) => Container(
    width: MediaQuery.sizeOf(context).width < 600 ? 164 : 205,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compactValue ? 13 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DataFlagNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, color: AppColors.warning),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DataFlag lookup is prepared, not connected',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'STMS currently displays visual OCR and AI-estimated attributes only. Registered-owner data will remain hidden until the authorized API, consent and response fields are configured.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.incident, required this.onTap});

  final ViolationIncident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 8,
            child: _NetworkEvidence(
              url: incident.plateCropUrl ?? incident.evidenceUrl,
              icon: Icons.directions_car_outlined,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        incident.plate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                    StatusPill(
                      label: '${(incident.confidence * 100).round()}%',
                      color: AppColors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _vehicleSummary(incident),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.videocam_outlined,
                      size: 16,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        incident.camera,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _VehicleDetails extends StatelessWidget {
  const _VehicleDetails({required this.incident});

  final ViolationIncident incident;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 18 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detected vehicle',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          incident.plate,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const StatusPill(label: 'VISUAL OCR', color: AppColors.blue),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth < 620
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _CropPanel(
                          label: 'Licence plate crop',
                          url: incident.plateCropUrl,
                          icon: Icons.pin_outlined,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _CropPanel(
                          label: 'Rider face crop',
                          url: incident.faceCropUrl,
                          icon: Icons.face_retouching_natural_outlined,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailFact(label: 'Camera', value: incident.camera),
                  _DetailFact(
                    label: 'Detected',
                    value: _formatDate(incident.detectedAt),
                  ),
                  _DetailFact(
                    label: 'Vehicle',
                    value: _vehicleSummary(incident),
                  ),
                  _DetailFact(label: 'Violation', value: incident.type.label),
                  _DetailFact(
                    label: 'OCR confidence',
                    value: '${(incident.confidence * 100).round()}%',
                  ),
                  _DetailFact(
                    label: 'Riders',
                    value: incident.riderCount?.toString() ?? 'Not confirmed',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: AppColors.muted),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Registered vehicle details',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'DataFlag API connection pending. No owner name, address or registration record has been requested.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPanel extends StatelessWidget {
  const _CropPanel({
    required this.label,
    required this.url,
    required this.icon,
  });

  final String label;
  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _NetworkEvidence(url: url ?? '', icon: icon),
        ),
      ),
    ],
  );
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 258,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _NetworkEvidence extends StatelessWidget {
  const _NetworkEvidence({required this.url, required this.icon});

  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _ImageFallback(icon: icon);
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ColoredBox(
              color: AppColors.ink,
              child: Center(child: CircularProgressIndicator()),
            ),
      errorBuilder: (context, error, stackTrace) => _ImageFallback(icon: icon),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.ink,
    child: Center(child: Icon(icon, color: AppColors.mutedOnInk, size: 44)),
  );
}

class _EmptyVehicles extends StatelessWidget {
  const _EmptyVehicles();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      child: Column(
        children: [
          Icon(Icons.directions_car_outlined, size: 46, color: AppColors.muted),
          SizedBox(height: 12),
          Text(
            'No detected vehicles',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          SizedBox(height: 5),
          Text(
            'Vehicle OCR records will appear after a video creates incident evidence.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
