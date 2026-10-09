import 'dart:math' as math;
import 'package:flutter/material.dart';

const String topologyOthersKey = '__others__';

enum TopoNodeType {
  source,
  host,
  outbound,
}

class TopoNode {
  final String id;
  final String name;
  final TopoNodeType type;
  final int value;
  final double x;
  final double y;
  final double width;
  final double height;
  final Color color;
  final bool isOthers;
  final bool recent;
  final String zone; // 'proxy' or 'direct'

  const TopoNode({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.color,
    this.isOthers = false,
    this.recent = false,
    required this.zone,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Rect hitBox() {
    if (type == TopoNodeType.host) {
      return Rect.fromLTWH(x - 4, y - 2, width + 8, height + 4);
    }
    const minH = 22.0;
    const gap = 10.0;
    final maxH = height + gap - 2.0;
    final h = math.min(math.max(height, minH), math.max(maxH, height));
    final centerY = y + height / 2;
    final towardLeft = type != TopoNodeType.outbound;
    const reach = 100.0;

    return Rect.fromLTWH(
      towardLeft ? x - reach : x - 10.0,
      centerY - h / 2,
      reach + width + 20.0,
      h,
    );
  }
}

class TopoLink {
  final String id;
  final String source;
  final String target;
  final int value;
  final Path path;
  final double sourceX;
  final double sourceY;
  final double targetX;
  final double targetY;
  final double heightSource;
  final double heightTarget;
  final Color sourceColor;
  final Color targetColor;
  final String zone; // 'proxy' or 'direct'
  final int speed; // bytes/s
  final double activity; // 0.0 to 1.0

  const TopoLink({
    required this.id,
    required this.source,
    required this.target,
    required this.value,
    required this.path,
    this.sourceX = 0.0,
    required this.sourceY,
    this.targetX = 0.0,
    required this.targetY,
    required this.heightSource,
    required this.heightTarget,
    required this.sourceColor,
    required this.targetColor,
    required this.zone,
    this.speed = 0,
    this.activity = 0.0,
  });
}

class ConnectionAggFlow {
  final String outbound;
  final int count;

  const ConnectionAggFlow({
    required this.outbound,
    required this.count,
  });
}

class ConnectionAggHost {
  final String name;
  final int count;
  final List<ConnectionAggFlow> flows;
  final bool recent;
  final int speed; // bytes/s
  final int uploadBytes;
  final int downloadBytes;
  final double activity; // 0.0 to 1.0

  const ConnectionAggHost({
    required this.name,
    required this.count,
    required this.flows,
    this.recent = false,
    this.speed = 0,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.activity = 0.0,
  });
}

class ConnectionAggOutbound {
  final String name;
  final int count;
  final int uploadSpeed; // bytes/s
  final int downloadSpeed; // bytes/s
  final int uploadBytes; // cumulative bytes
  final int downloadBytes; // cumulative bytes

  const ConnectionAggOutbound({
    required this.name,
    required this.count,
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
  });
}

class ConnectionsAggregate {
  final int total;
  final List<ConnectionAggHost> hosts;
  final List<ConnectionAggOutbound> outbounds;
  final DateTime timestamp;

  const ConnectionsAggregate({
    required this.total,
    required this.hosts,
    required this.outbounds,
    required this.timestamp,
  });

  factory ConnectionsAggregate.empty() => ConnectionsAggregate(
        total: 0,
        hosts: const [],
        outbounds: const [],
        timestamp: DateTime.now(),
      );
}

class TopoLayoutResult {
  final List<TopoNode> nodes;
  final List<TopoLink> links;
  final double dividerY;
  final int proxyHostCount;
  final int directHostCount;
  final String? expandedZone;
  final ConnectionAggOutbound? proxyOutbound;
  final ConnectionAggOutbound? directOutbound;

  const TopoLayoutResult({
    required this.nodes,
    required this.links,
    this.dividerY = 0.0,
    this.proxyHostCount = 0,
    this.directHostCount = 0,
    this.expandedZone,
    this.proxyOutbound,
    this.directOutbound,
  });

  static const empty = TopoLayoutResult(nodes: [], links: []);
}

// Layout geometry constants
const double nodeWidth = 8.0;
const double nodeGap = 10.0;
const double padTop = 26.0;
const double padBottom = 16.0;
const double colXSource = 0.12;
const double colXHost = 0.50;
const double colXOutbound = 0.86;

const double barHeightMax = 32.0;
const double minBarHeight = 3.0;

Path getSankeyPath(
  double x0,
  double y0,
  double x1,
  double y1,
  double h0,
  double h1,
) {
  final xi = (x0 + x1) / 2;
  final path = Path();
  path.moveTo(x0, y0);
  path.cubicTo(xi, y0, xi, y1, x1, y1);
  path.lineTo(x1, y1 + h1);
  path.cubicTo(xi, y1 + h1, xi, y0 + h0, x0, y0 + h0);
  path.close();
  return path;
}

double scaledBarHeight(int value, double scale) {
  return math.min(barHeightMax, math.max(minBarHeight, value * scale));
}

Set<String> collectLinkedIds(List<TopoLink> links, List<String> focusNodes) {
  final set = Set<String>.from(focusNodes);
  if (focusNodes.isEmpty) return set;

  Set<String> walk(bool forward) {
    final acc = Set<String>.from(focusNodes);
    bool changed = true;
    while (changed) {
      changed = false;
      for (final l in links) {
        final from = forward ? l.source : l.target;
        final to = forward ? l.target : l.source;
        if (acc.contains(from) && !acc.contains(to)) {
          acc.add(to);
          changed = true;
        }
      }
    }
    return acc;
  }

  final pathNodes = {...walk(false), ...walk(true)};
  set.addAll(pathNodes);

  for (final l in links) {
    if (pathNodes.contains(l.source) && pathNodes.contains(l.target)) {
      set.add(l.id);
    }
  }
  return set;
}

List<String> matchNodeIds(List<TopoNode> nodes, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return nodes
      .where((n) => n.type != TopoNodeType.source && n.name.toLowerCase().contains(q))
      .map((n) => n.id)
      .toList();
}

TopoLayoutResult computeTopologyLayout({
  required ConnectionsAggregate aggregate,
  required double width,
  required double height,
  required String sourceLabel,
  required String othersLabel,
  required Color primaryColor,
  required bool isDark,
  String? filterOutbound,
  String? expandedZone,
}) {
  if (aggregate.hosts.isEmpty || width <= 50 || height <= 50) {
    return TopoLayoutResult.empty;
  }

  final colorSource = isDark ? const Color(0xFF00E5FF) : const Color(0xFF00838F);
  final colorProxy = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
  final colorDirect = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
  final colorProxyHost = isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6);
  final colorDirectHost = isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);

