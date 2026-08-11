import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/violation.dart';
import '../models/vehicle_lookup.dart';
import '../models/penalty.dart';
import 'traffic_repository.dart';

class TrafficStore extends ChangeNotifier {
  TrafficStore(this.repository);
  final TrafficRepository repository;

  List<ViolationIncident> incidents = [];
  List<ProcessingJob> jobs = [];
  List<PenaltyRecord> penalties = [];
  List<VehiclePenaltySummary> vehiclePenaltySummaries = [];
  VehicleCreditWallet vehicleWallet = const VehicleCreditWallet(
    balance: 100,
    initialCredits: 100,
    lookupCost: 1,
    provider: 'DataFlag',
    configured: false,
  );
  List<VehicleCreditLedgerEntry> vehicleCreditLedger = [];
  bool loading = false;
  bool vehicleLookupLoading = false;
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
      await _loadPenalties();
      try {
        vehicleWallet = await repository.getVehicleCreditWallet();
      } catch (_) {
        // Vehicle lookup is optional and must not block incident operations.
      }
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
      await _loadPenalties();
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

  Future<VehicleLookupResult> lookupVehicle(String vehicleNumber) async {
    vehicleLookupLoading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.lookupVehicle(vehicleNumber);
      vehicleWallet = vehicleWallet.copyWith(balance: result.creditsRemaining);
      try {
        vehicleCreditLedger = await repository.getVehicleCreditLedger();
      } catch (_) {
        // The successful lookup result is still usable if ledger refresh fails.
      }
      return result;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      vehicleLookupLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadVehicleCreditLedger() async {
    vehicleCreditLedger = await repository.getVehicleCreditLedger();
    vehicleWallet = await repository.getVehicleCreditWallet();
    notifyListeners();
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
          await _loadPenalties();
          notifyListeners();
          return;
        }
      } catch (exception) {
        error = exception.toString();
        notifyListeners();
      }
    }
  }

  Future<void> _loadPenalties() async {
    try {
      final values = await Future.wait([
        repository.getPenalties(),
        repository.getVehiclePenaltySummaries(),
      ]);
      penalties = values[0] as List<PenaltyRecord>;
      vehiclePenaltySummaries = values[1] as List<VehiclePenaltySummary>;
    } catch (_) {
      // Penalties remain isolated so an older backend cannot block operations.
    }
  }
}
