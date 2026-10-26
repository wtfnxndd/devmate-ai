import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thin client for the DevMate FastAPI backend.
class Api {
  // Override at build time: flutter run --dart-define=API_URL=https://your-backend.onrender.com
  static const baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

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

  static Future<dynamic> get(String path) async => _decode(await http.get(_u(path)));

  static Future<dynamic> post(String path, [Map<String, dynamic>? body, Map<String, String>? query]) async =>
      _decode(await http.post(_u(path, query),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode(body ?? {})));

  static Future<dynamic> delete(String path) async => _decode(await http.delete(_u(path)));

  static Future<String> file(int pid, String path) async {
    final r = await http.get(_u('/projects/$pid/file', {'path': path}));
    if (r.statusCode >= 400) throw ApiException('File not found');
    return utf8.decode(r.bodyBytes);
  }

  static Future<dynamic> uploadZip(String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', _u('/projects/upload'))
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
