import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thin client for the DevMate FastAPI backend.
class Api {
  // Build-time default: flutter build web --dart-define=API_URL=https://...
  static const _defaultUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');
  static String baseUrl = _defaultUrl;
  static String token = '';

  /// Backend URL priority: ?api=... in the page URL > saved setting > build-time default.
  /// Lets the hosted app point at a Cloudflare Tunnel URL that changes, without rebuilding.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final fromQuery = Uri.base.queryParameters['api'];
    if (fromQuery != null && fromQuery.startsWith('http')) {
      await prefs.setString('api_url', fromQuery);
    }
    final tokenFromQuery = Uri.base.queryParameters['token'];
    if (tokenFromQuery != null) await prefs.setString('api_token', tokenFromQuery);
    baseUrl = (prefs.getString('api_url') ?? _defaultUrl).replaceAll(RegExp(r'/+$'), '');
    token = prefs.getString('api_token') ?? '';
  }

  static Future<void> configure(String url, String newToken) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    token = newToken.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', baseUrl);
    await prefs.setString('api_token', token);
  }

  static Map<String, String> get _auth => token.isEmpty ? {} : {'X-DevMate-Token': token};

  static Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl/api$path').replace(queryParameters: q);

  static dynamic _decode(http.Response r) {
    final body = utf8.decode(r.bodyBytes);
    if (r.statusCode >= 400) {
      String msg = body;
      try {
        msg = jsonDecode(body)['detail'].toString();
      } catch (_) {}
      throw ApiException(msg);
    }
    return body.isEmpty ? null : jsonDecode(body);
  }

  static Future<dynamic> get(String path) async => _decode(await http.get(_u(path), headers: _auth));

  static Future<dynamic> post(String path, [Map<String, dynamic>? body, Map<String, String>? query]) async =>
      _decode(await http.post(_u(path, query),
          headers: {'Content-Type': 'application/json', ..._auth}, body: jsonEncode(body ?? {})));

  static Future<dynamic> delete(String path) async => _decode(await http.delete(_u(path), headers: _auth));

  static Future<String> file(int pid, String path) async {
    final r = await http.get(_u('/projects/$pid/file', {'path': path}), headers: _auth);
    if (r.statusCode >= 400) throw ApiException('File not found');
    return utf8.decode(r.bodyBytes);
  }

  /// Raw bytes (PDF / ZIP downloads), sent with the access token.
  static Future<Uint8List> bytes(String path, [Map<String, String>? q]) async {
    final r = await http.get(_u(path, q), headers: _auth);
    if (r.statusCode >= 400) _decode(r);
    return r.bodyBytes;
  }

  static Future<dynamic> uploadZip(String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', _u('/projects/upload'))
      ..headers.addAll(_auth)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return _decode(await http.Response.fromStream(await req.send()));
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
