import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_model.dart';
import 'package:hiddify/singbox/service/singbox_service_provider.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class _VisitedSite {
  final String name;
  int count;
  int uploadBytes;
  int downloadBytes;
  String outbound; // '代理' or '直连'
  DateTime lastSeen;
  bool isCurrentlyActive;

  _VisitedSite({
    required this.name,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    required this.outbound,
    required this.lastSeen,
    this.isCurrentlyActive = false,
  }) : count = 1;
}

class ConnectionTopologyState {
  final ConnectionsAggregate aggregate;
  final String searchQuery;
  final String? activeOutboundFilter; // '直连', '代理', or null (all)
  final TopoNode? hoveredNode;
  final TopoLink? hoveredLink;
  final String? tooltipText;
  final Offset? tooltipPosition;

  const ConnectionTopologyState({
    required this.aggregate,
    this.searchQuery = '',
    this.activeOutboundFilter,
    this.hoveredNode,
    this.hoveredLink,
    this.tooltipText,
    this.tooltipPosition,
  });

  ConnectionTopologyState copyWith({
    ConnectionsAggregate? aggregate,
    String? searchQuery,
    String? activeOutboundFilter,
    bool clearOutboundFilter = false,
    TopoNode? hoveredNode,
    TopoLink? hoveredLink,
    String? tooltipText,
    Offset? tooltipPosition,
    bool clearHover = false,
  }) {
    return ConnectionTopologyState(
      aggregate: aggregate ?? this.aggregate,
      searchQuery: searchQuery ?? this.searchQuery,
      activeOutboundFilter: clearOutboundFilter
          ? null
          : (activeOutboundFilter ?? this.activeOutboundFilter),
      hoveredNode: clearHover ? null : (hoveredNode ?? this.hoveredNode),
      hoveredLink: clearHover ? null : (hoveredLink ?? this.hoveredLink),
      tooltipText: clearHover ? null : (tooltipText ?? this.tooltipText),
      tooltipPosition:
          clearHover ? null : (tooltipPosition ?? this.tooltipPosition),
    );
  }
}

final connectionTopologyNotifierProvider = StateNotifierProvider.autoDispose<
    ConnectionTopologyNotifier, ConnectionTopologyState>((ref) {
  return ConnectionTopologyNotifier(ref);
});

class ConnectionTopologyNotifier extends StateNotifier<ConnectionTopologyState> {
  final Ref _ref;
  Timer? _pollTimer;
  StreamSubscription? _logSubscription;
  late final Dio _dio;

  final Map<String, _VisitedSite> _visitedSites = {};
  final Set<String> _seenConnectionIds = <String>{};
  final Set<int> _processedLogLines = <int>{};
  final Map<String, String> _dnsCache = <String, String>{};
  String? _recentHost;
  int _logFileOffset = 0;

