import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../services/traffic_store.dart';

class OperationsPage extends StatefulWidget {
  const OperationsPage({super.key, required this.store});
  final TrafficStore store;

  @override
  State<OperationsPage> createState() => _OperationsPageState();
}

class _OperationsPageState extends State<OperationsPage> {
  late Future<List<Map<String, dynamic>>> hotspots;
  late Future<List<Map<String, dynamic>>> vip;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    hotspots = widget.store.repository.getHotspots();
    vip = widget.store.repository.getVipVehicles();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: pagePadding(context),
    children: [
      PageHeader(
        eyebrow: 'Automation lab · sandbox',
        title: 'Traffic operations',
        description: 'Review hotspots, manage VIP vehicles, and test proof notifications and UPI payments safely.',
        action: IconButton.filledTonal(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
      ),
      const SizedBox(height: 20),
      _section('Predictive violation hotspots', Icons.local_fire_department_outlined, FutureBuilder<List<Map<String, dynamic>>>(
        future: hotspots,
        builder: (context, snapshot) => snapshot.hasData
            ? Column(children: [for (final item in snapshot.data!) ListTile(title: Text('${item['camera']}'), subtitle: Text('${item['topViolation']} · ${item['violationCount']} violations'), trailing: Text('${item['riskScore']}% risk'))])
            : const LinearProgressIndicator(),
      )),
      _section('VIP vehicle whitelist', Icons.verified_user_outlined, Column(children: [
        FutureBuilder<List<Map<String, dynamic>>>(future: vip, builder: (context, snapshot) => snapshot.hasData ? Column(children: [for (final item in snapshot.data!) ListTile(title: Text('${item['plate']}'), subtitle: Text('${item['owner']} · ${item['reason']}'), trailing: const Icon(Icons.check_circle, color: AppColors.success))]) : const LinearProgressIndicator()),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _addVip, icon: const Icon(Icons.add), label: const Text('Add vehicle'))),
      ])),
      _section('Chalan and payment test tools', Icons.receipt_long_outlined, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WhatsApp/SMS remains a preview until an operator approves it. UPI uses sandbox responses only.'),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: [FilledButton.icon(onPressed: widget.store.incidents.isEmpty ? null : _preview, icon: const Icon(Icons.message_outlined), label: const Text('Preview chalan')), FilledButton.icon(onPressed: widget.store.penalties.isEmpty ? null : _pay, icon: const Icon(Icons.account_balance_wallet_outlined), label: const Text('Test UPI sandbox'))]),
      ])),
    ],
  );

  Widget _section(String title, IconData icon, Widget child) => Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: AppColors.blue), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))]), const Divider(height: 24), child])));

  Future<void> _addVip() async {
    final plate = TextEditingController();
    final owner = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Add VIP vehicle'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: plate, decoration: const InputDecoration(labelText: 'Plate number')), TextField(controller: owner, decoration: const InputDecoration(labelText: 'Owner')), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok == true && plate.text.isNotEmpty && mounted) { await widget.store.repository.addVipVehicle(plate: plate.text, owner: owner.text, reason: reason.text); setState(_reload); }
  }

  Future<void> _preview() async { final result = await widget.store.repository.previewNotification(incidentId: widget.store.incidents.first.id, channel: 'whatsapp', recipient: 'sandbox-recipient'); if (mounted) _show(result); }
  Future<void> _pay() async { final item = widget.store.penalties.first; final result = await widget.store.repository.sandboxPayment(penaltyId: item.id, amount: item.amount); if (mounted) _show(result); }
  void _show(Map<String, dynamic> result) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result['status'] ?? 'success'} · sandbox=${result['sandbox']}')));
}
