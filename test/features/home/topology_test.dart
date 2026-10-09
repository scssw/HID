import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_model.dart';

void main() {
  group('ConnectionTopology Layout & Algorithm Tests', () {
    test('computeTopologyLayout calculates 3 columns and valid bezier links', () {
      final aggregate = ConnectionsAggregate(
        total: 18,
        hosts: [
          const ConnectionAggHost(
            name: 'google.com',
            count: 10,
            recent: true,
            flows: [
              ConnectionAggFlow(outbound: '代理', count: 8),
              ConnectionAggFlow(outbound: '直连', count: 2),
            ],
          ),
          const ConnectionAggHost(
            name: 'bilibili.com',
            count: 8,
            flows: [
              ConnectionAggFlow(outbound: '直连', count: 8),
            ],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 8),
          ConnectionAggOutbound(name: '直连', count: 10),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: 400,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      // Verify source node exists
      expect(layout.nodes.any((n) => n.type == TopoNodeType.source), isTrue);
      final source = layout.nodes.firstWhere((n) => n.type == TopoNodeType.source);
      expect(source.name, '本机设备');

      // Verify host nodes exist
      final hosts = layout.nodes.where((n) => n.type == TopoNodeType.host).toList();
      expect(hosts.length, 2);
      expect(hosts.any((h) => h.name == 'google.com' && h.recent), isTrue);
      expect(hosts.any((h) => h.name == 'bilibili.com'), isTrue);

      // Verify outbound nodes exist: 代理 and 直连
      final outbounds = layout.nodes.where((n) => n.type == TopoNodeType.outbound).toList();
      expect(outbounds.length, 2);
      expect(outbounds.any((o) => o.name == '代理'), isTrue);
      expect(outbounds.any((o) => o.name == '直连'), isTrue);

      // Verify links
      expect(layout.links.isNotEmpty, isTrue);
      expect(layout.links.any((l) => l.source == 'source_proxy' && l.target == 'host_google.com'), isTrue);
      expect(layout.links.any((l) => l.source == 'source_direct' && l.target == 'host_bilibili.com'), isTrue);
      expect(layout.links.any((l) => l.source == 'host_google.com' && l.target == 'outbound_proxy'), isTrue);
      expect(layout.links.any((l) => l.source == 'host_bilibili.com' && l.target == 'outbound_direct'), isTrue);
    });

    test('computeTopologyLayout with filterOutbound filters to only direct or proxy domains', () {
      final aggregate = ConnectionsAggregate(
        total: 18,
        hosts: [
          const ConnectionAggHost(
            name: 'google.com',
            count: 10,
            flows: [
              ConnectionAggFlow(outbound: '代理', count: 10),
            ],
          ),
          const ConnectionAggHost(
            name: 'bilibili.com',
            count: 8,
            flows: [
              ConnectionAggFlow(outbound: '直连', count: 8),
            ],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 10),
          ConnectionAggOutbound(name: '直连', count: 8),
        ],
        timestamp: DateTime.now(),
      );

      // Filter by '直连'
      final directLayout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: 400,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
        filterOutbound: '直连',
      );

      final directHosts = directLayout.nodes.where((n) => n.type == TopoNodeType.host).toList();
      expect(directHosts.length, 1);
      expect(directHosts.first.name, 'bilibili.com');
      final directOutbounds = directLayout.nodes.where((n) => n.type == TopoNodeType.outbound).toList();
      expect(directOutbounds.length, 1);
      expect(directOutbounds.first.name, '直连');

      // Filter by '代理'
      final proxyLayout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: 400,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
        filterOutbound: '代理',
      );

      final proxyHosts = proxyLayout.nodes.where((n) => n.type == TopoNodeType.host).toList();
      expect(proxyHosts.length, 1);
      expect(proxyHosts.first.name, 'google.com');
      final proxyOutbounds = proxyLayout.nodes.where((n) => n.type == TopoNodeType.outbound).toList();
      expect(proxyOutbounds.length, 1);
      expect(proxyOutbounds.first.name, '代理');
    });

    test('collectLinkedIds performs bidirectional BFS path traversal', () {
      final links = <TopoLink>[
        TopoLink(
          id: 'source|mid-a',
          source: 'source',
          target: 'mid-a',
          value: 5,
          path: Path(),
          sourceY: 0,
          targetY: 0,
          heightSource: 10,
          heightTarget: 10,
          sourceColor: Colors.blue,
          targetColor: Colors.purple,
          zone: 'proxy',
        ),
        TopoLink(
          id: 'mid-a|out-proxy',
          source: 'mid-a',
          target: 'out-proxy',
          value: 5,
          path: Path(),
          sourceY: 0,
          targetY: 0,
          heightSource: 10,
          heightTarget: 10,
          sourceColor: Colors.purple,
          targetColor: Colors.indigo,
          zone: 'proxy',
        ),
        TopoLink(
          id: 'source|mid-b',
          source: 'source',
          target: 'mid-b',
          value: 3,
          path: Path(),
          sourceY: 10,
          targetY: 20,
          heightSource: 5,
          heightTarget: 5,
          sourceColor: Colors.blue,
          targetColor: Colors.purple,
          zone: 'proxy',
        ),
      ];

      final focusMidA = collectLinkedIds(links, ['mid-a']);
      expect(focusMidA.contains('mid-a'), isTrue);
      expect(focusMidA.contains('source'), isTrue);
      expect(focusMidA.contains('out-proxy'), isTrue);
      expect(focusMidA.contains('source|mid-a'), isTrue);
      expect(focusMidA.contains('mid-a|out-proxy'), isTrue);
      expect(focusMidA.contains('mid-b'), isFalse);
      expect(focusMidA.contains('source|mid-b'), isFalse);
    });

    test('matchNodeIds finds case-insensitive matching hosts and outbounds', () {
      final nodes = <TopoNode>[
        const TopoNode(
          id: 'source',
          name: 'My Device',
          type: TopoNodeType.source,
          value: 10,
          x: 0,
          y: 0,
          width: 8,
          height: 36,
          color: Colors.cyan,
          zone: 'proxy',
        ),
        const TopoNode(
          id: 'mid-google.com',
          name: 'google.com',
          type: TopoNodeType.host,
          value: 6,
          x: 100,
          y: 0,
          width: 8,
          height: 20,
          color: Colors.indigo,
          zone: 'proxy',
        ),
        const TopoNode(
          id: 'mid-github.com',
          name: 'github.com',
          type: TopoNodeType.host,
          value: 4,
          x: 100,
          y: 30,
          width: 8,
          height: 16,
          color: Colors.indigo,
          zone: 'proxy',
        ),
      ];

      final matched = matchNodeIds(nodes, 'HUB');
      expect(matched, ['mid-github.com']);
    });

    test('computeTopologyLayout partitions nodes into upper proxy and lower direct zones', () {
      final aggregate = ConnectionsAggregate(
        total: 10,
        hosts: [
          const ConnectionAggHost(
            name: 'proxy-site.com',
            count: 5,
            flows: [ConnectionAggFlow(outbound: '代理', count: 5)],
          ),
          const ConnectionAggHost(
            name: 'direct-site.cn',
            count: 5,
            flows: [ConnectionAggFlow(outbound: '直连', count: 5)],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 5),
          ConnectionAggOutbound(name: '直连', count: 5),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: 400,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      final proxyNodes = layout.nodes.where((n) => n.zone == 'proxy').toList();
      final directNodes = layout.nodes.where((n) => n.zone == 'direct').toList();

      expect(proxyNodes.isNotEmpty, isTrue);
      expect(directNodes.isNotEmpty, isTrue);

      for (final p in proxyNodes) {
        expect(p.y, lessThanOrEqualTo(200.0));
      }
      for (final d in directNodes) {
        expect(d.y, greaterThanOrEqualTo(190.0));
      }
    });

    test('computeTopologyLayout places host domain pills centered at 50% width', () {
      final aggregate = ConnectionsAggregate(
        total: 10,
        hosts: [
          const ConnectionAggHost(
            name: 'center-proxy.com',
            count: 5,
            flows: [ConnectionAggFlow(outbound: '代理', count: 5)],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 5),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 1000,
        height: 500,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      final host = layout.nodes.firstWhere((n) => n.type == TopoNodeType.host);
      final pillCenter = host.x + host.width / 2;
      // 50% of 1000 is 500
      expect(pillCenter, closeTo(500.0, 1.0));

      // Verify links connect to left and right edges of the centered pill
      final srcToHostLink = layout.links.firstWhere((l) => l.target == host.id);
      expect(srcToHostLink.targetX, closeTo(host.x, 0.1));

      final hostToOutLink = layout.links.firstWhere((l) => l.source == host.id);
      expect(hostToOutLink.sourceX, closeTo(host.x + host.width, 0.1));
    });

    test('computeTopologyLayout with expandedZone expands single flow to full view', () {
      final proxyHosts = List.generate(
        25,
        (i) => ConnectionAggHost(
          name: 'proxy-$i.com',
          count: i + 1,
          flows: [ConnectionAggFlow(outbound: '代理', count: i + 1)],
        ),
      );

      final aggregate = ConnectionsAggregate(
        total: 100,
        hosts: proxyHosts,
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 100),
          ConnectionAggOutbound(name: '直连', count: 0),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 1000,
        height: 600,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
        expandedZone: 'proxy',
      );

      expect(layout.expandedZone, 'proxy');
      expect(layout.dividerY, 0.0);
      expect(layout.nodes.any((n) => n.zone == 'direct'), isFalse);
      // In expanded full-view height 600, it can accommodate 20+ hosts!
      expect(layout.proxyHostCount, greaterThanOrEqualTo(18));
    });

    test('computeTopologyLayout preserves incoming recency order so new sites appear first', () {
      final aggregate = ConnectionsAggregate(
        total: 101,
        hosts: [
          // Newly visited site with 1 count at the top
          const ConnectionAggHost(
            name: 'brand-new-site.org',
            count: 1,
            recent: true,
            flows: [ConnectionAggFlow(outbound: '代理', count: 1)],
          ),
          // Old site with high count
          const ConnectionAggHost(
            name: 'old-frequent-site.com',
            count: 100,
            flows: [ConnectionAggFlow(outbound: '代理', count: 100)],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 101),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: 400,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      final hostNodes = layout.nodes.where((n) => n.type == TopoNodeType.host).toList();
      expect(hostNodes.length, 2);
      // The newly visited site MUST be first (highest in upper zone / smaller Y)!
      expect(hostNodes.first.name, 'brand-new-site.org');
      expect(hostNodes.last.name, 'old-frequent-site.com');
      expect(hostNodes.first.y, lessThan(hostNodes.last.y));
    });

    test('computeTopologyLayout guarantees zero overlap between proxy and direct pills', () {
      final proxyHosts = List.generate(
        15,
        (i) => ConnectionAggHost(
          name: 'proxy-$i.com',
          count: i + 1,
          flows: [ConnectionAggFlow(outbound: '代理', count: i + 1)],
        ),
      );
      final directHosts = List.generate(
        15,
        (i) => ConnectionAggHost(
          name: 'direct-$i.cn',
          count: i + 1,
          flows: [ConnectionAggFlow(outbound: '直连', count: i + 1)],
        ),
      );

      final aggregate = ConnectionsAggregate(
        total: 200,
        hosts: [...proxyHosts, ...directHosts],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 100),
          ConnectionAggOutbound(name: '直连', count: 100),
        ],
        timestamp: DateTime.now(),
      );

      const height = 400.0;
      final layout = computeTopologyLayout(
        aggregate: aggregate,
        width: 800,
        height: height,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      const dividerY = height * 0.5; // 200.0
      final proxyHostNodes = layout.nodes.where((n) => n.zone == 'proxy' && n.type == TopoNodeType.host).toList();
      final directHostNodes = layout.nodes.where((n) => n.zone == 'direct' && n.type == TopoNodeType.host).toList();

      expect(proxyHostNodes.isNotEmpty, isTrue);
      expect(directHostNodes.isNotEmpty, isTrue);

      // Verify all proxy host pills end BEFORE dividerY with safety margin
      for (final p in proxyHostNodes) {
        expect(p.y + p.height, lessThanOrEqualTo(dividerY - 14.0));
      }

      // Verify all direct host pills start AFTER dividerY with safety margin
      for (final d in directHostNodes) {
        expect(d.y, greaterThanOrEqualTo(dividerY + 22.0));
      }
    });

    test('computeTopologyLayout renders live dynamic layout for waiting traffic placeholder', () {
      final waitingAggregate = ConnectionsAggregate(
        total: 2,
        hosts: const [
          ConnectionAggHost(
            name: '等待网络请求...',
            count: 1,
            recent: true,
            flows: [
              ConnectionAggFlow(outbound: '代理', count: 1),
              ConnectionAggFlow(outbound: '直连', count: 1),
            ],
          ),
        ],
        outbounds: const [
          ConnectionAggOutbound(name: '代理', count: 1),
          ConnectionAggOutbound(name: '直连', count: 1),
        ],
        timestamp: DateTime.now(),
      );

      final layout = computeTopologyLayout(
        aggregate: waitingAggregate,
        width: 400,
        height: 300,
        sourceLabel: '本机设备',
        othersLabel: '其他目标',
        primaryColor: const Color(0xFF6C5CE7),
        isDark: true,
      );

      expect(layout.nodes.any((n) => n.name == '本机设备'), isTrue);
      expect(layout.nodes.any((n) => n.name == '等待网络请求...'), isTrue);
      expect(layout.nodes.any((n) => n.name == '代理'), isTrue);
      expect(layout.nodes.any((n) => n.name == '直连'), isTrue);
      expect(layout.links.isNotEmpty, isTrue);
    });
  });
}
