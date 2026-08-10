import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/violation.dart';
import '../models/vehicle_lookup.dart';

abstract interface class TrafficRepository {
  Future<List<ViolationIncident>> getIncidents();
  Future<List<ProcessingJob>> getJobs();
  Future<VehicleCreditWallet> getVehicleCreditWallet();
  Future<List<VehicleCreditLedgerEntry>> getVehicleCreditLedger();
  Future<VehicleLookupResult> lookupVehicle(String vehicleNumber);
  Future<void> reviewIncident(String id, ReviewStatus status, String note);
  Future<ProcessingJob> submitVideo({
    required String fileName,
    required String camera,
    Uint8List? bytes,
    String? path,
  });
}

class ApiTrafficRepository implements TrafficRepository {
  ApiTrafficRepository(String baseUrl)
    : baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
  final String baseUrl;

  @override
  Future<List<ViolationIncident>> getIncidents() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/incidents'));
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map((item) => _incidentFromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ProcessingJob>> getJobs() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/jobs'));
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map((item) => ProcessingJob.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<VehicleCreditWallet> getVehicleCreditWallet() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/vehicle-lookups/wallet'),
    );
    _ensureSuccess(response);
    return VehicleCreditWallet.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<VehicleCreditLedgerEntry>> getVehicleCreditLedger() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/vehicle-lookups/ledger'),
    );
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map(
          (item) =>
              VehicleCreditLedgerEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<VehicleLookupResult> lookupVehicle(String vehicleNumber) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/vehicle-lookups'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'vehicleNumber': vehicleNumber}),
    );
    _ensureSuccess(response);
    return VehicleLookupResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> reviewIncident(
    String id,
    ReviewStatus status,
    String note,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/v1/incidents/$id/review'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'status': status.name, 'note': note}),
    );
    _ensureSuccess(response);
  }

  @override
  Future<ProcessingJob> submitVideo({
    required String fileName,
    required String camera,
    Uint8List? bytes,
    String? path,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/jobs'),
    )..fields['camera'] = camera;
    if (bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('video', bytes, filename: fileName),
      );
    } else if (path != null) {
      request.files.add(await http.MultipartFile.fromPath('video', path));
    } else {
      throw ArgumentError('Video bytes or path must be provided.');
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response);
    return ProcessingJob.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Traffic API ${response.statusCode}: ${response.body}');
    }
  }

  ViolationIncident _incidentFromJson(Map<String, dynamic> source) {
    final json = Map<String, dynamic>.of(source);
    for (final key in ['evidenceUrl', 'plateCropUrl', 'faceCropUrl']) {
      final value = json[key];
      if (value is String && value.startsWith('/')) {
        json[key] = '$baseUrl$value';
      }
    }
    return ViolationIncident.fromJson(json);
  }
}

class DemoTrafficRepository implements TrafficRepository {
  DemoTrafficRepository() {
    final now = DateTime.now();
    _incidents.addAll([
      ViolationIncident(
        id: 'INC-1048',
        type: ViolationType.noHelmet,
        status: ReviewStatus.pending,
        plate: 'KA 01 MJ 4821',
        camera: 'MG Road · Northbound',
        confidence: .94,
        detectedAt: now.subtract(const Duration(minutes: 4)),
        explanation: 'Rider tracked without a helmet for 2.8 seconds.',
        evidenceUrl: '',
      ),
      ViolationIncident(
        id: 'INC-1047',
        type: ViolationType.tripleRiding,
        status: ReviewStatus.pending,
        plate: 'TN 09 BK 7712',
        camera: 'Central Junction · East',
        confidence: .91,
        detectedAt: now.subtract(const Duration(minutes: 18)),
        explanation: 'Three riders remained associated with one motorcycle.',
        evidenceUrl: '',
      ),
      ViolationIncident(
        id: 'INC-1046',
        type: ViolationType.wrongSide,
        status: ReviewStatus.approved,
        plate: 'KL 07 CP 2230',
        camera: 'Station Road · Gate 2',
        confidence: .88,
        detectedAt: now.subtract(const Duration(hours: 1, minutes: 12)),
        explanation: 'Vehicle track opposed the calibrated lane direction.',
        evidenceUrl: '',
      ),
      ViolationIncident(
        id: 'INC-1045',
        type: ViolationType.ambulanceObstruction,
        status: ReviewStatus.needsReview,
        plate: 'KA 05 NC 9090',
        camera: 'Hospital Corridor · West',
        confidence: .82,
        detectedAt: now.subtract(const Duration(hours: 2, minutes: 5)),
        explanation:
            'Vehicle occupied the ambulance clearance corridor for 7.4 seconds.',
        evidenceUrl: '',
      ),
    ]);
    _jobs.add(
      ProcessingJob(
        id: 'JOB-241',
        fileName: 'junction_morning.mp4',
        camera: 'MG Road · Northbound',
        status: JobStatus.completed,
        progress: 1,
        createdAt: now.subtract(const Duration(hours: 3)),
        incidentCount: 4,
      ),
    );
  }

  final List<ViolationIncident> _incidents = [];
  final List<ProcessingJob> _jobs = [];

  @override
  Future<VehicleCreditWallet> getVehicleCreditWallet() async =>
      const VehicleCreditWallet(
        balance: 100,
        initialCredits: 100,
        lookupCost: 1,
        provider: 'DataFlag',
        configured: false,
      );

  @override
  Future<List<VehicleCreditLedgerEntry>> getVehicleCreditLedger() async => [
    VehicleCreditLedgerEntry(
      id: 'LED-INITIAL',
      amount: 100,
      balanceAfter: 100,
      reason: 'Initial pilot allocation',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<VehicleLookupResult> lookupVehicle(String vehicleNumber) =>
      throw StateError('DataFlag lookup is not configured');

  @override
  Future<List<ViolationIncident>> getIncidents() async => List.of(_incidents);

  @override
  Future<List<ProcessingJob>> getJobs() async => List.of(_jobs);

  @override
  Future<void> reviewIncident(
    String id,
    ReviewStatus status,
    String note,
  ) async {
    final index = _incidents.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _incidents[index] = _incidents[index].copyWith(
        status: status,
        note: note,
      );
    }
  }

  @override
  Future<ProcessingJob> submitVideo({
    required String fileName,
    required String camera,
    Uint8List? bytes,
    String? path,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final job = ProcessingJob(
      id: 'JOB-${242 + _jobs.length}',
      fileName: fileName,
      camera: camera,
      status: JobStatus.completed,
      progress: 1,
      createdAt: DateTime.now(),
      incidentCount: 2,
    );
    _jobs.insert(0, job);
    return job;
  }
}
