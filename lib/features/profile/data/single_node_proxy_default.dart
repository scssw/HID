import 'dart:convert';
import 'dart:math';

/// Selects the only node in the built-in Auto group as the default proxy.
///
/// The Auto group remains in the selector so users can switch back to it
/// manually. Configurations which do not match the expected shape are left
/// untouched.
String selectOnlyProxyAsDefault(String config) {
  try {
    final decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) return config;

    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return config;

    var changed = false;
    for (final autoGroup in outbounds.whereType<Map<String, dynamic>>()) {
      final type = autoGroup['type'];
      final autoTag = autoGroup['tag'];
      if ((type != 'urltest' && type != 'url-test') || autoTag != 'auto') {
        continue;
      }

      final autoOutbounds = autoGroup['outbounds'];
      if (autoOutbounds is! List || autoOutbounds.length != 1) continue;

      final nodeTags = autoOutbounds.whereType<String>().toList();
      if (nodeTags.length != 1) continue;

      final nodeTag = nodeTags.single;
      for (final selector in outbounds.whereType<Map<String, dynamic>>()) {
        if (selector['type'] != 'selector' || selector['default'] != autoTag) {
          continue;
        }

        final selectorOutbounds = selector['outbounds'];
        if (selectorOutbounds is! List ||
            !selectorOutbounds.contains(autoTag) ||
            !selectorOutbounds.contains(nodeTag)) {
          continue;
        }

        selector['default'] = nodeTag;
        changed = true;
      }
    }

    return changed ? jsonEncode(decoded) : config;
  } catch (_) {
    return config;
  }
}

/// Returns true when [config] contains exactly one real proxy outbound
/// (i.e. a single-node profile, without selector/url-test groups).
bool hasSingleProxyOutbound(String config) {
  try {
    final decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) return false;

    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return false;

    final nodes = outbounds.whereType<Map<String, dynamic>>().where((outbound) {
      final type = outbound['type'];
      return type is String &&
          type != 'selector' &&
          type != 'urltest' &&
          type != 'url-test' &&
          type != 'direct' &&
          type != 'block' &&
          type != 'dns' &&
          type != 'custom';
    }).toList();

    return nodes.length == 1;
  } catch (_) {
    return false;
  }
}

/// Parses a port range string like "20000-50000", "20000:50000", or "4433, 20000-50000" into [(min, max)] pairs.
List<(int, int)> parsePortRanges(String mport) {
  final ranges = <(int, int)>[];
  for (final part in mport.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    String? sep;
    if (trimmed.contains('-')) {
      sep = '-';
    } else if (trimmed.contains(':')) {
      sep = ':';
    }
    if (sep != null) {
      final sub = trimmed.split(sep);
      if (sub.length == 2) {
        final start = int.tryParse(sub[0].trim());
        final end = int.tryParse(sub[1].trim());
        if (start != null && end != null && start > 0 && end > 0 && start <= 65535 && end <= 65535) {
          ranges.add(start <= end ? (start, end) : (end, start));
        }
      }
    } else {
      final p = int.tryParse(trimmed);
      if (p != null && p > 0 && p <= 65535) {
        ranges.add((p, p));
      }
    }
  }
  return ranges;
}

/// Picks a random port uniformly from the port ranges.
int? pickRandomPort(String mport) {
  final ranges = parsePortRanges(mport);
  if (ranges.isEmpty) return null;
  var total = 0;
  for (final r in ranges) {
    total += (r.$2 - r.$1 + 1);
  }
  if (total <= 0) return null;
  var idx = Random().nextInt(total);
  for (final r in ranges) {
    final count = r.$2 - r.$1 + 1;
    if (idx < count) {
      return r.$1 + idx;
    }
    idx -= count;
  }
  return ranges.first.$1;
}

