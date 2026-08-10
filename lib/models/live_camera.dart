class RtspProbeResult {
  const RtspProbeResult({
    required this.reachable,
    required this.endpoint,
    required this.message,
    this.codec,
    this.width,
    this.height,
  });

  final bool reachable;
  final String endpoint;
  final String message;
  final String? codec;
  final int? width;
  final int? height;

  factory RtspProbeResult.fromJson(Map<String, dynamic> json) =>
      RtspProbeResult(
        reachable: json['reachable'] as bool? ?? false,
        endpoint: json['endpoint'] as String? ?? '',
        message: json['message'] as String? ?? '',
        codec: json['codec'] as String?,
        width: json['width'] as int?,
        height: json['height'] as int?,
      );
}

class LiveCameraStatus {
  const LiveCameraStatus({
    required this.id,
    required this.cameraName,
    required this.endpoint,
    required this.state,
    required this.segmentSeconds,
    required this.intervalSeconds,
    required this.consecutiveFailures,
    required this.startedAt,
    this.lastJobId,
    this.lastUploadAt,
    this.lastError,
  });

  final String id;
  final String cameraName;
  final String endpoint;
  final String state;
  final int segmentSeconds;
  final int intervalSeconds;
  final String? lastJobId;
  final DateTime? lastUploadAt;
  final String? lastError;
  final int consecutiveFailures;
  final DateTime startedAt;

  bool get active => state != 'stopped' && state != 'stopping';

  factory LiveCameraStatus.fromJson(Map<String, dynamic> json) =>
      LiveCameraStatus(
        id: json['id'] as String,
        cameraName: json['cameraName'] as String,
        endpoint: json['endpoint'] as String,
        state: json['state'] as String,
        segmentSeconds: json['segmentSeconds'] as int,
        intervalSeconds: json['intervalSeconds'] as int,
        lastJobId: json['lastJobId'] as String?,
        lastUploadAt: json['lastUploadAt'] == null
            ? null
            : DateTime.parse(json['lastUploadAt'] as String),
        lastError: json['lastError'] as String?,
        consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}
