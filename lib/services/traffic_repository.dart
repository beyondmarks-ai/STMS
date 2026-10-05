import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/violation.dart';
import '../models/vehicle_lookup.dart';
import '../models/penalty.dart';

abstract interface class TrafficRepository {
  Future<List<ViolationIncident>> getIncidents();
  Future<List<ProcessingJob>> getJobs();
  Future<List<PenaltyRecord>> getPenalties();
  Future<List<VehiclePenaltySummary>> getVehiclePenaltySummaries();
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
  Future<List<Map<String, dynamic>>> getHotspots();
  Future<List<Map<String, dynamic>>> getVipVehicles();
  Future<Map<String, dynamic>> addVipVehicle({required String plate, required String owner, required String reason});
  Future<Map<String, dynamic>> previewNotification({required String incidentId, required String channel, required String recipient});
  Future<Map<String, dynamic>> sandboxPayment({required String penaltyId, required int amount});
}

class ApiTrafficRepository implements TrafficRepository {
  ApiTrafficRepository(String baseUrl)
    : baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
  final String baseUrl;

  Future<Map<String, dynamic>> _json(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = method == 'GET'
        ? await http.get(uri)
        : await http.post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode(body));
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> getHotspots() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/operations/hotspots'));
    _ensureSuccess(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> getVipVehicles() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/operations/vip'));
    _ensureSuccess(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> addVipVehicle({required String plate, required String owner, required String reason}) =>
      _json('POST', '/api/v1/operations/vip', {'plate': plate, 'owner': owner, 'reason': reason});

  @override
  Future<Map<String, dynamic>> previewNotification({required String incidentId, required String channel, required String recipient}) =>
      _json('POST', '/api/v1/operations/notifications/preview', {'incidentId': incidentId, 'channel': channel, 'recipient': recipient});

  @override
  Future<Map<String, dynamic>> sandboxPayment({required String penaltyId, required int amount}) =>
      _json('POST', '/api/v1/operations/payments/upi-sandbox', {'penaltyId': penaltyId, 'amount': amount});

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
  Future<List<PenaltyRecord>> getPenalties() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/penalties'));
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map((item) => PenaltyRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<VehiclePenaltySummary>> getVehiclePenaltySummaries() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/penalties/vehicles'),
    );
    _ensureSuccess(response);
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map(
          (item) =>
              VehiclePenaltySummary.fromJson(item as Map<String, dynamic>),
        )
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

  List<PenaltyRecord> get _demoPenalties => [
    PenaltyRecord(
      id: 'PEN-INC-1048',
      incidentId: 'INC-1048',
      plate: 'KA 01 MJ 4821',
      violationType: ViolationType.noHelmet,
      violationLabel: 'Riding without a helmet',
      amount: 1000,
      currency: 'INR',
      status: PenaltyStatus.pending,
      camera: 'MG Road · Northbound',
      detectedAt: _incidents.first.detectedAt,
    ),
    PenaltyRecord(
      id: 'PEN-INC-1046',
      incidentId: 'INC-1046',
      plate: 'KL 07 CP 2230',
      violationType: ViolationType.wrongSide,
      violationLabel: 'Driving on the wrong side',
      amount: 500,
      currency: 'INR',
      status: PenaltyStatus.confirmed,
      camera: 'Station Road · Gate 2',
      detectedAt: _incidents[2].detectedAt,
    ),
  ];

  @override
  Future<List<PenaltyRecord>> getPenalties() async => _demoPenalties;

  @override
  Future<List<VehiclePenaltySummary>> getVehiclePenaltySummaries() async =>
      _demoPenalties
          .map(
            (item) => VehiclePenaltySummary(
              plate: item.plate,
              penaltyCount: 1,
              pendingCount: item.status == PenaltyStatus.pending ? 1 : 0,
              confirmedCount: item.status == PenaltyStatus.confirmed ? 1 : 0,
              totalAmount: item.amount,
              confirmedAmount: item.status == PenaltyStatus.confirmed
                  ? item.amount
                  : 0,
              currency: item.currency,
              lastDetectedAt: item.detectedAt,
            ),
          )
          .toList();

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

  @override
  Future<List<Map<String, dynamic>>> getHotspots() async => [
    {'camera': 'Demo Junction', 'violationCount': 8, 'riskScore': 87.5, 'topViolation': 'tripleRiding'},
  ];

  @override
  Future<List<Map<String, dynamic>>> getVipVehicles() async => [
    {'plate': 'KA01VIP001', 'owner': 'Emergency Services', 'reason': 'Ambulance escort', 'active': true},
  ];

  @override
  Future<Map<String, dynamic>> addVipVehicle({required String plate, required String owner, required String reason}) async =>
      {'plate': plate, 'owner': owner, 'reason': reason, 'active': true};

  @override
  Future<Map<String, dynamic>> previewNotification({required String incidentId, required String channel, required String recipient}) async =>
      {'status': 'preview', 'sandbox': true, 'channel': channel, 'recipient': recipient};

  @override
  Future<Map<String, dynamic>> sandboxPayment({required String penaltyId, required int amount}) async =>
      {'status': 'success', 'sandbox': true, 'penaltyId': penaltyId, 'amount': amount};
}