/// Randomizes the `server_port` of any hysteria / hysteria2 outbound that has `mport`.
String randomizePortHopping(String config) {
  try {
    final decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) return config;
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return config;

    var changed = false;
    for (final outbound in outbounds.whereType<Map<String, dynamic>>()) {
      final type = outbound['type'];
      if (type != 'hysteria2' && type != 'hysteria' && type != 'hy2' && type != 'hy') continue;
      final mport = outbound['mport'] ?? outbound['ports'];
      String? mportStr;
      if (mport is String && mport.trim().isNotEmpty) {
        mportStr = mport.trim();
      } else if (outbound['server_ports'] is List && (outbound['server_ports'] as List).isNotEmpty) {
        mportStr = (outbound['server_ports'] as List).map((e) => e.toString()).join(',');
      }
      if (mportStr != null) {
        final newPort = pickRandomPort(mportStr);
        if (newPort != null && newPort > 0) {
          outbound['server_port'] = newPort;
          changed = true;
        }
      }
    }
    return changed ? jsonEncode(decoded) : config;
  } catch (_) {
    return config;
  }
}

/// Extracts mport definitions from raw URLs or subscriptions and patches them into the profile JSON.
String patchMportIntoConfig(String config, String rawInput) {
  try {
    final decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) return config;
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return config;

    var text = rawInput;
    // Check if base64 encoded
    try {
      final trimmed = rawInput.trim();
      if (!trimmed.startsWith('hysteria2://') &&
          !trimmed.startsWith('hy2://') &&
          !trimmed.startsWith('hysteria://') &&
          !trimmed.startsWith('hy://') &&
          !trimmed.startsWith('http://') &&
          !trimmed.startsWith('https://')) {
        final b64Decoded = utf8.decode(base64.decode(base64.normalize(trimmed)));
        if (b64Decoded.isNotEmpty) {
          text = b64Decoded;
        }
      }
    } catch (_) {}

    final mportMap = <String, String>{};
    String? fallbackMport;

    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (!lower.startsWith('hysteria2://') &&
          !lower.startsWith('hy2://') &&
          !lower.startsWith('hysteria://') &&
          !lower.startsWith('hy://')) {
        continue;
      }
      final uri = Uri.tryParse(trimmed);
      if (uri == null) continue;
      final mport = uri.queryParameters['mport'] ??
          uri.queryParameters['ports'] ??
          uri.queryParameters['mports'];
      if (mport != null && mport.trim().isNotEmpty) {
        final cleanMport = mport.trim();
        final tag = uri.fragment.isNotEmpty
            ? Uri.decodeComponent(uri.fragment.split('&&detour')[0]).trim()
            : '';
        if (tag.isNotEmpty) {
          mportMap[tag] = cleanMport;
        }
        fallbackMport ??= cleanMport;
      }
    }

    if (mportMap.isEmpty && fallbackMport == null) return config;

    var changed = false;
    for (final outbound in outbounds.whereType<Map<String, dynamic>>()) {
      final type = outbound['type'];
      if (type != 'hysteria2' && type != 'hysteria' && type != 'hy2' && type != 'hy') continue;
      final tag = outbound['tag']?.toString().trim() ?? '';
      String? matchedMport = mportMap[tag];
      if (matchedMport == null) {
        for (final entry in mportMap.entries) {
          if (tag.startsWith(entry.key)) {
            matchedMport = entry.value;
            break;
          }
        }
      }
      matchedMport ??= fallbackMport;

      if (matchedMport != null && matchedMport.isNotEmpty) {
        if (outbound['mport'] == null || outbound['mport'].toString().trim().isEmpty) {
          outbound['mport'] = matchedMport;
          changed = true;
        }
        final initialPort = pickRandomPort(matchedMport);
        if (initialPort != null && initialPort > 0) {
          outbound['server_port'] = initialPort;
          changed = true;
        }
      }
    }
    return changed ? jsonEncode(decoded) : config;
  } catch (_) {
    return config;
  }
}

