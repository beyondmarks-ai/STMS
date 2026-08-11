import 'violation.dart';

enum PenaltyStatus {
  pending('Pending review'),
  confirmed('Confirmed'),
  voided('Void');

  const PenaltyStatus(this.label);
  final String label;

  static PenaltyStatus fromWire(String value) => switch (value) {
    'confirmed' => confirmed,
    'void' => voided,
    _ => pending,
  };
}

class PenaltyRecord {
  const PenaltyRecord({
    required this.id,
    required this.incidentId,
    required this.plate,
    required this.violationType,
    required this.violationLabel,
    required this.amount,
    required this.currency,
    required this.status,
    required this.camera,
    required this.detectedAt,
    this.reviewNote,
  });

  final String id;
  final String incidentId;
  final String plate;
  final ViolationType violationType;
  final String violationLabel;
  final int amount;
  final String currency;
  final PenaltyStatus status;
  final String camera;
  final DateTime detectedAt;
  final String? reviewNote;

  factory PenaltyRecord.fromJson(Map<String, dynamic> json) => PenaltyRecord(
    id: json['id'] as String,
    incidentId: json['incidentId'] as String,
    plate: json['plate'] as String,
    violationType: ViolationType.fromWire(json['violationType'] as String),
    violationLabel: json['violationLabel'] as String,
    amount: (json['amount'] as num).toInt(),
    currency: json['currency'] as String? ?? 'INR',
    status: PenaltyStatus.fromWire(json['status'] as String),
    camera: json['camera'] as String,
    detectedAt: DateTime.parse(json['detectedAt'] as String),
    reviewNote: json['reviewNote'] as String?,
  );
}

class VehiclePenaltySummary {
  const VehiclePenaltySummary({
    required this.plate,
    required this.penaltyCount,
    required this.pendingCount,
    required this.confirmedCount,
    required this.totalAmount,
    required this.confirmedAmount,
    required this.currency,
    required this.lastDetectedAt,
  });

  final String plate;
  final int penaltyCount;
  final int pendingCount;
  final int confirmedCount;
  final int totalAmount;
  final int confirmedAmount;
  final String currency;
  final DateTime lastDetectedAt;

  factory VehiclePenaltySummary.fromJson(Map<String, dynamic> json) =>
      VehiclePenaltySummary(
        plate: json['plate'] as String,
        penaltyCount: (json['penaltyCount'] as num).toInt(),
        pendingCount: (json['pendingCount'] as num).toInt(),
        confirmedCount: (json['confirmedCount'] as num).toInt(),
        totalAmount: (json['totalAmount'] as num).toInt(),
        confirmedAmount: (json['confirmedAmount'] as num).toInt(),
        currency: json['currency'] as String? ?? 'INR',
        lastDetectedAt: DateTime.parse(json['lastDetectedAt'] as String),
      );
}
