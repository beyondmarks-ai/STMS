enum ViolationType {
  noHelmet('No helmet'),
  tripleRiding('Triple riding'),
  wrongSide('Wrong side'),
  ambulanceObstruction('Ambulance obstruction'),
  tamperedPlate('Suspicious/tampered plate');

  const ViolationType(this.label);
  final String label;

  static ViolationType fromWire(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => noHelmet);
}

enum PlateStatus {
  readable,
  fake,
  obscured,
  unreadable;

  static PlateStatus fromWire(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => unreadable,
  );
}

enum ReviewStatus {
  pending('Pending review'),
  approved('Approved'),
  rejected('Rejected'),
  needsReview('Needs review');

  const ReviewStatus(this.label);
  final String label;

  static ReviewStatus fromWire(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => pending);
}

class ViolationIncident {
  const ViolationIncident({
    required this.id,
    required this.type,
    required this.status,
    required this.plate,
    required this.camera,
    required this.confidence,
    required this.detectedAt,
    required this.explanation,
    required this.evidenceUrl,
    this.plateCropUrl,
    this.faceCropUrl,
    this.riderCount,
    this.vehicleType,
    this.vehicleBodyStyle,
    this.vehicleColor,
    this.vehicleMake,
    this.vehicleModel,
    this.azureDescription,
    this.enrichmentConfidence,
    this.enrichmentUncertainties = const [],
    this.note,
    this.plateStatus = PlateStatus.readable,
    this.mobileCapture = false,
    this.imageProofUrl,
  });

  final String id;
  final ViolationType type;
  final ReviewStatus status;
  final String plate;
  final String camera;
  final double confidence;
  final DateTime detectedAt;
  final String explanation;
  final String evidenceUrl;
  final String? plateCropUrl;
  final String? faceCropUrl;
  final int? riderCount;
  final String? vehicleType;
  final String? vehicleBodyStyle;
  final String? vehicleColor;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? azureDescription;
  final double? enrichmentConfidence;
  final List<String> enrichmentUncertainties;
  final String? note;
  final PlateStatus plateStatus;
  final bool mobileCapture;
  final String? imageProofUrl;

  ViolationIncident copyWith({ReviewStatus? status, String? note}) =>
      ViolationIncident(
        id: id,
        type: type,
        status: status ?? this.status,
        plate: plate,
        camera: camera,
        confidence: confidence,
        detectedAt: detectedAt,
        explanation: explanation,
        evidenceUrl: evidenceUrl,
        plateCropUrl: plateCropUrl,
        faceCropUrl: faceCropUrl,
        riderCount: riderCount,
        vehicleType: vehicleType,
        vehicleBodyStyle: vehicleBodyStyle,
        vehicleColor: vehicleColor,
        vehicleMake: vehicleMake,
        vehicleModel: vehicleModel,
        azureDescription: azureDescription,
        enrichmentConfidence: enrichmentConfidence,
        enrichmentUncertainties: enrichmentUncertainties,
        note: note ?? this.note,
        plateStatus: plateStatus,
        mobileCapture: mobileCapture,
        imageProofUrl: imageProofUrl,
      );

  factory ViolationIncident.fromJson(Map<String, dynamic> json) =>
      ViolationIncident(
        id: json['id'] as String,
        type: ViolationType.fromWire(json['type'] as String),
        status: ReviewStatus.fromWire(json['status'] as String),
        plate: json['plate'] as String? ?? 'Unreadable',
        camera: json['camera'] as String? ?? 'Unknown camera',
        confidence: (json['confidence'] as num).toDouble(),
        detectedAt: DateTime.parse(json['detectedAt'] as String),
        explanation: json['explanation'] as String? ?? '',
        evidenceUrl: json['evidenceUrl'] as String? ?? '',
        plateCropUrl: json['plateCropUrl'] as String?,
        faceCropUrl: json['faceCropUrl'] as String?,
        riderCount: json['riderCount'] as int?,
        vehicleType: json['vehicleType'] as String?,
        vehicleBodyStyle: json['vehicleBodyStyle'] as String?,
        vehicleColor: json['vehicleColor'] as String?,
        vehicleMake: json['vehicleMake'] as String?,
        vehicleModel: json['vehicleModel'] as String?,
        azureDescription: json['azureDescription'] as String?,
        enrichmentConfidence: (json['enrichmentConfidence'] as num?)
            ?.toDouble(),
        enrichmentUncertainties:
            (json['enrichmentUncertainties'] as List<dynamic>?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
        note: json['note'] as String?,
        plateStatus: PlateStatus.fromWire(json['plateStatus'] as String?),
        mobileCapture: json['mobileCapture'] as bool? ?? false,
        imageProofUrl: json['imageProofUrl'] as String?,
      );
}

enum JobStatus {
  queued('Queued'),
  processing('Processing'),
  completed('Completed'),
  failed('Failed');

  const JobStatus(this.label);
  final String label;

  static JobStatus fromWire(String value) =>
      values.firstWhere((item) => item.name == value, orElse: () => queued);
}

class ProcessingJob {
  const ProcessingJob({
    required this.id,
    required this.fileName,
    required this.camera,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.incidentCount = 0,
    this.error,
  });

  final String id;
  final String fileName;
  final String camera;
  final JobStatus status;
  final double progress;
  final DateTime createdAt;
  final int incidentCount;
  final String? error;

  factory ProcessingJob.fromJson(Map<String, dynamic> json) => ProcessingJob(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    camera: json['camera'] as String,
    status: JobStatus.fromWire(json['status'] as String),
    progress: (json['progress'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    incidentCount: json['incidentCount'] as int? ?? 0,
    error: json['error'] as String?,
  );
}
