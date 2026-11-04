import 'package:flutter_test/flutter_test.dart';
import 'package:metapi_m/src/server_address.dart';
import 'package:metapi_m/src/widget_contract.dart';

void main() {
  test('web input rule handles included and split cache', () {
    expect(WidgetContract.resolveWebInputTokens(120, 20, 5), 120);
    expect(WidgetContract.resolveWebInputTokens(3, 50483, 0), 50486);
    expect(WidgetContract.resolveWebInputTokens(null, null, null), isNull);
  });
  test('percentage, missing cache and cost preserve provenance', () {
    final s = WidgetContract.snapshot(accounts: [], logs: [
      {'id': 1, 'promptTokens': 120, 'cacheReadTokens': 20, 'cacheCreationTokens': 5, 'estimatedCost': 0.1234567},
      {'id': 2, 'promptTokens': 50},
    ]);
    final c = s.recentCalls.firstWhere((c) => c.id == 1);
    expect(c.cacheHitRate, closeTo(20 / 120, 0.000001));
    expect(c.estimatedCost, 0.1234567);
    expect(s.recentCalls.firstWhere((c) => c.id == 2).cacheHitRate, isNull);
  });
  test('query is encoded separately from path; origin includes port', () {
    final s = ServerAddress.parse('https://example.com/');
    expect(s.endpoint('api/stats/proxy-logs', {'view': 'query'}).toString(), 'https://example.com/api/stats/proxy-logs?view=query');
    expect(s.contains(Uri.parse('https://example.com:444/')), isFalse);
    expect(() => ServerAddress.parse('file:///etc/passwd'), throwsFormatException);
    expect(() => ServerAddress.parse('https://user:password@example.com'), throwsFormatException);
  });
}