  ConnectionAggOutbound? proxyOutbound;
  ConnectionAggOutbound? directOutbound;
  for (final o in aggregate.outbounds) {
    if (o.name == '代理') proxyOutbound = o;
    if (o.name == '直连') directOutbound = o;
  }

  // 1. Classify hosts into Proxy and Direct
  final rawProxyHosts = <ConnectionAggHost>[];
  final rawDirectHosts = <ConnectionAggHost>[];

  for (final h in aggregate.hosts) {
    int pVal = 0;
    int dVal = 0;
    for (final f in h.flows) {
      if (f.outbound == '代理') {
        pVal += f.count;
      } else {
        dVal += f.count;
      }
    }
    if (pVal > 0 && dVal == 0) {
      rawProxyHosts.add(h);
    } else if (dVal > 0 && pVal == 0) {
      rawDirectHosts.add(h);
    } else if (pVal >= dVal) {
      rawProxyHosts.add(h);
    } else {
      rawDirectHosts.add(h);
    }
  }

  // Filter if filterOutbound is active
  if (filterOutbound == '代理' || expandedZone == 'proxy') {
    rawDirectHosts.clear();
  } else if (filterOutbound == '直连' || expandedZone == 'direct') {
    rawProxyHosts.clear();
  }

  final nodes = <TopoNode>[];
  final links = <TopoLink>[];

  final isExpandedProxy = expandedZone == 'proxy';
  final isExpandedDirect = expandedZone == 'direct';
  final isExpanded = isExpandedProxy || isExpandedDirect;

  final dividerY = isExpanded ? 0.0 : height * 0.5;

  // Geometry for centered domain pills
  final hostPillWidth = math.min(130.0, math.max(90.0, width * 0.28));
  const hostPillHeight = 16.0;
  final hostX = (width * colXHost) - (hostPillWidth / 2);
  const hostGap = 4.0;

  // Upper section (代理 / Proxy Zone)
  const double upperTop = padTop + 10.0;
  final double upperBottom = isExpandedProxy ? (height - padBottom - 8.0) : (dividerY - 14.0);
  final upperCenterY = (upperTop + upperBottom) / 2;
  final upperH = math.max(20.0, upperBottom - upperTop);

  // Lower section (直连 / Direct Zone)
  final double lowerTop = isExpandedDirect ? (padTop + 10.0) : (dividerY + 22.0);
  final double lowerBottom = height - padBottom - 6.0;
  final lowerCenterY = (lowerTop + lowerBottom) / 2;
  final lowerH = math.max(20.0, lowerBottom - lowerTop);

  // --- Determine Display Host Capacity strictly based on available space ---
  final int maxProxy = (upperH / (hostPillHeight + hostGap)).floor().clamp(1, isExpandedProxy ? 25 : 14);
  final int maxDirect = (lowerH / (hostPillHeight + hostGap)).floor().clamp(1, isExpandedDirect ? 25 : 14);

