import 'dart:convert';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/domain_rules/model/custom_domain_rule.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final customDomainRulesProvider =
    StateNotifierProvider<CustomDomainRulesNotifier, List<CustomDomainRule>>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    return CustomDomainRulesNotifier(prefs);
  },
);

class CustomDomainRulesNotifier extends StateNotifier<List<CustomDomainRule>> {
  CustomDomainRulesNotifier(this._prefs) : super([]) {
    _loadRules();
  }

  final SharedPreferences _prefs;
  static const _storageKey = 'custom_domain_rules';

  void _loadRules() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      state = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .whereType<Map<String, dynamic>>()
          .map(CustomDomainRule.fromJson)
          .toList();
    } catch (_) {
      state = [];
    }
  }

  Future<void> _saveRules() async {
    final jsonList = state.map((r) => r.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  static String normalizeDomain(String raw) {
    var d = raw.trim().toLowerCase();
    if (d.startsWith('https://')) d = d.substring(8);
    if (d.startsWith('http://')) d = d.substring(7);
    final slashIdx = d.indexOf('/');
    if (slashIdx != -1) d = d.substring(0, slashIdx);
    final colonIdx = d.indexOf(':');
    if (colonIdx != -1) d = d.substring(0, colonIdx);
    while (d.startsWith('.')) {
      d = d.substring(1);
    }
    return d;
  }

  Future<void> setRule(String domain, String outbound) async {
    final clean = normalizeDomain(domain);
    if (clean.isEmpty) return;

    final existingIndex = state.indexWhere((r) => r.domain == clean);
    if (existingIndex >= 0) {
      final updated = List<CustomDomainRule>.from(state);
      updated[existingIndex] = updated[existingIndex].copyWith(
        outbound: outbound,
        updatedAt: DateTime.now(),
      );
      state = updated;
    } else {
      state = [
        CustomDomainRule(
          domain: clean,
          outbound: outbound,
          updatedAt: DateTime.now(),
        ),
        ...state,
      ];
    }
    await _saveRules();
  }

  Future<void> removeRule(String domain) async {
    final clean = normalizeDomain(domain);
    state = state.where((r) => r.domain != clean).toList();
    await _saveRules();
  }

  Future<void> clearAll() async {
    state = [];
    await _saveRules();
  }
}
