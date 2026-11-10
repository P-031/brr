import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Future<http.Response> get(String path) => _send('GET', path);

  Future<http.Response> postJson(String path, Map<String, Object?> body) =>
      _send('POST', path, body: jsonEncode(body));

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
    final res = method == 'GET'
        ? await _client.get(_uri(path), headers: headers)
        : await _client.post(_uri(path), headers: headers, body: body);
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
