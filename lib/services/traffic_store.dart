import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/violation.dart';
import 'traffic_repository.dart';

class TrafficStore extends ChangeNotifier {
  TrafficStore(this.repository);
  final TrafficRepository repository;

  List<ViolationIncident> incidents = [];
  List<ProcessingJob> jobs = [];
  bool loading = false;
  String? error;

  int get pendingCount =>
      incidents.where((item) => item.status == ReviewStatus.pending).length;
  int count(ViolationType type) =>
      incidents.where((item) => item.type == type).length;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        repository.getIncidents(),
        repository.getJobs(),
      ]);
      incidents = values[0] as List<ViolationIncident>;
      jobs = values[1] as List<ProcessingJob>;
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> review(
    ViolationIncident incident,
    ReviewStatus status,
    String note,
  ) async {
    await repository.reviewIncident(incident.id, status, note);
    final index = incidents.indexWhere((item) => item.id == incident.id);
    if (index >= 0) {
      incidents[index] = incident.copyWith(status: status, note: note);
      notifyListeners();
    }
  }

  Future<void> submitVideo({
    required String fileName,
    required String camera,
    Uint8List? bytes,
    String? path,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final job = await repository.submitVideo(
        fileName: fileName,
        camera: camera,
        bytes: bytes,
        path: path,
      );
      jobs = [job, ...jobs.where((item) => item.id != job.id)];
      if (job.status == JobStatus.queued ||
          job.status == JobStatus.processing) {
        unawaited(_pollJob(job.id));
      }
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _pollJob(String jobId) async {
    for (var attempt = 0; attempt < 600; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        jobs = await repository.getJobs();
        notifyListeners();
        final matches = jobs.where((item) => item.id == jobId);
        if (matches.isEmpty || matches.first.status == JobStatus.failed) {
          return;
        }
        if (matches.first.status == JobStatus.completed) {
          incidents = await repository.getIncidents();
          notifyListeners();
          return;
        }
      } catch (exception) {
        error = exception.toString();
        notifyListeners();
      }
    }
  }
}
