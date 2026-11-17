import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:brr/core/config/api_config.dart';

/// HTTP client for the app's backend. Injects `Authorization: Bearer`
/// and retries once with a fresh token on 401.
///
/// [getAccessToken] is supplied by AuthViewModel — it returns the
/// current access token, refreshing first if needed.
class ApiClient {
  ApiClient({required this._getAccessToken});

  final Future<String?> Function() _getAccessToken;
  final http.Client _client = http.Client();

  /// Client เฉพาะ streaming — ปิด autoUncompress เพื่อนับ bytes
  /// บนสายจริง (ตรง Content-Length ของ payload ที่บีบ) แล้วค่อย
  /// gunzip เองหลังรับครบ. autoUncompress=true จะทำ % เพี้ยน
  /// เพราะ received (ขนาดแตกแล้ว) > total (ขนาดบีบ)
  final http.Client _streamClient = IOClient(
    HttpClient()..autoUncompress = false,
  );

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<http.Response> get(String path) => _send('GET', path);

  /// Streams a GET — reports download progress as (received, total?)
  /// bytes; total is null when the server omits Content-Length.
  Future<http.Response> getStreamed(
    String path, {
    void Function(int received, int? total)? onProgress,
    /// เรียกเมื่อรับ bytes ครบแล้วก่อน gunzip — ไม่งั้น UI ค้าง
    /// ที่ 100% ระหว่าง decode (gunzip+parse ใน isolate ใช้เวลา)
    void Function()? onProcessing,
    bool retried = false,
  }) async {
    final token = await _getAccessToken();
    final req = http.Request('GET', _uri(path))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept-Encoding': 'gzip',
        if (token != null && token.isNotEmpty)
          'Authorization': 'Bearer $token',
      });
    final streamed = await _streamClient.send(req);
    if (streamed.statusCode == 401 && !retried) {
      final fresh = await _getAccessToken();
      if (fresh != null && fresh.isNotEmpty && fresh != token) {
        return getStreamed(
          path,
          onProgress: onProgress,
          onProcessing: onProcessing,
          retried: true,
        );
      }
    }
    final total = streamed.contentLength;
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in streamed.stream) {
      bytes.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total != null && total > 0 ? total : null);
    }
    final raw = bytes.toBytes();
    // gunzip ใน isolate — payload ใหญ่ decode บน main จะค้างจอ
    onProcessing?.call();
    final body = await compute(
      _maybeGunzip,
      (raw, streamed.headers['content-encoding']),
    );
    return http.Response.bytes(
      body,
      streamed.statusCode,
      headers: streamed.headers,
    );
  }

  Future<http.Response> postJson(String path, Map<String, Object?> body) =>
      _send('POST', path, body: jsonEncode(body));

  Future<http.Response> putJson(String path, Map<String, Object?> body) =>
      _send('PUT', path, body: jsonEncode(body));

  Future<http.Response> patchJson(String path, Map<String, Object?> body) =>
      _send('PATCH', path, body: jsonEncode(body));

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
    bool retried = false,
  }) async {
    final token = await _getAccessToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final uri = _uri(path);
    final res = method == 'GET'
        ? await _client.get(uri, headers: headers)
        : method == 'PUT'
        ? await _client.put(uri, headers: headers, body: body)
        : method == 'PATCH'
        ? await _client.patch(uri, headers: headers, body: body)
        : await _client.post(uri, headers: headers, body: body);
    // Expired token — get a fresh one and retry once.
    if (res.statusCode == 401 && !retried) {
      final fresh = await _getAccessToken();
      if (fresh != null && fresh.isNotEmpty && fresh != token) {
        return _send(method, path, body: body, retried: true);
      }
    }
    return res;
  }
}

/// แตก gzip ถ้า response บีบมา — รันใน isolate ผ่าน compute()
List<int> _maybeGunzip((List<int> bytes, String? encoding) packed) {
  final (bytes, encoding) = packed;
  return encoding == 'gzip' ? GZipCodec().decode(bytes) : bytes;
}
