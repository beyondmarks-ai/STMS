import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/live_camera.dart';
import '../../services/live_camera_service.dart';

class LiveCameraCard extends StatefulWidget {
  const LiveCameraCard({super.key});

  @override
  State<LiveCameraCard> createState() => _LiveCameraCardState();
}

class _LiveCameraCardState extends State<LiveCameraCard> {
  final gatewayController = TextEditingController();
  final tokenController = TextEditingController();
  final cameraController = TextEditingController(text: 'College Main Gate');
  final rtspController = TextEditingController();
  final service = const LiveCameraService();

  RtspProbeResult? probe;
  LiveCameraStatus? camera;
  Timer? pollingTimer;
  bool busy = false;
  bool hideRtsp = true;
  bool hideToken = true;

  @override
  void dispose() {
    pollingTimer?.cancel();
    gatewayController.dispose();
    tokenController.dispose();
    cameraController.dispose();
    rtspController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          color: AppColors.ink,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.lime.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sensors, color: AppColors.lime),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live IP camera',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'RTSP stays on the college LAN · evidence uploads over HTTPS',
                      style: TextStyle(
                        color: AppColors.mutedOnInk,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (camera != null)
                StatusPill(
                  label: camera!.state.toUpperCase(),
                  color: _stateColor(camera!.state),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.computer_outlined, color: AppColors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Run the STMS edge connector on a computer connected to the same network as the phone and camera. Never expose RTSP port 554 to the internet.',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 700;
                  final gateway = TextField(
                    controller: gatewayController,
                    enabled: camera?.active != true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Edge gateway URL',
                      hintText: 'http://192.168.1.10:8090',
                      prefixIcon: Icon(Icons.router_outlined),
                    ),
                  );
                  final token = TextField(
                    controller: tokenController,
                    enabled: camera?.active != true,
                    obscureText: hideToken,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Gateway pairing token',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hideToken = !hideToken),
                        icon: Icon(
                          hideToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  );
                  if (narrow) {
                    return Column(
                      children: [gateway, const SizedBox(height: 11), token],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: gateway),
                      const SizedBox(width: 12),
                      Expanded(child: token),
                    ],
                  );
                },
              ),
              const SizedBox(height: 11),
              TextField(
                controller: cameraController,
                enabled: camera?.active != true,
                decoration: const InputDecoration(
                  labelText: 'Camera / junction name',
                  prefixIcon: Icon(Icons.videocam_outlined),
                ),
              ),
              const SizedBox(height: 11),
              TextField(
                controller: rtspController,
                enabled: camera?.active != true,
                obscureText: hideRtsp,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'College camera RTSP URL',
                  hintText: 'rtsp://user:password@camera-ip:554/stream',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hideRtsp = !hideRtsp),
                    icon: Icon(
                      hideRtsp
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || camera?.active == true ? null : _test,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Test connection'),
                  ),
                  FilledButton.icon(
                    onPressed: busy || camera?.active == true ? null : _start,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start monitoring'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || camera?.active != true ? null : _stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ],
              ),
              if (probe != null || camera != null) ...[
                const SizedBox(height: 15),
                _CameraFeedback(probe: probe, camera: camera),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _test() async {
    if (!_validate()) return;
    await _perform(() async {
      final health = await service.health(gatewayController.text);
      if (health['configured'] != true) {
        throw const LiveCameraException(
          'The edge connector pairing token is not configured.',
        );
      }
      if (health['ffmpeg'] != true) {
        throw const LiveCameraException(
          'FFmpeg is unavailable on the edge computer.',
        );
      }
      final value = await service.testCamera(
        gatewayUrl: gatewayController.text,
        token: tokenController.text,
        cameraName: cameraController.text,
        rtspUrl: rtspController.text,
      );
      if (mounted) setState(() => probe = value);
      _message('${value.message} (${value.width}×${value.height}).');
    });
  }

  Future<void> _start() async {
    if (!_validate()) return;
    await _perform(() async {
      final value = await service.startCamera(
        gatewayUrl: gatewayController.text,
        token: tokenController.text,
        cameraName: cameraController.text,
        rtspUrl: rtspController.text,
      );
      if (!mounted) return;
      setState(() => camera = value);
      pollingTimer?.cancel();
      pollingTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshStatus()),
      );
      _message(
        'Live monitoring started. The connector will upload evidence clips.',
      );
    });
  }

  Future<void> _stop() async {
    final value = camera;
    if (value == null) return;
    await _perform(() async {
      final stopped = await service.stopCamera(
        gatewayUrl: gatewayController.text,
        token: tokenController.text,
        cameraId: value.id,
      );
      pollingTimer?.cancel();
      if (mounted) setState(() => camera = stopped);
      _message('Camera monitoring is stopping safely.');
    });
  }

  Future<void> _refreshStatus() async {
    final value = camera;
    if (value == null || !value.active) return;
    try {
      final updated = await service.getCamera(
        gatewayUrl: gatewayController.text,
        token: tokenController.text,
        cameraId: value.id,
      );
      if (!mounted) return;
      setState(() => camera = updated);
      if (!updated.active) pollingTimer?.cancel();
    } catch (_) {
      // A transient status failure must not stop the edge worker.
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    setState(() => busy = true);
    try {
      await operation();
    } on TimeoutException {
      _message(
        'Connection timed out. Confirm the phone, gateway and camera are on the same network.',
      );
    } on FormatException catch (error) {
      _message(error.message);
    } on LiveCameraException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(
        'Edge connector is unreachable. Start it on the college gateway and check the LAN IP/firewall.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool _validate() {
    if (gatewayController.text.trim().isEmpty ||
        tokenController.text.trim().isEmpty ||
        cameraController.text.trim().length < 2 ||
        rtspController.text.trim().isEmpty) {
      _message('Complete the gateway, token, camera name and RTSP URL.');
      return false;
    }
    final rtsp = Uri.tryParse(rtspController.text.trim());
    if (rtsp == null ||
        !{'rtsp', 'rtsps'}.contains(rtsp.scheme.toLowerCase()) ||
        rtsp.host.isEmpty) {
      _message('Enter a valid rtsp:// or rtsps:// camera URL.');
      return false;
    }
    return true;
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _CameraFeedback extends StatelessWidget {
  const _CameraFeedback({required this.probe, required this.camera});

  final RtspProbeResult? probe;
  final LiveCameraStatus? camera;

  @override
  Widget build(BuildContext context) {
    final value = camera;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _stateColor(value?.state ?? 'reachable').withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _stateColor(value?.state ?? 'reachable').withValues(alpha: .3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value == null ? 'Camera connection verified' : value.cameraName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            value?.endpoint ?? probe?.endpoint ?? '',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          if (probe != null && value == null) ...[
            const SizedBox(height: 4),
            Text(
              '${probe!.codec?.toUpperCase() ?? 'VIDEO'} · ${probe!.width}×${probe!.height}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
          if (value != null) ...[
            const SizedBox(height: 6),
            Text(
              value.lastJobId == null
                  ? 'State: ${value.state}. Waiting for the first evidence upload.'
                  : 'State: ${value.state} · Last Azure job: ${value.lastJobId}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            if (value.lastError != null) ...[
              const SizedBox(height: 4),
              Text(
                value.lastError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 11),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

Color _stateColor(String state) => switch (state) {
  'capturing' ||
  'uploading' ||
  'monitoring' ||
  'reachable' => AppColors.success,
  'starting' || 'reconnecting' || 'stopping' => AppColors.warning,
  'stopped' => AppColors.muted,
  _ => AppColors.blue,
};
