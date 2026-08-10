import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_header.dart';
import '../../models/violation.dart';
import '../../services/traffic_store.dart';
import 'live_camera_card.dart';

class JobsPage extends StatefulWidget {
  const JobsPage({super.key, required this.store});
  final TrafficStore store;

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  final cameraController = TextEditingController(
    text: 'Demo Junction · Northbound',
  );
  PlatformFile? selectedFile;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => ListView(
      padding: pagePadding(context),
      children: [
        const PageHeader(
          eyebrow: 'Video sources',
          title: 'Camera & processing jobs',
          description:
              'Monitor a college IP camera or upload recorded traffic footage for review.',
        ),
        const SizedBox(height: 24),
        const LiveCameraCard(),
        const SizedBox(height: 18),
        const Text(
          'Recorded video upload',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 650;
                final picker = InkWell(
                  onTap: _pickVideo,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_upload_outlined,
                            size: 34,
                            color: AppColors.muted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            selectedFile?.name ??
                                'Choose an MP4, MOV, or AVI file',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedFile == null
                                ? 'Recorded clips stay private'
                                : _fileSize(selectedFile!.size),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: cameraController,
                      decoration: const InputDecoration(
                        labelText: 'Camera / junction name',
                        prefixIcon: Icon(Icons.videocam_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppColors.ink,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: selectedFile == null || widget.store.loading
                          ? null
                          : _submit,
                      icon: widget.store.loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        widget.store.loading ? 'Submitting…' : 'Analyse video',
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Every generated incident requires human review.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 10),
                    ),
                  ],
                );
                if (narrow) {
                  return Column(
                    children: [picker, const SizedBox(height: 16), details],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: picker),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: details),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Recent jobs',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (widget.store.jobs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('No video jobs yet.')),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final job in widget.store.jobs) _JobTile(job: job),
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'avi', 'mkv'],
      withData: false,
    );
    if (result != null && mounted) {
      setState(() => selectedFile = result.files.single);
    }
  }

  Future<void> _submit() async {
    final file = selectedFile!;
    try {
      await widget.store.submitVideo(
        fileName: file.name,
        camera: cameraController.text.trim(),
        bytes: file.bytes,
        path: file.path,
      );
      if (!mounted) {
        return;
      }
      setState(() => selectedFile = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video submitted. Evidence will appear in the incident queue.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.store.error ?? 'Upload failed')),
        );
      }
    }
  }

  String _fileSize(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final ProcessingJob job;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final color = switch (job.status) {
      JobStatus.completed => AppColors.success,
      JobStatus.failed => AppColors.danger,
      JobStatus.processing => AppColors.blue,
      JobStatus.queued => AppColors.warning,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.movie_outlined, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  job.camera,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                if (compact && job.status == JobStatus.processing) ...[
                  const SizedBox(height: 9),
                  LinearProgressIndicator(value: job.progress),
                  const SizedBox(height: 3),
                  Text(
                    '${(job.progress * 100).round()}% analysed',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!compact && job.status == JobStatus.processing)
            SizedBox(
              width: 110,
              child: LinearProgressIndicator(value: job.progress),
            ),
          const SizedBox(width: 14),
          if (!compact && job.incidentCount > 0)
            Text(
              '${job.incidentCount} incidents',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          SizedBox(width: compact ? 8 : 14),
          StatusPill(label: job.status.label, color: color),
        ],
      ),
    );
  }
}
