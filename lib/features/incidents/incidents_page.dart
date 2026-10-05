import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/violation.dart';
import '../../services/traffic_store.dart';

class IncidentsPage extends StatefulWidget {
  const IncidentsPage({super.key, required this.store});
  final TrafficStore store;

  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  ReviewStatus? filter;
  String query = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final incidents = widget.store.incidents.where((item) {
        final matchesFilter = filter == null || item.status == filter;
        final needle = query.toLowerCase();
        return matchesFilter &&
            (item.plate.toLowerCase().contains(needle) ||
                item.type.label.toLowerCase().contains(needle) ||
                item.camera.toLowerCase().contains(needle));
      }).toList();
      return ListView(
        padding: pagePadding(context),
        children: [
          const PageHeader(
            eyebrow: 'Evidence queue',
            title: 'Incident review',
            description:
                'Confirm or reject every AI suggestion before it leaves the system.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 600
                    ? MediaQuery.sizeOf(context).width - 36
                    : 300,
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search plate, camera, violation',
                  ),
                ),
              ),
              DropdownButton<ReviewStatus?>(
                value: filter,
                borderRadius: BorderRadius.circular(12),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  ...ReviewStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => filter = value),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (incidents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('No incidents match these filters.')),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final incident in incidents)
                    _IncidentTile(
                      incident: incident,
                      onTap: () => _openIncident(context, incident),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Future<void> _openIncident(
    BuildContext context,
    ViolationIncident incident,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _IncidentDialog(store: widget.store, incident: incident),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({required this.incident, required this.onTap});
  final ViolationIncident incident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: compact ? 50 : 62,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.videocam_outlined, color: AppColors.lime),
            ),
            const SizedBox(width: 15),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    incident.type.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    incident.id,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if (compact) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${incident.plate} · ${incident.camera}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!compact)
              Expanded(
                flex: 2,
                child: Text(
                  incident.plate,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
              ),
            if (!compact)
              Expanded(
                flex: 3,
                child: Text(
                  incident.camera,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            if (!compact)
              StatusPill(
                label: '${(incident.confidence * 100).round()}%',
                color: AppColors.blue,
              ),
            SizedBox(width: compact ? 6 : 10),
            StatusPill(
              label: incident.status.label,
              color: _statusColor(incident.status),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(ReviewStatus status) => switch (status) {
  ReviewStatus.pending => AppColors.warning,
  ReviewStatus.approved => AppColors.success,
  ReviewStatus.rejected => AppColors.danger,
  ReviewStatus.needsReview => AppColors.blue,
};

class _IncidentDialog extends StatefulWidget {
  const _IncidentDialog({required this.store, required this.incident});
  final TrafficStore store;
  final ViolationIncident incident;

  @override
  State<_IncidentDialog> createState() => _IncidentDialogState();
}

class _IncidentDialogState extends State<_IncidentDialog> {
  final noteController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
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
                        Text(
                          widget.incident.type.label,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.incident.id} · ${widget.incident.camera}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AspectRatio(
                aspectRatio: compact ? 4 / 3 : 16 / 7,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.incident.evidenceUrl.isNotEmpty)
                        Image.network(
                          widget.incident.evidenceUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const _EvidenceFallback(),
                        )
                      else
                        const _EvidenceFallback(),
                      Positioned(
                        left: 18,
                        top: 18,
                        child: StatusPill(
                          label: 'EVIDENCE FRAME',
                          color: AppColors.lime,
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 20,
                        child: Container(height: 2, color: Colors.white24),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _EvidenceFact(
                    label: 'Plate OCR',
                    value: widget.incident.plate,
                    icon: Icons.pin_outlined,
                  ),
                  _EvidenceFact(
                    label: 'AI confidence',
                    value: '${(widget.incident.confidence * 100).round()}%',
                    icon: Icons.analytics_outlined,
                  ),
                  _EvidenceFact(
                    label: 'Review state',
                    value: widget.incident.status.label,
                    icon: Icons.fact_check_outlined,
                  ),
                  if (widget.incident.riderCount != null)
                    _EvidenceFact(
                      label: 'Confirmed riders',
                      value: '${widget.incident.riderCount}',
                      icon: Icons.groups_2_outlined,
                    ),
                  if (widget.incident.vehicleType != null ||
                      widget.incident.vehicleMake != null ||
                      widget.incident.vehicleModel != null)
                    _EvidenceFact(
                      label: 'Vehicle (estimated)',
                      value: [
                        widget.incident.vehicleMake,
                        widget.incident.vehicleModel,
                        widget.incident.vehicleType,
                      ].whereType<String>().join(' · '),
                      icon: Icons.two_wheeler_outlined,
                    ),
                  if (widget.incident.vehicleColor != null)
                    _EvidenceFact(
                      label: 'Colour (estimated)',
                      value: widget.incident.vehicleColor!,
                      icon: Icons.palette_outlined,
                    ),
                ],
              ),
              if (widget.incident.plateCropUrl != null ||
                  widget.incident.faceCropUrl != null) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (widget.incident.plateCropUrl != null)
                      _EvidenceThumbnail(
                        label: 'Plate crop',
                        url: widget.incident.plateCropUrl!,
                      ),
                    if (widget.incident.faceCropUrl != null)
                      _EvidenceThumbnail(
                        label: 'Rider face crop',
                        url: widget.incident.faceCropUrl!,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (widget.incident.type == ViolationType.tamperedPlate)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.report_gmailerrorred_outlined, color: AppColors.warning),
                      SizedBox(width: 10),
                      Expanded(child: Text('Suspicious or tampered plate alert: OCR confidence is below 75%. Verify the plate crop before approving a challan.', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              if (widget.incident.type == ViolationType.tamperedPlate)
                const SizedBox(height: 18),
              const Text(
                'Why this was flagged',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text(
                widget.incident.explanation,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
              if (widget.incident.azureDescription != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Azure visual assessment',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.incident.azureDescription!,
                  style: const TextStyle(color: AppColors.muted, height: 1.5),
                ),
                if (widget.incident.enrichmentUncertainties.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Uncertainty: ${widget.incident.enrichmentUncertainties.join(' · ')}',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Operator note',
                  hintText: 'Describe the reason for your decision',
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () => _review(ReviewStatus.rejected),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                  OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () => _review(ReviewStatus.needsReview),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Needs review'),
                  ),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () => _review(ReviewStatus.approved),
                    icon: const Icon(Icons.check),
                    label: Text(saving ? 'Saving…' : 'Approve'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _review(ReviewStatus status) async {
    setState(() => saving = true);
    await widget.store.review(
      widget.incident,
      status,
      noteController.text.trim(),
    );
    if (mounted) Navigator.pop(context);
  }
}

class _EvidenceFact extends StatelessWidget {
  const _EvidenceFact({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 220,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EvidenceThumbnail extends StatelessWidget {
  const _EvidenceThumbnail({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 110,
            width: 180,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const _EvidenceFallback(),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EvidenceFallback extends StatelessWidget {
  const _EvidenceFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.ink,
    child: Center(
      child: Icon(Icons.traffic_rounded, color: AppColors.mutedOnInk, size: 54),
    ),
  );
}
