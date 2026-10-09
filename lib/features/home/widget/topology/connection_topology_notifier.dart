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
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/singbox/service/singbox_service_provider.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class _VisitedSite {
  final String name;
  int count;
  int uploadBytes;
  int downloadBytes;
  int uploadSpeed; // bytes/s
  int downloadSpeed; // bytes/s
  double activityFactor; // 0.0 to 1.0
  String outbound; // '代理' or '直连'
  DateTime lastSeen;
  bool isCurrentlyActive;

  _VisitedSite({
    required this.name,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.activityFactor = 0.0,
    required this.outbound,
    required this.lastSeen,
    this.isCurrentlyActive = false,
  }) : count = 1;
}

class _ConnSnapshot {
  final String connId;
  final String host;
  final String outbound;
  int lastUpload;
  int lastDownload;
  DateTime lastPollTime;

  _ConnSnapshot({
    required this.connId,
    required this.host,
    required this.outbound,
    required this.lastUpload,
    required this.lastDownload,
    required this.lastPollTime,
  });
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

  bool _isPolling = false;
  String? _cachedController;
  String? _cachedSecret;
  DateTime _lastConfigCheck = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, _VisitedSite> _visitedSites = {};
  final Map<String, _ConnSnapshot> _connSnapshots = {};
  final Set<String> _seenConnectionIds = <String>{};
  final Set<int> _processedLogLines = <int>{};
  final Map<String, String> _dnsCache = <String, String>{};
  String? _recentHost;

  int _proxyTotalUpload = 0;
  int _proxyTotalDownload = 0;
  int _directTotalUpload = 0;
  int _directTotalDownload = 0;

  int _proxyUploadSpeed = 0;
  int _proxyDownloadSpeed = 0;
  int _directUploadSpeed = 0;
  int _directDownloadSpeed = 0;

  int _lastGlobalDownlinkTotal = 0;
  int _lastGlobalUplinkTotal = 0;

