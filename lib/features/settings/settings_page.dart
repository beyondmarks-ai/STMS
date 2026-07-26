import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../services/traffic_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final TrafficStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double persistence = 2.5;
  double confidence = .80;
  bool blurThumbnails = true;

  @override
  Widget build(BuildContext context) => ListView(
    padding: pagePadding(context),
    children: [
      const PageHeader(
        eyebrow: 'Calibrated decisions',
        title: 'System settings',
        description:
            'Demo-safe defaults for evidence, privacy, and detection rules.',
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? MediaQuery.sizeOf(context).width - 36
                : 520,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detection thresholds',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SliderSetting(
                      label: 'Minimum confidence',
                      valueLabel: '${(confidence * 100).round()}%',
                      value: confidence,
                      min: .5,
                      max: .99,
                      onChanged: (value) => setState(() => confidence = value),
                    ),
                    _SliderSetting(
                      label: 'Temporal persistence',
                      valueLabel: '${persistence.toStringAsFixed(1)} sec',
                      value: persistence,
                      min: .5,
                      max: 8,
                      onChanged: (value) => setState(() => persistence = value),
                    ),
                    const Divider(height: 30),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Blur faces and plates in thumbnails',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Evidence is revealed only inside authenticated review.',
                      ),
                      value: blurThumbnails,
                      onChanged: (value) =>
                          setState(() => blurThumbnails = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? MediaQuery.sizeOf(context).width - 36
                : 360,
            child: Card(
              child: const Padding(
                padding: EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Azure connection',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 18),
                    _ConnectionRow(
                      name: 'Azure OpenAI vision',
                      status: 'Ready',
                    ),
                    _ConnectionRow(
                      name: 'Local ONNX inference',
                      status: 'Ready',
                    ),
                    _ConnectionRow(name: 'Azure Face crop', status: 'Ready'),
                    _ConnectionRow(name: 'Local plate OCR', status: 'Ready'),
                    SizedBox(height: 15),
                    Text(
                      'Hybrid analysis is active: ONNX tracks the video and Azure verifies selected evidence frames. Use API_BASE_URL with port 8001 on a physical device.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(valueLabel, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.name, required this.status});
  final String name;
  final String status;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(name)),
        Text(
          status,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}
