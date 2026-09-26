import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/single_node_proxy_default.dart';

void main() {
  group('selectOnlyProxyAsDefault', () {
    test('selects the only Auto node while keeping Auto available', () {
      const config = '''
{
  "outbounds": [
    {
      "type": "selector",
      "tag": "proxy",
      "outbounds": ["auto", "only-node"],
      "default": "auto"
    },
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["only-node"]
    },
    {"type": "vless", "tag": "only-node"}
  ]
}
''';

      final result = jsonDecode(selectOnlyProxyAsDefault(config)) as Map;
      final selector = (result['outbounds'] as List).first as Map;

      expect(selector['default'], 'only-node');
      expect(selector['outbounds'], containsAll(['auto', 'only-node']));
    });

    test('does not change a multi-node Auto group', () {
      const config = '''
{"outbounds":[
  {"type":"selector","outbounds":["auto","node-a","node-b"],"default":"auto"},
  {"type":"urltest","tag":"auto","outbounds":["node-a","node-b"]}
]}
''';

      expect(selectOnlyProxyAsDefault(config), config);
    });

    test('does not override a manually selected default', () {
      const config = '''
{"outbounds":[
  {"type":"selector","outbounds":["auto","only-node"],"default":"only-node"},
  {"type":"urltest","tag":"auto","outbounds":["only-node"]}
]}
''';

      expect(selectOnlyProxyAsDefault(config), config);
    });

    test('leaves invalid JSON unchanged', () {
      const config = '{not json}';

      expect(selectOnlyProxyAsDefault(config), config);
    });
  });
}