  final proxyDisplayHosts = isExpandedDirect ? <ConnectionAggHost>[] : rawProxyHosts.take(maxProxy).toList();
  final directDisplayHosts = isExpandedProxy ? <ConnectionAggHost>[] : rawDirectHosts.take(maxDirect).toList();

  // --- Build Upper Section (代理) ---
  if (!isExpandedDirect && (proxyDisplayHosts.isNotEmpty || filterOutbound != '直连')) {
    final proxyTotal = proxyDisplayHosts.fold<int>(0, (acc, h) => acc + h.count);
    final pSourceBarH = isExpandedProxy ? 64.0 : 36.0;
    final pSourceY = upperCenterY - pSourceBarH / 2;
    final pSource = TopoNode(
      id: 'source_proxy',
      name: sourceLabel,
      type: TopoNodeType.source,
      value: proxyTotal > 0 ? proxyTotal : 1,
      x: width * colXSource - nodeWidth / 2,
      y: pSourceY,
      width: nodeWidth,
      height: pSourceBarH,
      color: colorSource,
      zone: 'proxy',
    );
    nodes.add(pSource);

    final pOutboundY = upperCenterY - pSourceBarH / 2;
    final pOutbound = TopoNode(
      id: 'outbound_proxy',
      name: '代理',
      type: TopoNodeType.outbound,
      value: proxyTotal > 0 ? proxyTotal : 1,
      x: width * colXOutbound - nodeWidth / 2,
      y: pOutboundY,
      width: nodeWidth,
      height: pSourceBarH,
      color: colorProxy,
      zone: 'proxy',
    );
    nodes.add(pOutbound);

    if (proxyDisplayHosts.isNotEmpty) {
      final pTotalBarsH = proxyDisplayHosts.length * hostPillHeight +
          math.max(0, proxyDisplayHosts.length - 1) * hostGap;
      var pCursor = upperCenterY - pTotalBarsH / 2;
      if (pCursor + pTotalBarsH > upperBottom) {
        pCursor = upperBottom - pTotalBarsH;
      }
      if (pCursor < upperTop) {
        pCursor = upperTop;
      }

      for (final h in proxyDisplayHosts) {
        final hostNode = TopoNode(
          id: 'host_${h.name}',
          name: h.name,
          type: TopoNodeType.host,
          value: h.count,
          x: hostX,
          y: pCursor,
          width: hostPillWidth,
          height: hostPillHeight,
          color: colorProxyHost,
          recent: h.recent,
          zone: 'proxy',
        );
        nodes.add(hostNode);

        // Link from pSource -> host (enters left edge of host pill)
        final linkSourceH = math.max(3.0, pSourceBarH / proxyDisplayHosts.length);
        final linkTargetH = math.min(10.0, hostPillHeight - 4.0);
        final sX = pSource.x + pSource.width;
        final sY = pSource.y + (hostNode.y - pSource.y).clamp(0.0, pSourceBarH - linkSourceH);
        final tX = hostNode.x;
        final tY = hostNode.y + (hostNode.height - linkTargetH) / 2;

        links.add(
          TopoLink(
            id: '${pSource.id}|${hostNode.id}',
            source: pSource.id,
            target: hostNode.id,
            value: h.count,
            sourceX: sX,
            sourceY: sY,
            targetX: tX,
            targetY: tY,
            heightSource: linkSourceH,
            heightTarget: linkTargetH,
            sourceColor: colorSource,
            targetColor: colorProxyHost,
            path: getSankeyPath(sX, sY, tX, tY, linkSourceH, linkTargetH),
            zone: 'proxy',
            speed: h.speed,
            activity: h.activity,
          ),
        );

        // Link from host -> pOutbound (exits right edge of host pill)
        final linkOutboundH = math.max(3.0, pSourceBarH / proxyDisplayHosts.length);
        final oSX = hostNode.x + hostNode.width;
        final oSY = hostNode.y + (hostNode.height - linkTargetH) / 2;
        final oTX = pOutbound.x;
        final oTY = pOutbound.y + (hostNode.y - pOutbound.y).clamp(0.0, pSourceBarH - linkOutboundH);

        links.add(
          TopoLink(
            id: '${hostNode.id}|${pOutbound.id}',
            source: hostNode.id,
            target: pOutbound.id,
            value: h.count,
            sourceX: oSX,
            sourceY: oSY,
            targetX: oTX,
            targetY: oTY,
            heightSource: linkTargetH,
            heightTarget: linkOutboundH,
            sourceColor: colorProxyHost,
            targetColor: colorProxy,
            path: getSankeyPath(oSX, oSY, oTX, oTY, linkTargetH, linkOutboundH),
            zone: 'proxy',
            speed: h.speed,
            activity: h.activity,
          ),
        );

        pCursor += hostPillHeight + hostGap;
      }
    }
  }

