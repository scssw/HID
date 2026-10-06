import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
import 'package:hiddify/utils/validators.dart';

typedef ProfileLink = ({String url, String name});

// TODO: test and improve
abstract class LinkParser {
  static String generateSubShareLink(String url, [String? name]) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final modifiedUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      query: uri.query,
      fragment: name ?? uri.fragment,
    );
    // return 'hiddify://import/$modifiedUri';
    return '$modifiedUri';
  }

  // protocols schemas
  static const protocols = {'clash', 'clashmeta', 'sing-box', 'sinbox', 'hiddify'};

  static ProfileLink? parse(String link) {
    return simple(link) ?? deep(link);
  }

  static ProfileLink? simple(String link) {
    if (!isUrl(link)) return null;
    final uri = Uri.parse(link.trim());
    return (
      url: uri.toString(),
      name: uri.queryParameters['name'] ?? '',
    );
  }

  static ({String content, String name})? protocol(String content) {
    final normalContent = safeDecodeBase64(content);
    final lines = normalContent.split('\n');
    String? name;
    for (final line in lines) {
      final trimmedLine = line.trim();
      final uri = Uri.tryParse(trimmedLine);
      if (uri == null) continue;
      final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split("&&detour")[0]) : null;
      name ??= switch (uri.scheme) {
        'ss' => fragment ?? ProxyType.shadowsocks.label,
        'ssconf' => fragment ?? ProxyType.shadowsocks.label,
        'vmess' => parseVmessRemark(trimmedLine) ?? fragment ?? ProxyType.vmess.label,
        'vless' => fragment ?? ProxyType.vless.label,
        'trojan' => fragment ?? ProxyType.trojan.label,
        'tuic' => fragment ?? ProxyType.tuic.label,
        'hy2' || 'hysteria2' => fragment ?? ProxyType.hysteria2.label,
        'hy' || 'hysteria' => fragment ?? ProxyType.hysteria.label,
        'ssh' => fragment ?? ProxyType.ssh.label,
        'wg' => fragment ?? ProxyType.wireguard.label,
        'warp' => fragment ?? ProxyType.warp.label,
        'naive' || 'naive+https' || 'naive+http' || 'naive+quic' => fragment ?? ProxyType.naive.label,
        'phttp' || 'phttps' => fragment ?? ProxyType.http.label,
        'ssr' => parseSsrRemark(trimmedLine) ?? fragment ?? ProxyType.shadowsocksr.label,
        'anytls' => fragment ?? ProxyType.anytls.label,
        _ => null,
      };
    }
    final headers = ProfileRepositoryImpl.parseHeadersFromContent(content);
    final subinfo = ProfileParser.parse("", headers);

    if (subinfo.name.isNotNullOrEmpty && subinfo.name != "Remote Profile") {
      name = subinfo.name;
    }

    return (content: normalContent, name: name ?? ProxyType.unknown.label);
  }

  static ProfileLink? deep(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final queryParams = uri.queryParameters;
    switch (uri.scheme) {
      case 'clash' || 'clashmeta' when uri.authority == 'install-config':
        if (uri.authority != 'install-config' || !queryParams.containsKey('url')) return null;
        return (url: queryParams['url']!, name: queryParams['name'] ?? '');
      case 'sing-box' || 'sinbox':
        if (uri.authority != 'import-remote-profile' || !queryParams.containsKey('url')) return null;
        final name = (queryParams['name'] != null && queryParams['name']!.isNotEmpty)
            ? queryParams['name']!
            : (uri.hasFragment && uri.fragment.isNotEmpty ? Uri.decodeComponent(uri.fragment) : '');
        return (url: queryParams['url']!, name: name);
      case 'hiddify':
        if (uri.authority == "import") {
          return (url: uri.path.substring(1) + (uri.hasQuery ? "?${uri.query}" : ""), name: uri.fragment);
        }
        //for backward compatibility
        if ((uri.authority != 'install-config' && uri.authority != 'install-sub') || !queryParams.containsKey('url')) return null;
        return (url: queryParams['url']!, name: queryParams['name'] ?? '');
      default:
        return null;
    }
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}

String? safeBase64DecodeNullable(String str) {
  try {
    var normalized = str.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return utf8.decode(base64Decode(normalized), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

String? parseSsrRemark(String raw) {
  try {
    final trimmed = raw.trim();
    if (!trimmed.toLowerCase().startsWith('ssr://')) return null;

    var b64 = trimmed.substring(6).trim();
    String? fragment;
    final hashIndex = b64.indexOf('#');
    if (hashIndex != -1) {
      fragment = Uri.decodeComponent(b64.substring(hashIndex + 1)).trim();
      b64 = b64.substring(0, hashIndex).trim();
    }

    final decoded = safeBase64DecodeNullable(b64);
    if (decoded == null) return fragment;

    // SSR format: host:port:protocol:method:obfs:passwordB64/?remarks=remarksB64&...
    String query = '';
    final slashQ = decoded.indexOf('/?');
    if (slashQ != -1) {
      query = decoded.substring(slashQ + 2);
    } else {
      final q = decoded.indexOf('?');
      if (q != -1) {
        query = decoded.substring(q + 1);
      }
    }

    if (query.isNotEmpty) {
      for (final param in query.split('&')) {
        final kv = param.split('=');
        if (kv.length == 2 && kv[0].toLowerCase() == 'remarks') {
          final remark = safeBase64DecodeNullable(kv[1]);
          if (remark != null && remark.trim().isNotEmpty) {
            return remark.trim();
          }
        }
      }
    }

    if (fragment != null && fragment.isNotEmpty) {
      return fragment;
    }

    final parts = decoded.split(':');
    if (parts.length >= 2 && parts[0].isNotEmpty) {
      return '${parts[0]}:${parts[1]}';
    }
  } catch (_) {}
  return null;
}

String? parseVmessRemark(String raw) {
  try {
    final trimmed = raw.trim();
    if (!trimmed.toLowerCase().startsWith('vmess://')) return null;

    var b64 = trimmed.substring(8).trim();
    String? fragment;
    final hashIndex = b64.indexOf('#');
    if (hashIndex != -1) {
      fragment = Uri.decodeComponent(b64.substring(hashIndex + 1)).trim();
      b64 = b64.substring(0, hashIndex).trim();
    }

    final decoded = safeBase64DecodeNullable(b64);
    if (decoded != null) {
      final data = jsonDecode(decoded);
      if (data is Map && data['ps'] != null && data['ps'].toString().trim().isNotEmpty) {
        return data['ps'].toString().trim();
      }
    }
    return fragment;
  } catch (_) {}
  return null;
}