  ConnectionTopologyNotifier(this._ref)
      : super(ConnectionTopologyState(aggregate: ConnectionsAggregate.empty())) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ),
    );
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        return client;
      },
    );
    _startTracking();
  }

  void _startTracking() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      _pollActiveConnections();
    });

    _subscribeToLogs();
    _pollActiveConnections();
  }

  void _subscribeToLogs() {
    _logSubscription?.cancel();
    try {
      final singbox = _ref.read(singboxServiceProvider);
      final dirs = _ref.read(appDirectoriesProvider).valueOrNull;
      final logPath = (dirs != null && PlatformUtils.isDesktop)
          ? p.join(dirs.workingDir.path, 'box.log')
          : '';

      _logSubscription = singbox.watchLogs(logPath).listen(
        (lines) {
          _handleLogBatch(lines);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _handleLogBatch(List<String> lines) {
    final connStatus = _ref.read(connectionNotifierProvider).valueOrNull;
    final isConnected = connStatus is Connected;
    final isConnecting = connStatus is Connecting;
    if (!isConnected && !isConnecting) return;

    bool hasNewActivity = false;
    for (final line in lines) {
      if (line.isEmpty) continue;
      _checkDnsLogLine(line);
      final parsed = _parseLogLine(line);
      if (parsed != null) {
        final lineHash = line.hashCode;
        final isNew = !_processedLogLines.contains(lineHash);
        if (isNew) {
          _processedLogLines.add(lineHash);
          if (_processedLogLines.length > 3000) {
            _processedLogLines.clear();
          }
        }
        _recordTarget(parsed.host, parsed.outbound, 0, 0, isNew: isNew, isActive: true);
        hasNewActivity = true;
      }
    }

    if (hasNewActivity || state.aggregate.hosts.length != _visitedSites.length) {
      _rebuildAggregate();
    }
  }

  Future<void> _pollActiveConnections() async {
    final connStatus = _ref.read(connectionNotifierProvider).valueOrNull;
    final isConnected = connStatus is Connected;
    final isConnecting = connStatus is Connecting;

    if (!isConnected && !isConnecting) {
      if (state.aggregate.total > 0 || _visitedSites.isNotEmpty) {
        _visitedSites.clear();
        _seenConnectionIds.clear();
        _processedLogLines.clear();
        state = state.copyWith(aggregate: ConnectionsAggregate.empty());
      }
      return;
    }

    if (_logSubscription == null) {
      _subscribeToLogs();
    }

    final dirs = _ref.read(appDirectoriesProvider).valueOrNull;
    if (dirs == null) return;

    final workingDir = dirs.workingDir;
    bool hasNewActivity = false;

    // Reset currently active flags before checking Clash API
    for (final s in _visitedSites.values) {
      s.isCurrentlyActive = false;
    }

    // 1. Check Clash API (/connections) using controller & secret from current-config.json
    final configFile = File(p.join(workingDir.path, 'current-config.json'));
    if (configFile.existsSync()) {
      try {
        final configJson = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        final exp = configJson['experimental'] as Map<String, dynamic>?;
        final clashApi = exp?['clash_api'] as Map<String, dynamic>?;
        if (clashApi != null) {
          final controller = clashApi['external_controller'] as String? ?? '127.0.0.1:16756';
          final secret = clashApi['secret'] as String? ?? '';

          final url = 'http://$controller/connections';
          final response = await _dio.get<Map<String, dynamic>>(
            url,
            options: Options(
              headers: {
                if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
              },
            ),
          );

          if (response.statusCode == 200 && response.data != null) {
            final connections = response.data!['connections'] as List?;
            if (connections != null) {
              for (final raw in connections) {
                if (raw is! Map<String, dynamic>) continue;
                final meta = raw['metadata'] as Map<String, dynamic>?;
                if (meta == null) continue;

                final connId = raw['id']?.toString() ?? '';
                final isNewConnection = connId.isNotEmpty && !_seenConnectionIds.contains(connId);
                if (connId.isNotEmpty) {
                  _seenConnectionIds.add(connId);
                }

                final rawHost = (meta['host'] as String? ?? '').trim();
                final rawIp = (meta['destinationIP'] as String? ?? '').trim();
                final destPort = meta['destinationPort']?.toString() ?? '';

                // Filter internal/DNS
                if (destPort == '53') continue;
                if (rawIp == '172.19.0.2' || rawIp == '127.0.0.1') continue;

                // Prefer domain name over IP, check DNS cache if host is empty
                var target = rawHost;
                if (target.isEmpty && rawIp.isNotEmpty) {
                  target = _dnsCache[rawIp] ?? rawIp;
                }
                if (target.isEmpty ||
                    target.startsWith('192.168.') ||
                    target.startsWith('10.') ||
                    target.startsWith('172.19.') ||
                    target.startsWith('127.')) {
                  continue;
                }

                final chains = (raw['chains'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
                final rule = (raw['rule'] as String? ?? '').toLowerCase();

                final isDirect = chains.any((c) => c.contains('direct') || c.contains('bypass')) ||
                    rule.contains('direct') ||
                    rule.contains('bypass');
                final outbound = isDirect ? '直连' : '代理';

                final up = (raw['upload'] as num?)?.toInt() ?? 0;
                final down = (raw['download'] as num?)?.toInt() ?? 0;

                _recordTarget(
                  target,
                  outbound,
                  up,
                  down,
                  isActive: true,
                  isNew: isNewConnection,
                );
                hasNewActivity = true;
              }
            }
          }
        }
      } catch (_) {
        // Clash API poll skipped or transient error
      }
    }

    if (_seenConnectionIds.length > 5000) {
      _seenConnectionIds.clear();
    }

    // 2. Read newly appended lines in box.log
    final logFile = File(p.join(workingDir.path, 'box.log'));
    if (logFile.existsSync()) {
      try {
        final len = logFile.lengthSync();
        if (_logFileOffset == 0 && len > 0) {
          _logFileOffset = math.max(0, len - 32768);
        }
        if (len > _logFileOffset) {
          final stream = logFile.openRead(_logFileOffset, len);
          final content = await stream.transform(utf8.decoder).join();
          _logFileOffset = len;

          final lines = const LineSplitter().convert(content);
          for (final line in lines) {
            _checkDnsLogLine(line);
            final parsed = _parseLogLine(line);
            if (parsed != null) {
              _recordTarget(parsed.host, parsed.outbound, 0, 0, isNew: true, isActive: true);
              hasNewActivity = true;
            }
          }
        }
      } catch (_) {
        // Log reading fallback
      }
    }

    if (hasNewActivity || state.aggregate.hosts.length != _visitedSites.length) {
      _rebuildAggregate();
    }
  }

  void _checkDnsLogLine(String line) {
    if (!line.contains('dns: exchanged')) return;
    final dnsMatch = RegExp(r'dns:\s+exchanged\s+([a-zA-Z0-9.\-_]+)').firstMatch(line);
    if (dnsMatch != null) {
      final domain = dnsMatch.group(1)?.toLowerCase().trim();
      if (domain != null && domain.isNotEmpty) {
        final ipMatches = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').allMatches(line);
        for (final m in ipMatches) {
          final ip = m.group(0);
          if (ip != null &&
              !ip.startsWith('127.') &&
              !ip.startsWith('0.') &&
              !ip.startsWith('172.19.') &&
              !ip.startsWith('10.') &&
              !ip.startsWith('192.168.')) {
            _dnsCache[ip] = domain;
          }
        }
      }
    }
  }

  void _recordTarget(
    String target,
    String outbound,
    int up,
    int down, {
    bool isActive = false,
    bool isNew = false,
  }) {
    var cleanTarget = target.toLowerCase().trim();
    // Strip trailing port
    final colonIdx = cleanTarget.lastIndexOf(':');
    if (colonIdx > 0 && !cleanTarget.contains(']')) {
      cleanTarget = cleanTarget.substring(0, colonIdx);
    }
    if (cleanTarget.startsWith('[') && cleanTarget.endsWith(']')) {
      cleanTarget = cleanTarget.substring(1, cleanTarget.length - 1);
    }

    // Resolve from DNS cache if it's an IP
    if (_dnsCache.containsKey(cleanTarget)) {
      cleanTarget = _dnsCache[cleanTarget]!;
    }

    if (cleanTarget.isEmpty ||
        cleanTarget == 'localhost' ||
        cleanTarget.startsWith('127.') ||
        cleanTarget.startsWith('10.') ||
        cleanTarget.startsWith('192.168.') ||
        cleanTarget.startsWith('172.19.')) {
      return;
    }

    final existing = _visitedSites[cleanTarget];
    if (existing != null) {
      if (isNew) {
        existing.count += 1;
        existing.lastSeen = DateTime.now();
        _recentHost = cleanTarget;
      }
      existing.uploadBytes = math.max(existing.uploadBytes, up);
      existing.downloadBytes = math.max(existing.downloadBytes, down);
      existing.outbound = outbound;
      if (isActive) {
        existing.isCurrentlyActive = true;
      }
    } else {
      _recentHost = cleanTarget;
      _visitedSites[cleanTarget] = _VisitedSite(
        name: cleanTarget,
        uploadBytes: up,
        downloadBytes: down,
        outbound: outbound,
        lastSeen: DateTime.now(),
        isCurrentlyActive: isActive,
      );
    }
  }

  _ParsedLog? _parseLogLine(String line) {
    if (line.contains('127.0.0.1') || line.contains('::1')) return null;

    // Match real outbound connection lines in sing-box:
    // e.g. outbound/direct[direct]: outbound connection to domain.com:443
    // e.g. outbound/vless[NATUS:...]: outbound connection to domain.com:443
    final outboundConnMatch = RegExp(
      r'outbound/([a-zA-Z0-9_\-]+)(?:\[([^\]]*)\])?:\s+outbound\s+(?:packet\s+)?connection\s+to\s+([a-zA-Z0-9.\-_]+|\[[a-fA-F0-9:]+\])(?::\d+)?',
    ).firstMatch(line);

    if (outboundConnMatch != null) {
      final type = outboundConnMatch.group(1)?.toLowerCase() ?? '';
      final tag = outboundConnMatch.group(2)?.toLowerCase() ?? '';
      var target = outboundConnMatch.group(3)?.trim() ?? '';

      if (target.startsWith('[') && target.endsWith(']')) {
        target = target.substring(1, target.length - 1);
      }

      if (_dnsCache.containsKey(target)) {
        target = _dnsCache[target]!;
      }

      if (target.isNotEmpty &&
          !target.startsWith('127.') &&
          !target.startsWith('10.') &&
          !target.startsWith('192.168.') &&
          !target.startsWith('172.19.')) {
        final isDirect = type == 'direct' || tag.contains('direct') || tag.contains('bypass');
        return _ParsedLog(host: target, outbound: isDirect ? '直连' : '代理');
      }
    }

    return null;
  }

  void _rebuildAggregate() {
    if (_visitedSites.isEmpty) {
      state = state.copyWith(aggregate: ConnectionsAggregate.empty());
      return;
    }

    final proxyList = _visitedSites.values.where((s) => s.outbound == '代理').toList();
    final directList = _visitedSites.values.where((s) => s.outbound == '直连').toList();

    int sorter(_VisitedSite a, _VisitedSite b) {
      if (a.isCurrentlyActive != b.isCurrentlyActive) {
        return a.isCurrentlyActive ? -1 : 1;
      }
      final timeComp = b.lastSeen.compareTo(a.lastSeen);
      if (timeComp != 0) return timeComp;
      return b.count.compareTo(a.count);
    }

    proxyList.sort(sorter);
    directList.sort(sorter);

    // Keep up to 35 proxy targets and 35 direct targets independently!
    final topProxy = proxyList.take(35).toList();
    final topDirect = directList.take(35).toList();

    int totalProxy = 0;
    int totalDirect = 0;

    for (final s in _visitedSites.values) {
      if (s.outbound == '直连') {
        totalDirect += s.count;
      } else {
        totalProxy += s.count;
      }
    }

    final combined = [...topProxy, ...topDirect];

    final hosts = combined.map((site) {
      return ConnectionAggHost(
        name: site.name,
        count: site.count,
        recent: site.name == _recentHost || site.isCurrentlyActive,
        flows: [
          ConnectionAggFlow(outbound: site.outbound, count: site.count),
        ],
      );
    }).toList();

    // Outbounds: Always ordered with '代理' on top and '直连' below!
    final outbounds = [
      ConnectionAggOutbound(name: '代理', count: math.max(1, totalProxy)),
      ConnectionAggOutbound(name: '直连', count: math.max(1, totalDirect)),
    ];

    final aggregate = ConnectionsAggregate(
      total: totalProxy + totalDirect,
      hosts: hosts,
      outbounds: outbounds,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(aggregate: aggregate);
  }

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Toggle outbound filter:
  /// - clicking '直连' shows only direct domains
  /// - clicking '代理' (the node above) shows only proxy domains
  /// - clicking again or empty space restores all
  void toggleOutboundFilter(String outboundName) {
    if (state.activeOutboundFilter == outboundName) {
      state = state.copyWith(clearOutboundFilter: true);
    } else {
      state = state.copyWith(activeOutboundFilter: outboundName);
    }
  }

  void clearFilterAndHover() {
    state = state.copyWith(
      clearOutboundFilter: true,
      clearHover: true,
    );
  }

  void setHover({
    TopoNode? node,
    TopoLink? link,
    String? tooltipText,
    Offset? tooltipPosition,
  }) {
    state = state.copyWith(
      hoveredNode: node,
      hoveredLink: link,
      tooltipText: tooltipText,
      tooltipPosition: tooltipPosition,
    );
  }

  void clearHover() {
    state = state.copyWith(clearHover: true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logSubscription?.cancel();
    _dio.close();
    super.dispose();
  }
}

class _ParsedLog {
  final String host;
  final String outbound;

  _ParsedLog({required this.host, required this.outbound});
}