  ConnectionTopologyNotifier(this._ref)
      : super(ConnectionTopologyState(aggregate: ConnectionsAggregate.empty())) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: 1500),
        receiveTimeout: const Duration(milliseconds: 1500),
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
    // Poll every 800ms to balance responsiveness and system resource usage
    _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
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
      final lineHash = line.hashCode;
      if (_processedLogLines.contains(lineHash)) continue;

      _processedLogLines.add(lineHash);
      if (_processedLogLines.length > 5000) {
        _processedLogLines.clear();
      }

      final parsed = _parseLogLine(line);
      if (parsed != null) {
        _recordTarget(parsed.host, parsed.outbound, 0, 0, isNew: true, isActive: true);
        hasNewActivity = true;
      }
    }

    if (hasNewActivity || state.aggregate.hosts.length != _visitedSites.length) {
      _rebuildAggregate();
    }
  }

  Future<void> _pollActiveConnections() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      final connStatus = _ref.read(connectionNotifierProvider).valueOrNull;
      final isConnected = connStatus is Connected;
      final isConnecting = connStatus is Connecting;

      if (!isConnected && !isConnecting) {
        if (state.aggregate.total > 0 || _visitedSites.isNotEmpty) {
          _visitedSites.clear();
          _seenConnectionIds.clear();
          _connSnapshots.clear();
          _processedLogLines.clear();
          _proxyTotalUpload = 0;
          _proxyTotalDownload = 0;
          _directTotalUpload = 0;
          _directTotalDownload = 0;
          _proxyUploadSpeed = 0;
          _proxyDownloadSpeed = 0;
          _directUploadSpeed = 0;
          _directDownloadSpeed = 0;
          state = state.copyWith(aggregate: ConnectionsAggregate.empty());
        }
        return;
      }

      if (_logSubscription == null) {
        _subscribeToLogs();
      }

      final dirs = _ref.read(appDirectoriesProvider).valueOrNull;
      if (dirs == null) return;

      // Reset currently active flags before evaluating active connections
      for (final s in _visitedSites.values) {
        s.isCurrentlyActive = false;
      }

      bool hasClashSuccess = false;
      final now = DateTime.now();

      // Cache Clash API credentials: read asynchronously at most once every 5 seconds
      if (_cachedController == null || now.difference(_lastConfigCheck).inSeconds >= 5) {
        _lastConfigCheck = now;
        final configFile = File(p.join(dirs.workingDir.path, 'current-config.json'));
        if (await configFile.exists()) {
          try {
            final raw = await configFile.readAsString();
            final configJson = jsonDecode(raw) as Map<String, dynamic>;
            final exp = configJson['experimental'] as Map<String, dynamic>?;
            final clashApi = exp?['clash_api'] as Map<String, dynamic>?;
            if (clashApi != null) {
              _cachedController = clashApi['external_controller'] as String? ?? '127.0.0.1:16756';
              _cachedSecret = clashApi['secret'] as String? ?? '';
            }
          } catch (_) {}
        }
      }

      final controller = _cachedController;
      final secret = _cachedSecret ?? '';

      if (controller != null && controller.isNotEmpty) {
        try {
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
            hasClashSuccess = true;
            final connections = response.data!['connections'] as List?;
            if (connections != null) {
              final currentIds = <String>{};
              int pUpSpeed = 0;
              int pDownSpeed = 0;
              int dUpSpeed = 0;
              int dDownSpeed = 0;
              final hostSpeedUp = <String, int>{};
              final hostSpeedDown = <String, int>{};

              for (final raw in connections) {
                if (raw is! Map<String, dynamic>) continue;
                final meta = raw['metadata'] as Map<String, dynamic>?;
                if (meta == null) continue;

                final connId = raw['id']?.toString() ?? '';
                if (connId.isNotEmpty) {
                  currentIds.add(connId);
                }

                final rawHost = (meta['host'] as String? ?? '').trim();
                final rawIp = (meta['destinationIP'] as String? ?? '').trim();
                final destPort = meta['destinationPort']?.toString() ?? '';

                if (destPort == '53') continue;
                if (rawIp == '172.19.0.2' || rawIp == '127.0.0.1') continue;

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

                final isNewConn = connId.isNotEmpty && !_connSnapshots.containsKey(connId);
                final prevSnapshot = _connSnapshots[connId];

                int deltaUp = 0;
                int deltaDown = 0;
                double dtSec = 0.8;

                if (prevSnapshot != null) {
                  deltaUp = math.max(0, up - prevSnapshot.lastUpload);
                  deltaDown = math.max(0, down - prevSnapshot.lastDownload);
                  dtSec = math.max(0.1, now.difference(prevSnapshot.lastPollTime).inMilliseconds / 1000.0);
                  prevSnapshot.lastUpload = up;
                  prevSnapshot.lastDownload = down;
                  prevSnapshot.lastPollTime = now;
                } else if (connId.isNotEmpty) {
                  deltaUp = up;
                  deltaDown = down;
                  _connSnapshots[connId] = _ConnSnapshot(
                    connId: connId,
                    host: target,
                    outbound: outbound,
                    lastUpload: up,
                    lastDownload: down,
                    lastPollTime: now,
                  );
                }

                final cUpSpeed = (deltaUp / dtSec).round();
                final cDownSpeed = (deltaDown / dtSec).round();

                if (isDirect) {
                  _directTotalUpload += deltaUp;
                  _directTotalDownload += deltaDown;
                  dUpSpeed += cUpSpeed;
                  dDownSpeed += cDownSpeed;
                } else {
                  _proxyTotalUpload += deltaUp;
                  _proxyTotalDownload += deltaDown;
                  pUpSpeed += cUpSpeed;
                  pDownSpeed += cDownSpeed;
                }

                final cleanT = _cleanTargetName(target);
                if (cleanT.isNotEmpty) {
                  hostSpeedUp[cleanT] = (hostSpeedUp[cleanT] ?? 0) + cUpSpeed;
                  hostSpeedDown[cleanT] = (hostSpeedDown[cleanT] ?? 0) + cDownSpeed;
                }

                _recordTarget(
                  target,
                  outbound,
                  deltaUp,
                  deltaDown,
                  isActive: true,
                  isNew: isNewConn,
                );
              }

              // Clean up closed connections
              _connSnapshots.removeWhere((id, _) => !currentIds.contains(id));

              _proxyUploadSpeed = pUpSpeed;
              _proxyDownloadSpeed = pDownSpeed;
              _directUploadSpeed = dUpSpeed;
              _directDownloadSpeed = dDownSpeed;

              // Update host speeds and smooth activityFactor
              for (final s in _visitedSites.values) {
                final upSpd = hostSpeedUp[s.name] ?? 0;
                final downSpd = hostSpeedDown[s.name] ?? 0;
                final totalSpd = upSpd + downSpd;
                s.uploadSpeed = upSpd;
                s.downloadSpeed = downSpd;

                if (totalSpd > 0) {
                  final kb = totalSpd / 1024.0;
                  final targetAct = (math.log(math.max(1.0, kb)) / math.log(3072.0)).clamp(0.18, 1.0);
                  s.activityFactor = math.max(targetAct, s.activityFactor * 0.80);
                } else {
                  s.activityFactor = s.activityFactor * 0.70;
                  if (s.activityFactor < 0.05) s.activityFactor = 0.0;
                }
              }
            }
          }
        } catch (_) {
          // Clash API poll skipped
        }
      }

      // Fallback: If Clash API is not responding or on Android log mode,
      // use Riverpod statsNotifierProvider for global speed & byte delta
      if (!hasClashSuccess) {
        final stats = _ref.read(statsNotifierProvider).asData?.value;
        if (stats != null) {
          final gDown = stats.downlink;
          final gUp = stats.uplink;
          final gDownTotal = stats.downlinkTotal;
          final gUpTotal = stats.uplinkTotal;

          final deltaDownTotal = _lastGlobalDownlinkTotal > 0 ? math.max(0, gDownTotal - _lastGlobalDownlinkTotal) : 0;
          final deltaUpTotal = _lastGlobalUplinkTotal > 0 ? math.max(0, gUpTotal - _lastGlobalUplinkTotal) : 0;
          _lastGlobalDownlinkTotal = gDownTotal;
          _lastGlobalUplinkTotal = gUpTotal;

          final activeDirect = _visitedSites.values.where((s) => s.outbound == '直连' && (s.isCurrentlyActive || s.name == _recentHost)).toList();
          final activeProxy = _visitedSites.values.where((s) => s.outbound == '代理' && (s.isCurrentlyActive || s.name == _recentHost)).toList();

          if (activeDirect.isNotEmpty && activeProxy.isEmpty) {
            _directDownloadSpeed = gDown;
            _directUploadSpeed = gUp;
            _directTotalDownload += deltaDownTotal;
            _directTotalUpload += deltaUpTotal;
            _proxyDownloadSpeed = 0;
            _proxyUploadSpeed = 0;
            for (final s in activeDirect) {
              s.downloadSpeed = (gDown / activeDirect.length).round();
              s.uploadSpeed = (gUp / activeDirect.length).round();
              final kb = (s.downloadSpeed + s.uploadSpeed) / 1024.0;
              s.activityFactor = (math.log(math.max(1.0, kb)) / math.log(3072.0)).clamp(0.18, 1.0);
            }
          } else if (activeProxy.isNotEmpty && activeDirect.isEmpty) {
            _proxyDownloadSpeed = gDown;
            _proxyUploadSpeed = gUp;
            _proxyTotalDownload += deltaDownTotal;
            _proxyTotalUpload += deltaUpTotal;
            _directDownloadSpeed = 0;
            _directUploadSpeed = 0;
            for (final s in activeProxy) {
              s.downloadSpeed = (gDown / activeProxy.length).round();
              s.uploadSpeed = (gUp / activeProxy.length).round();
              final kb = (s.downloadSpeed + s.uploadSpeed) / 1024.0;
              s.activityFactor = (math.log(math.max(1.0, kb)) / math.log(3072.0)).clamp(0.18, 1.0);
            }
          } else if (activeProxy.isNotEmpty && activeDirect.isNotEmpty) {
            final pRatio = activeProxy.length / (activeProxy.length + activeDirect.length);
            _proxyDownloadSpeed = (gDown * pRatio).round();
            _proxyUploadSpeed = (gUp * pRatio).round();
            _directDownloadSpeed = gDown - _proxyDownloadSpeed;
            _directUploadSpeed = gUp - _proxyUploadSpeed;
            _proxyTotalDownload += (deltaDownTotal * pRatio).round();
            _proxyTotalUpload += (deltaUpTotal * pRatio).round();
            _directTotalDownload += deltaDownTotal - (deltaDownTotal * pRatio).round();
            _directTotalUpload += deltaUpTotal - (deltaUpTotal * pRatio).round();
          }
        }
      }

      _rebuildAggregate();
    } finally {
      _isPolling = false;
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

  String _cleanTargetName(String target) {
    var cleanTarget = target.toLowerCase().trim();
    final colonIdx = cleanTarget.lastIndexOf(':');
    if (colonIdx > 0 && !cleanTarget.contains(']')) {
      cleanTarget = cleanTarget.substring(0, colonIdx);
    }
    if (cleanTarget.startsWith('[') && cleanTarget.endsWith(']')) {
      cleanTarget = cleanTarget.substring(1, cleanTarget.length - 1);
    }
    if (_dnsCache.containsKey(cleanTarget)) {
      cleanTarget = _dnsCache[cleanTarget]!;
    }
    return cleanTarget;
  }

  void _recordTarget(
    String target,
    String outbound,
    int deltaUp,
    int deltaDown, {
    bool isActive = false,
    bool isNew = false,
  }) {
    final cleanTarget = _cleanTargetName(target);

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
      existing.uploadBytes += deltaUp;
      existing.downloadBytes += deltaDown;
      existing.outbound = outbound;
      if (isActive) {
        existing.isCurrentlyActive = true;
      }
    } else {
      _recentHost = cleanTarget;
      _visitedSites[cleanTarget] = _VisitedSite(
        name: cleanTarget,
        uploadBytes: deltaUp,
        downloadBytes: deltaDown,
        outbound: outbound,
        lastSeen: DateTime.now(),
        isCurrentlyActive: isActive,
      );
    }
  }

  _ParsedLog? _parseLogLine(String line) {
    if (line.contains('127.0.0.1') || line.contains('::1')) return null;

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
        speed: site.uploadSpeed + site.downloadSpeed,
        uploadBytes: site.uploadBytes,
        downloadBytes: site.downloadBytes,
        activity: site.activityFactor,
        flows: [
          ConnectionAggFlow(outbound: site.outbound, count: site.count),
        ],
      );
    }).toList();

    final outbounds = [
      ConnectionAggOutbound(
        name: '代理',
        count: math.max(1, totalProxy),
        uploadSpeed: _proxyUploadSpeed,
        downloadSpeed: _proxyDownloadSpeed,
        uploadBytes: _proxyTotalUpload,
        downloadBytes: _proxyTotalDownload,
      ),
      ConnectionAggOutbound(
        name: '直连',
        count: math.max(1, totalDirect),
        uploadSpeed: _directUploadSpeed,
        downloadSpeed: _directDownloadSpeed,
        uploadBytes: _directTotalUpload,
        downloadBytes: _directTotalDownload,
      ),
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
