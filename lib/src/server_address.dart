import 'package:flutter/foundation.dart';

@immutable
class ServerAddress {
  const ServerAddress._(this.uri);

  final Uri uri;

  static ServerAddress parse(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('请输入服务器地址');
    final candidate = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (candidate == null ||
        !candidate.hasAuthority ||
        candidate.host.isEmpty ||
        (candidate.scheme != 'http' && candidate.scheme != 'https') ||
        candidate.userInfo.isNotEmpty ||
        candidate.hasQuery ||
        candidate.hasFragment) {
      throw const FormatException('请输入有效的 HTTP(S) 服务器根地址');
    }
    final normalizedPath = candidate.path.replaceFirst(RegExp(r'/+$'), '');
    return ServerAddress._(candidate.replace(path: normalizedPath));
  }

  Uri endpoint(String path, [Map<String, String>? query]) {
    final suffix = path.replaceFirst(RegExp(r'^/+'), '');
    final joined = '${uri.path}/$suffix'.replaceAll(RegExp(r'/+'), '/');
    return uri.replace(path: joined, queryParameters: query);
  }

  bool contains(Uri target) =>
      target.scheme == uri.scheme &&
      target.host.toLowerCase() == uri.host.toLowerCase() &&
      target.port == uri.port;

  @override
  String toString() => uri.toString();
}
