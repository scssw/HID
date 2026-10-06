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

  group('LinkParser for AnyTLS', () {
    test('parses anytls protocol link with fragment name', () {
      const anytlsUrl =
          'anytls://OPzNxfEQjB@txany.ssrr.today:52978?security=tls&sni=txany.ssrr.today#anytls-52978';
      final parsed = LinkParser.protocol(anytlsUrl);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'anytls-52978');
    });

    test('parses base64 subscription containing anytls', () {
      const b64 =
          'YW55dGxzOi8veXl2VWJ0S01ZYUB0eGFueS5zc3JyLnRvZGF5OjUyOTc4P3NlY3VyaXR5PXRscyZzbmk9dHhhbnkuc3Nyci50b2RheSNhbnl0bHMtNTI5Nzg=';
      final parsed = LinkParser.protocol(b64);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'anytls-52978');
    });
  });

  group('LinkParser for sing-box and sinbox deep links', () {
    test('parses sing-box import-remote-profile with fragment as name', () {
      const link =
          'sing-box://import-remote-profile?url=http%3A%2F%2Ftxany.ssrr.today%3A36725%2Fsub%2F956ba01a-9c49-4a4b-adbc-2cad3e9051ca%3Fformat%3Djson#202610061340';
      final parsed = LinkParser.deep(link);
      expect(parsed, isNotNull);
      expect(
        parsed!.url,
        'http://txany.ssrr.today:36725/sub/956ba01a-9c49-4a4b-adbc-2cad3e9051ca?format=json',
      );
      expect(parsed.name, '202610061340');
    });

    test('parses sinbox import-remote-profile scheme', () {
      const link =
          'sinbox://import-remote-profile?url=http%3A%2F%2Ftxany.ssrr.today%3A36725%2Fsub%2F956ba01a-9c49-4a4b-adbc-2cad3e9051ca%3Fformat%3Djson#202610061340';
      final parsed = LinkParser.deep(link);
      expect(parsed, isNotNull);
      expect(
        parsed!.url,
        'http://txany.ssrr.today:36725/sub/956ba01a-9c49-4a4b-adbc-2cad3e9051ca?format=json',
      );
      expect(parsed.name, '202610061340');
    });

    test('LinkParser.parse resolves sinbox deep link', () {
      const link =
          'sinbox://import-remote-profile?url=http%3A%2F%2Ftxany.ssrr.today%3A36725%2Fsub%2F956ba01a-9c49-4a4b-adbc-2cad3e9051ca%3Fformat%3Djson#202610061340';
      final parsed = LinkParser.parse(link);
      expect(parsed, isNotNull);
      expect(
        parsed!.url,
        'http://txany.ssrr.today:36725/sub/956ba01a-9c49-4a4b-adbc-2cad3e9051ca?format=json',
      );
      expect(parsed.name, '202610061340');
    });
  });
}
