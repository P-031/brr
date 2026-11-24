import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'package:brr/core/config/api_config.dart';

/// ข้อผิดพลาดชั้น transport (เน็ตหลุด/timeout/DNS) — แยกชนิดจาก
/// error ที่ server ตอบกลับมา เพื่อให้ caller เลือก fallback ได้
/// เช่น createParcel เซฟเป็นร่างแทนที่จะทำฟอร์มหาย
class TransportException implements Exception {
  const TransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  /// request ทั่วไปต้องไม่แขวนบนเครือข่ายที่ dead-but-open —
  /// 30 วิพอสำหรับ endpoint ขนาดเล็กทั้งหมดในแอป
  static const _timeout = Duration(seconds: 30);

  /// streamed download (หลักหมื่นแปลง) — รอ header 30 วิ แล้วนับ
  /// เฉพาะช่วงที่ไม่มี chunk ไหลมาเกิน 2 นาทีค่อยตัด (สายอืดจริง
  /// แต่ยังไหลอยู่ไม่ถูกฆ่ากลางทาง)
  static const _streamIdleTimeout = Duration(minutes: 2);

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  /// ข้อผิดพลาดชั้น transport → ข้อความไทยสั้น ผู้ใช้ไม่ต้องเห็น
  /// "SocketException: Connection refused (OS Error: 111)"
  Never _transportError(Object e) {
    if (e is TimeoutException) {
      throw const TransportException(
        'เซิร์ฟเวอร์ตอบช้าเกินไป — ลองใหม่อีกครั้ง',
      );
    }
    throw const TransportException(
      'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจสอบอินเทอร์เน็ต',
    );
  }

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
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
    final http.StreamedResponse streamed;
    try {
      streamed = await _streamClient.send(req).timeout(_timeout);
    } catch (e) {
      _transportError(e);
    }
    if (streamed.statusCode == 401 && !retried) {
      // response เก่าต้อง drain ก่อนยิงใหม่ — ไม่งั้น connection
      // ค้างเปิดรอ GC (socket เสียบนเครื่องสเปกต่ำ)
      final fresh = await _getAccessToken();
      if (fresh != null && fresh.isNotEmpty && fresh != token) {
        unawaited(streamed.stream.drain<void>());
        return getStreamed(
          path,
          onProgress: onProgress,
          onProcessing: onProcessing,
          retried: true,
        );
      }
      // retry ไม่ได้ (ไม่มี token ใหม่/ได้ตัวเดิม) — คืน 401 เลย
      // ไม่ต้องเสียเวลาอ่าน+gunzip body ของ error
      return http.Response.bytes(
        await streamed.stream.toBytes(),
        streamed.statusCode,
        headers: streamed.headers,
      );
    }
    final total = streamed.contentLength;
    final bytes = BytesBuilder(copy: false);
    var received = 0;
    try {
      await for (final chunk in streamed.stream.timeout(_streamIdleTimeout)) {
        bytes.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total != null && total > 0 ? total : null);
      }
    } catch (e) {
      _transportError(e);
    }
    final raw = bytes.toBytes();
    // gunzip ใน isolate — payload ใหญ่ decode บน main จะค้างจอ
    onProcessing?.call();
    final body = await compute(_maybeGunzip, (
      raw,
      streamed.headers['content-encoding'],
    ));
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
    final http.Response res;
    try {
      res =
          await (method == 'GET'
                  ? _client.get(uri, headers: headers)
                  : method == 'PUT'
                  ? _client.put(uri, headers: headers, body: body)
                  : method == 'PATCH'
                  ? _client.patch(uri, headers: headers, body: body)
                  : _client.post(uri, headers: headers, body: body))
              .timeout(_timeout);
    } catch (e) {
      _transportError(e);
    }
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
