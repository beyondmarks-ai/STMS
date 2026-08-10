import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/live_camera.dart';

class LiveCameraService {
  const LiveCameraService();

  Future<Map<String, dynamic>> health(String gatewayUrl) async {
    final response = await http
        .get(Uri.parse('${_gateway(gatewayUrl)}/health'))
        .timeout(const Duration(seconds: 8));
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<RtspProbeResult> testCamera({
    required String gatewayUrl,
    required String token,
    required String cameraName,
    required String rtspUrl,
  }) async {
    final response = await http
        .post(
          Uri.parse('${_gateway(gatewayUrl)}/api/v1/cameras/test'),
          headers: _headers(token),
          body: jsonEncode(_cameraPayload(cameraName, rtspUrl)),
        )
        .timeout(const Duration(seconds: 20));
    _ensureSuccess(response);
    return RtspProbeResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LiveCameraStatus> startCamera({
    required String gatewayUrl,
    required String token,
    required String cameraName,
    required String rtspUrl,
  }) async {
    final response = await http
        .post(
          Uri.parse('${_gateway(gatewayUrl)}/api/v1/cameras'),
          headers: _headers(token),
          body: jsonEncode(_cameraPayload(cameraName, rtspUrl)),
        )
        .timeout(const Duration(seconds: 25));
    _ensureSuccess(response);
    return LiveCameraStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LiveCameraStatus> getCamera({
    required String gatewayUrl,
    required String token,
    required String cameraId,
  }) async {
    final response = await http
        .get(
          Uri.parse('${_gateway(gatewayUrl)}/api/v1/cameras/$cameraId'),
          headers: _headers(token, includeContentType: false),
        )
        .timeout(const Duration(seconds: 10));
    _ensureSuccess(response);
    return LiveCameraStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<LiveCameraStatus> stopCamera({
    required String gatewayUrl,
    required String token,
    required String cameraId,
  }) async {
    final response = await http
        .delete(
          Uri.parse('${_gateway(gatewayUrl)}/api/v1/cameras/$cameraId'),
          headers: _headers(token, includeContentType: false),
        )
        .timeout(const Duration(seconds: 10));
    _ensureSuccess(response);
    return LiveCameraStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Map<String, String> _headers(
    String token, {
    bool includeContentType = true,
  }) => {
    'X-EDGE-TOKEN': token.trim(),
    'Accept': 'application/json',
    if (includeContentType) 'Content-Type': 'application/json',
  };

  Map<String, dynamic> _cameraPayload(String cameraName, String rtspUrl) => {
    'cameraName': cameraName.trim(),
    'rtspUrl': rtspUrl.trim(),
    'segmentSeconds': 8,
    'intervalSeconds': 60,
    'captureFps': 8,
  };

  String _gateway(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Enter a valid edge gateway URL such as http://192.168.1.10:8090',
      );
    }
    return trimmed;
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var detail = 'Edge connector returned ${response.statusCode}';
    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final value = payload['detail'];
      if (value is String && value.isNotEmpty) detail = value;
    } catch (_) {
      // Keep the status-only message for a non-JSON response.
    }
    throw LiveCameraException(detail);
  }
}

class LiveCameraException implements Exception {
  const LiveCameraException(this.message);

  final String message;

  @override
  String toString() => message;
}
