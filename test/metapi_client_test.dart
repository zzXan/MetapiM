import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:metapi_m/src/metapi_client.dart';
import 'package:metapi_m/src/server_address.dart';

void main() {
  for (final wrapped in [true, false]) {
    test('snapshot accepts ${wrapped ? "wrapped" : "direct"} lists', () async {
      final client = MetapiClient(
        server: ServerAddress.parse('https://example.com'), token: 'fixture',
        client: MockClient((request) async {
          final accounts = [
            {'id': 1, 'site': {'name': 'Vendor'}, 'balance': 12.5}
          ];
          final logs = [
            {'id': 2, 'siteName': 'Vendor', 'promptTokens': 100,
             'completionTokens': 20, 'cacheReadTokens': 10, 'estimatedCost': 0.01}
          ];
          final data = request.url.path.endsWith('/accounts')
              ? (wrapped ? {'accounts': accounts} : accounts)
              : (wrapped ? {'items': logs} : logs);
          return http.Response(jsonEncode(data), 200);
        }),
      );
      final snapshot = await client.loadWidgetSnapshot();
      expect(snapshot.balances.single.balance, 12.5);
      expect(snapshot.recentCalls.single.estimatedCost, 0.01);
      client.close();
    });
  }
}