  // --- Build Lower Section (直连) ---
  if (!isExpandedProxy && (directDisplayHosts.isNotEmpty || filterOutbound != '代理')) {
    final directTotal = directDisplayHosts.fold<int>(0, (acc, h) => acc + h.count);
    final dSourceBarH = isExpandedDirect ? 64.0 : 36.0;
    final dSourceY = lowerCenterY - dSourceBarH / 2;
    final dSource = TopoNode(
      id: 'source_direct',
      name: sourceLabel,
      type: TopoNodeType.source,
      value: directTotal > 0 ? directTotal : 1,
      x: width * colXSource - nodeWidth / 2,
      y: dSourceY,
      width: nodeWidth,
      height: dSourceBarH,
      color: colorSource,
      zone: 'direct',
    );
    nodes.add(dSource);

    final dOutboundY = lowerCenterY - dSourceBarH / 2;
    final dOutbound = TopoNode(
      id: 'outbound_direct',
      name: '直连',
      type: TopoNodeType.outbound,
      value: directTotal > 0 ? directTotal : 1,
      x: width * colXOutbound - nodeWidth / 2,
      y: dOutboundY,
      width: nodeWidth,
      height: dSourceBarH,
      color: colorDirect,
      zone: 'direct',
    );
    nodes.add(dOutbound);

    if (directDisplayHosts.isNotEmpty) {
      final dTotalBarsH = directDisplayHosts.length * hostPillHeight +
          math.max(0, directDisplayHosts.length - 1) * hostGap;
      var dCursor = lowerCenterY - dTotalBarsH / 2;
      if (dCursor < lowerTop) {
        dCursor = lowerTop;
      }
      if (dCursor + dTotalBarsH > lowerBottom) {
        dCursor = lowerBottom - dTotalBarsH;
      }

      for (final h in directDisplayHosts) {
        final hostNode = TopoNode(
          id: 'host_${h.name}',
          name: h.name,
          type: TopoNodeType.host,
          value: h.count,
          x: hostX,
          y: dCursor,
          width: hostPillWidth,
          height: hostPillHeight,
          color: colorDirectHost,
          recent: h.recent,
          zone: 'direct',
        );
        nodes.add(hostNode);

        // Link from dSource -> host
        final linkSourceH = math.max(3.0, dSourceBarH / directDisplayHosts.length);
        final linkTargetH = math.min(10.0, hostPillHeight - 4.0);
        final sX = dSource.x + dSource.width;
        final sY = dSource.y + (hostNode.y - dSource.y).clamp(0.0, dSourceBarH - linkSourceH);
        final tX = hostNode.x;
        final tY = hostNode.y + (hostNode.height - linkTargetH) / 2;

        links.add(
          TopoLink(
            id: '${dSource.id}|${hostNode.id}',
            source: dSource.id,
            target: hostNode.id,
            value: h.count,
            sourceX: sX,
            sourceY: sY,
            targetX: tX,
            targetY: tY,
            heightSource: linkSourceH,
            heightTarget: linkTargetH,
            sourceColor: colorSource,
            targetColor: colorDirectHost,
            path: getSankeyPath(sX, sY, tX, tY, linkSourceH, linkTargetH),
            zone: 'direct',
            speed: h.speed,
            activity: h.activity,
          ),
        );

        // Link from host -> dOutbound
        final linkOutboundH = math.max(3.0, dSourceBarH / directDisplayHosts.length);
        final oSX = hostNode.x + hostNode.width;
        final oSY = hostNode.y + (hostNode.height - linkTargetH) / 2;
        final oTX = dOutbound.x;
        final oTY = dOutbound.y + (hostNode.y - dOutbound.y).clamp(0.0, dSourceBarH - linkOutboundH);

        links.add(
          TopoLink(
            id: '${hostNode.id}|${dOutbound.id}',
            source: hostNode.id,
            target: dOutbound.id,
            value: h.count,
            sourceX: oSX,
            sourceY: oSY,
            targetX: oTX,
            targetY: oTY,
            heightSource: linkTargetH,
            heightTarget: linkOutboundH,
            sourceColor: colorDirectHost,
            targetColor: colorDirect,
            path: getSankeyPath(oSX, oSY, oTX, oTY, linkTargetH, linkOutboundH),
            zone: 'direct',
            speed: h.speed,
            activity: h.activity,
          ),
        );

        dCursor += hostPillHeight + hostGap;
      }
    }
  }

  return TopoLayoutResult(
    nodes: nodes,
    links: links,
    dividerY: dividerY,
    proxyHostCount: proxyDisplayHosts.length,
    directHostCount: directDisplayHosts.length,
    expandedZone: expandedZone,
    proxyOutbound: proxyOutbound,
    directOutbound: directOutbound,
  );
}
