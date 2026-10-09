import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/domain_rules/notifier/custom_domain_rules_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CustomDomainRulesNotifier Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('normalizeDomain strips protocol, path, port and converts to lowercase', () {
      expect(CustomDomainRulesNotifier.normalizeDomain('https://GitHub.com/test'), 'github.com');
      expect(CustomDomainRulesNotifier.normalizeDomain('http://api.openai.com:8080/v1'), 'api.openai.com');
      expect(CustomDomainRulesNotifier.normalizeDomain('  .GOOGLE.COM/ '), 'google.com');
      expect(CustomDomainRulesNotifier.normalizeDomain('twitter.com'), 'twitter.com');
    });

    test('setRule adds a new rule and persists to SharedPreferences', () async {
      final notifier = CustomDomainRulesNotifier(prefs);

      await notifier.setRule('https://github.com/torvalds', 'proxy');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.domain, 'github.com');
      expect(notifier.state.first.outbound, 'proxy');
      expect(notifier.state.first.isProxy, isTrue);
      expect(notifier.state.first.isDirect, isFalse);

      // Verify persistence by initializing a new notifier from same prefs
      final reloaded = CustomDomainRulesNotifier(prefs);
      expect(reloaded.state.length, 1);
      expect(reloaded.state.first.domain, 'github.com');
      expect(reloaded.state.first.outbound, 'proxy');
    });

    test('setRule updates existing rule when domain already exists', () async {
      final notifier = CustomDomainRulesNotifier(prefs);

      await notifier.setRule('bilibili.com', 'bypass');
      expect(notifier.state.first.isDirect, isTrue);

      await notifier.setRule('bilibili.com', 'proxy');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.isProxy, isTrue);
      expect(notifier.state.first.isDirect, isFalse);
    });

    test('removeRule removes target domain rule', () async {
      final notifier = CustomDomainRulesNotifier(prefs);

      await notifier.setRule('domain1.com', 'proxy');
      await notifier.setRule('domain2.com', 'bypass');
      expect(notifier.state.length, 2);

      await notifier.removeRule('domain1.com');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.domain, 'domain2.com');
    });

    test('clearAll removes all rules', () async {
      final notifier = CustomDomainRulesNotifier(prefs);

      await notifier.setRule('domain1.com', 'proxy');
      await notifier.setRule('domain2.com', 'bypass');
      expect(notifier.state.length, 2);

      await notifier.clearAll();
      expect(notifier.state.isEmpty, isTrue);

      final reloaded = CustomDomainRulesNotifier(prefs);
      expect(reloaded.state.isEmpty, isTrue);
    });
  });
}
