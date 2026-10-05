import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/violation.dart';
import '../../models/vehicle_lookup.dart';
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
                _SummaryCard(
                  label: 'Lookup credits',
                  value: '${widget.store.vehicleWallet.balance}',
                  icon: Icons.account_balance_wallet_outlined,
                  color: widget.store.vehicleWallet.balance > 0
                      ? AppColors.success
                      : AppColors.danger,
                  compactValue: true,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _VehicleLookupPanel(store: widget.store),
            const SizedBox(height: 14),
            _DataFlagNotice(wallet: widget.store.vehicleWallet),
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
        builder: (context) =>
            _VehicleDetails(incident: incident, store: widget.store),
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

class _VehicleLookupPanel extends StatefulWidget {
  const _VehicleLookupPanel({
    required this.store,
    this.initialVehicleNumber = '',
  });

  final TrafficStore store;
  final String initialVehicleNumber;

  @override
  State<_VehicleLookupPanel> createState() => _VehicleLookupPanelState();
}

class _VehicleLookupPanelState extends State<_VehicleLookupPanel> {
  late final TextEditingController controller;
  VehicleLookupResult? result;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialVehicleNumber);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.store.vehicleWallet;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.manage_search_rounded,
                    color: AppColors.lime,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manual registration check',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Correct the OCR value before checking DataFlag.',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: '${wallet.balance} CREDITS',
                  color: wallet.balance > 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 600
                      ? double.infinity
                      : 300,
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle registration number',
                      hintText: 'KA01AB1234',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      !wallet.configured ||
                          wallet.balance < wallet.lookupCost ||
                          widget.store.vehicleLookupLoading
                      ? null
                      : _lookup,
                  icon: widget.store.vehicleLookupLoading
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    wallet.configured
                        ? 'Check · ${wallet.lookupCost} credit'
                        : 'API key required',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showLedger,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Credit ledger'),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              _LookupResultPanel(result: result!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _lookup() async {
    final vehicleNumber = controller.text.trim();
    if (vehicleNumber.isEmpty) {
      _message('Enter or correct the vehicle registration number.');
      return;
    }
    try {
      final value = await widget.store.lookupVehicle(vehicleNumber);
      if (!mounted) return;
      setState(() => result = value);
      _message('Vehicle details checked. One credit was deducted.');
      await showDialog<void>(
        context: context,
        builder: (context) => _VehicleRegistryDialog(result: value),
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _showLedger() async {
    try {
      await widget.store.loadVehicleCreditLedger();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _CreditLedgerDialog(
          entries: widget.store.vehicleCreditLedger,
          balance: widget.store.vehicleWallet.balance,
        ),
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _VehicleRegistryDialog extends StatelessWidget {
  const _VehicleRegistryDialog({required this.result});

  final VehicleLookupResult result;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.directions_car_filled_outlined,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Registered vehicle details',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _LookupResultPanel(result: result),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LookupResultPanel extends StatelessWidget {
  const _LookupResultPanel({required this.result});

  final VehicleLookupResult result;

  @override
  Widget build(BuildContext context) {
    final fields = _flattenDetails(result.details);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.success),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${result.vehicleNumber} · DataFlag response',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${result.creditsRemaining} credits left',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (fields.isEmpty)
            const Text(
              'The provider returned no displayable vehicle fields.',
              style: TextStyle(color: AppColors.muted),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final field in fields.take(24))
                  _DetailFact(label: field.$1, value: field.$2),
              ],
            ),
          const SizedBox(height: 10),
          const Text(
            'Authorized use only. Verify provider data against the OCR crop and do not treat it as an automatic enforcement decision.',
            style: TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _CreditLedgerDialog extends StatelessWidget {
  const _CreditLedgerDialog({required this.entries, required this.balance});

  final List<VehicleCreditLedgerEntry> entries;
  final int balance;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Expanded(child: Text('Vehicle lookup ledger')),
        StatusPill(label: '$balance CREDITS', color: AppColors.success),
      ],
    ),
    content: SizedBox(
      width: 560,
      child: entries.isEmpty
          ? const Text('No credit entries recorded.')
          : ListView.separated(
              shrinkWrap: true,
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        (entry.amount >= 0 ? AppColors.success : AppColors.blue)
                            .withValues(alpha: .1),
                    child: Icon(
                      entry.amount >= 0 ? Icons.add : Icons.remove,
                      color: entry.amount >= 0
                          ? AppColors.success
                          : AppColors.blue,
                    ),
                  ),
                  title: Text(
                    entry.vehicleNumber ?? entry.reason,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${entry.reason} · ${_formatDate(entry.createdAt)}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        entry.amount > 0
                            ? '+${entry.amount}'
                            : '${entry.amount}',
                        style: TextStyle(
                          color: entry.amount >= 0
                              ? AppColors.success
                              : AppColors.blue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Balance ${entry.balanceAfter}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

List<(String, String)> _flattenDetails(Map<String, dynamic> details) {
  final fields = <(String, String)>[];

  void visit(String prefix, Object? value) {
    if (value == null || value == '') return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = prefix.isEmpty ? '${entry.key}' : '$prefix ${entry.key}';
        visit(key, entry.value);
      }
      return;
    }
    if (value is List) {
      if (value.isNotEmpty) fields.add((_titleCase(prefix), value.join(', ')));
      return;
    }
    fields.add((_titleCase(prefix), '$value'));
  }

  visit('', details);
  return fields;
}

String _titleCase(String value) {
  final spaced = value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .trim();
  return spaced
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _friendlyError(Object error) {
  final value = error.toString();
  if (value.contains('503')) return 'DataFlag API key is not configured yet.';
  if (value.contains('402')) return 'No vehicle lookup credits remain.';
  if (value.contains('404')) return 'DataFlag found no details for this registration. Check the plate number and try again.';
  if (value.contains('422')) return 'Check the vehicle registration number.';
  return 'Vehicle lookup failed. No credit was deducted.';
}

class _DataFlagNotice extends StatelessWidget {
  const _DataFlagNotice({required this.wallet});

  final VehicleCreditWallet wallet;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          wallet.configured
              ? Icons.verified_user_outlined
              : Icons.cloud_off_outlined,
          color: AppColors.warning,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wallet.configured
                    ? 'DataFlag lookup is available'
                    : 'DataFlag lookup is prepared, not connected',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                wallet.configured
                    ? 'Each successful registration check costs ${wallet.lookupCost} credit. Confirm the OCR value and use registry data only for an authorized purpose.'
                    : 'Add the DataFlag key to the Azure backend to enable checks. Failed or disabled checks do not deduct credits.',
                style: const TextStyle(
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
  const _VehicleDetails({required this.incident, required this.store});

  final ViolationIncident incident;
  final TrafficStore store;

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
              _VehicleLookupPanel(
                store: store,
                initialVehicleNumber: _hasReadablePlate(incident)
                    ? incident.plate
                    : '',
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
