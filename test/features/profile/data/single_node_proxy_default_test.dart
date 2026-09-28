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

  group('port hopping', () {
    test('parsePortRanges parses ranges and single ports', () {
      expect(parsePortRanges('20000-50000'), [(20000, 50000)]);
      expect(parsePortRanges('20000:50000'), [(20000, 50000)]);
      expect(parsePortRanges('4433, 20000-50000'), [(4433, 4433), (20000, 50000)]);
    });

    test('pickRandomPort picks a port within the range', () {
      for (var i = 0; i < 20; i++) {
        final port = pickRandomPort('20000-50000');
        expect(port, isNotNull);
        expect(port! >= 20000 && port <= 50000, isTrue);
      }
    });

    test('randomizePortHopping updates server_port for mport outbound', () {
      const config = '''
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-node",
      "server": "bw6.ssrr.today",
      "server_port": 4433,
      "mport": "20000-50000"
    }
  ]
}
''';

      final randomizedJson = randomizePortHopping(config);
      final decoded = jsonDecode(randomizedJson) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List;
      final hy2 = outbounds.first as Map<String, dynamic>;

      expect(hy2['mport'], '20000-50000');
      final newPort = hy2['server_port'] as int;
      expect(newPort >= 20000 && newPort <= 50000, isTrue);
    });

    test('patchMportIntoConfig extracts mport from raw direct hysteria2 URL', () {
      const rawUrl = 'hysteria2://061520262112.nNMfmn@bw6.ssrr.today:4433/?sni=bw6.ssrr.today&peer=bw6.ssrr.today&insecure=0&downmbps=50%20Mbps&mport=20000-50000#Bw6-UNI-12.15';
      const config = '''
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "Bw6-UNI-12.15 § 0",
      "server": "bw6.ssrr.today",
      "server_port": 4433
    }
  ]
}
''';

      final patchedJson = patchMportIntoConfig(config, rawUrl);
      final decoded = jsonDecode(patchedJson) as Map<String, dynamic>;
      final hy2 = (decoded['outbounds'] as List).first as Map<String, dynamic>;

      expect(hy2['mport'], '20000-50000');
      final newPort = hy2['server_port'] as int;
      expect(newPort >= 20000 && newPort <= 50000, isTrue);
    });

    test('patchMportIntoConfig extracts mport from base64 subscription content', () {
      // Base64 encoding of: hysteria2://CnFH7p.GpzTEK@bw6.ssrr.today:4433/?sni=bw6.ssrr.today&peer=bw6.ssrr.today&insecure=0&downmbps=50%20Mbps&mport=20000-50000#Bw6-UNI
      const base64Sub = 'aHlzdGVyaWEyOi8vQ25GSDdwLkdwelRFS0BidzYuc3Nyci50b2RheTo0NDMzLz9zbmk9Ync2LnNzcnIudG9kYXkmcGVlcj1idzYuc3Nyci50b2RheSZpbnNlY3VyZT0wJmRvd25tYnBzPTUwJTIwTWJwcyZtcG9ydD0yMDAwMC01MDAwMCNCdzYtVU5J';
      const config = '''
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "Bw6-UNI § 0",
      "server": "bw6.ssrr.today",
      "server_port": 4433
    }
  ]
}
''';

      final patchedJson = patchMportIntoConfig(config, base64Sub);
      final decoded = jsonDecode(patchedJson) as Map<String, dynamic>;
      final hy2 = (decoded['outbounds'] as List).first as Map<String, dynamic>;

      expect(hy2['mport'], '20000-50000');
      final newPort = hy2['server_port'] as int;
      expect(newPort >= 20000 && newPort <= 50000, isTrue);
    });
  });
}

