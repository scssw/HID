import 'dart:convert';

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
