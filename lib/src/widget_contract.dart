import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class ProviderBalance {
  const ProviderBalance({required this.id, required this.name, required this.balance});
  final int id;
  final String name;
  final double balance;
}

@immutable
class ProxyCall {
  const ProxyCall({
    required this.id,
    required this.createdAt,
    required this.vendor,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheHitRate,
    required this.estimatedCost,
  });
  final int id;
  final DateTime? createdAt;
  final String vendor;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final double? cacheHitRate;
  final double? estimatedCost;
}

@immutable
class WidgetSnapshot {
  const WidgetSnapshot({required this.generatedAt, required this.balances, required this.recentCalls});
  final DateTime generatedAt;
  final List<ProviderBalance> balances;
  final List<ProxyCall> recentCalls;

  Map<String, dynamic> toJson() => {
    'schema': 'metapim-widget/v1',
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'balances': balances.map((b) => {'id': b.id, 'name': b.name, 'balance': b.balance}).toList(),
    'recentCalls': recentCalls.map((c) => {
      'id': c.id,
      'createdAt': c.createdAt?.toUtc().toIso8601String(),
      'vendor': c.vendor,
      'model': c.model,
      'inputTokens': c.inputTokens,
      'outputTokens': c.outputTokens,
      'cacheHitRate': c.cacheHitRate,
      'estimatedCost': c.estimatedCost,
    }).toList(),
  };

  String encode() => jsonEncode(toJson());
}

class WidgetContract {
  static WidgetSnapshot snapshot({
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> logs,
    DateTime? now,
  }) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final account in accounts) {
      final site = account['site'];
      final name = site is Map && site['name'] is String ? (site['name'] as String).trim() : '';
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => []).add(account);
    }
    final balances = grouped.entries.map((entry) {
      final rows = entry.value;
      final values = rows.map((r) => _number(r['balance']) ?? 0).toList();
      final id = rows.map((r) => _integer(r['id']) ?? 0).reduce((a, b) => a < b ? a : b);
      return ProviderBalance(id: id, name: entry.key, balance: values.fold<double>(0, (a, b) => a + b));
    }).toList()
      ..sort((a, b) {
        final balanceOrder = b.balance.compareTo(a.balance);
        return balanceOrder != 0 ? balanceOrder : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final calls = logs.map((row) {
      final prompt = _integer(row['promptTokens']);
      final cacheRead = _integer(row['cacheReadTokens']);
      final cacheCreation = _integer(row['cacheCreationTokens']);
      final effectiveInput = resolveWebInputTokens(prompt, cacheRead, cacheCreation);
      final hitRate = cacheRead == null || effectiveInput == null || effectiveInput <= 0
          ? null
          : (cacheRead / effectiveInput).clamp(0.0, 1.0).toDouble();
      final timestamp = DateTime.tryParse('${row['createdAt'] ?? ''}'.replaceFirst(' ', 'T'));
      final name = row['siteName'] is String ? (row['siteName'] as String).trim() : '';
      final model = row['modelRequested'] is String ? row['modelRequested'] as String : '';
      return ProxyCall(
        id: _integer(row['id']) ?? 0,
        createdAt: timestamp,
        vendor: name.isNotEmpty ? name : (model.isNotEmpty ? model : '未知供应商'),
        model: model,
        inputTokens: effectiveInput ?? prompt ?? 0,
        outputTokens: _integer(row['completionTokens']) ?? 0,
        cacheHitRate: hitRate,
        estimatedCost: _number(row['estimatedCost']),
      );
    }).toList()
      ..sort((a, b) {
        final byTime = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return WidgetSnapshot(generatedAt: (now ?? DateTime.now()).toUtc(), balances: balances, recentCalls: calls);
  }

  /// Exactly mirrors src/web/pages/helpers/proxyLogsHelpers.ts:
  /// cacheRead + cacheCreation are added only when their sum exceeds prompt.
  static int? resolveWebInputTokens(int? prompt, int? cacheRead, int? cacheCreation) {
    if (prompt == null && cacheRead == null && cacheCreation == null) return null;
    final p = prompt ?? 0;
    final cacheTotal = (cacheRead ?? 0) + (cacheCreation ?? 0);
    if (cacheTotal <= 0) return p;
    return cacheTotal > p ? p + cacheTotal : p;
  }

  static int? _integer(dynamic value) => value is num && value.isFinite ? value.toInt() : null;
  static double? _number(dynamic value) => value is num && value.isFinite ? value.toDouble() : null;
}
