import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'server_address.dart';
import 'widget_contract.dart';

class MetapiClient {
  MetapiClient({required this.server, required this.token, http.Client? client}) : _client = client ?? http.Client();
  final ServerAddress server;
  final String token;
  final http.Client _client;

  Future<void> validate() async {
    final data = await _get('api/settings/auth/verify');
    final payload = jsonDecode(utf8.decode(data));
    if (payload is! Map || payload['success'] != true) throw const MetapiAuthException();
  }

  Future<WidgetSnapshot> loadWidgetSnapshot() async {
    final responses = await Future.wait([
      _get('api/accounts'),
      _get('api/stats/proxy-logs', {'view': 'query', 'limit': '20', 'offset': '0'}),
    ]);
    final accountsPayload = jsonDecode(utf8.decode(responses[0]));
    final logsPayload = jsonDecode(utf8.decode(responses[1]));
    // Accept list and wrapped-list response shapes without inventing rows.
    final accountRows = accountsPayload is List ? accountsPayload
        : accountsPayload is Map ? accountsPayload['accounts'] : null;
    final logRows = logsPayload is List ? logsPayload
        : logsPayload is Map ? (logsPayload['items'] ?? logsPayload['logs']) : null;
    if (accountRows is! List || logRows is! List) {
      throw const FormatException('服务器返回的数据格式不正确');
    }
    final accounts = accountRows.whereType<Map>().map((m) => Map<String,dynamic>.from(m)).toList();
    final logs = logRows.whereType<Map>().map((m) => Map<String,dynamic>.from(m)).toList();
    return WidgetContract.snapshot(accounts: accounts, logs: logs);
  }

  Future<Uint8List> _get(String path, [Map<String, String>? query]) async {
    final uri = server.endpoint(path, query);
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll({'Authorization': 'Bearer $token', 'Accept': 'application/json'});
    final response = await http.Response.fromStream(await _client.send(request))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) throw const MetapiAuthException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('服务器返回 HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  void close() => _client.close();
}

class MetapiAuthException implements Exception {
  const MetapiAuthException();
  @override
  String toString() => '地址或管理员 Token 不正确';
}

class HttpException implements Exception {
  const HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
