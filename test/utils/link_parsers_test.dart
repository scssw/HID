import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/link_parsers.dart';

void main() {
  group('LinkParser.protocol for SSR', () {
    test('extracts remarks as profile name', () {
      const ssrUrl =
          'ssr://anMuc3Nyci50b2RheToyMjY1MzphdXRoX2NoYWluX2E6bm9uZTpwbGFpbjpaemQxV2xGaC8_cmVtYXJrcz1TbE02TWpJMk5UTXRNVEl1TWpV';
      final parsed = LinkParser.protocol(ssrUrl);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'JS:22653-12.25');
    });

    test('extracts remarks when fragment is also present', () {
      const ssrUrl =
          'ssr://anMuc3Nyci50b2RheToyMjY1MzphdXRoX2NoYWluX2E6bm9uZTpwbGFpbjpaemQxV2xGaC8_cmVtYXJrcz1TbE02TWpJMk5UTXRNVEl1TWpV#CustomFragment';
      final parsed = LinkParser.protocol(ssrUrl);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'JS:22653-12.25');
    });

    test('falls back to fragment or host:port if remarks missing', () {
      // js.ssrr.today:22653:auth_chain_a:none:plain:Zzd1WlFh/
      // base64: anMuc3Nyci50b2RheToyMjY1MzphdXRoX2NoYWluX2E6bm9uZTpwbGFpbjpaemQxV2xGaC8=
      const ssrUrlNoRemark =
          'ssr://anMuc3Nyci50b2RheToyMjY1MzphdXRoX2NoYWluX2E6bm9uZTpwbGFpbjpaemQxV2xGaC8';
      final parsed = LinkParser.protocol(ssrUrlNoRemark);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'js.ssrr.today:22653');
    });
  });
}
