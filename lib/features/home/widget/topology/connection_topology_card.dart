import 'dart:math' as math;
import 'package:dartx/dartx.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/router.dart';
import 'package:hiddify/features/domain_rules/notifier/custom_domain_rules_notifier.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_model.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_notifier.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_painter.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

class ConnectionTopologyCard extends HookConsumerWidget {
  final bool disconnected;
  final VoidCallback? onHide;

  const ConnectionTopologyCard({
    super.key,
    this.disconnected = false,
    this.onHide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final state = ref.watch(connectionTopologyNotifierProvider);
    final notifier = ref.read(connectionTopologyNotifierProvider.notifier);
    final searchController = useTextEditingController(text: state.searchQuery);

    final animController = useAnimationController(
      duration: const Duration(seconds: 3),
    );

    final isAlwaysOnTop = useState<bool>(false);

    useEffect(
      () {
        animController.repeat();
        if (PlatformUtils.isDesktop) {
          windowManager.isAlwaysOnTop().then((val) {
            isAlwaysOnTop.value = val;
          }).catchError((_) {});
        }

        final observer = _TopologyLifecycleObserver(
          onPaused: () {
            if (animController.isAnimating) {
              animController.stop();
            }
          },
          onResumed: () {
            if (!animController.isAnimating) {
              animController.repeat();
            }
          },
        );
        WidgetsBinding.instance.addObserver(observer);

        WindowListener? winListener;
        if (PlatformUtils.isDesktop) {
          winListener = _TopologyWindowListener(
            onHidden: () {
              if (animController.isAnimating) {
                animController.stop();
              }
            },
            onShown: () {
              if (!animController.isAnimating) {
                animController.repeat();
              }
            },
          );
          windowManager.addListener(winListener);
        }

        return () {
          WidgetsBinding.instance.removeObserver(observer);
          if (winListener != null) {
            windowManager.removeListener(winListener);
          }
        };
      },
      [],
    );

    // Track expanded single flow ('proxy' or 'direct') on double click
    final expandedZone = useState<String?>(null);

    // Track mouse interaction to lock layout and prevent any jitter/shifting
    final isMouseOverCanvas = useState<bool>(false);
    final cachedLayout = useRef<TopoLayoutResult?>(null);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.35 : 0.45),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Title, connection count, filter chip, expanded chip and search bar
            Row(
              children: [
                Icon(
                  FluentIcons.arrow_routing_24_filled,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const Gap(8),
                Text(
                  "连接流向",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "活跃目标: ${state.aggregate.hosts.isEmpty ? '监听中' : state.aggregate.hosts.length}",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Expanded Zone Indicator Chip
                if (expandedZone.value != null) ...[
                  const Gap(8),
                  InkWell(
                    onTap: () {
                      cachedLayout.value = null;
                      expandedZone.value = null;
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (expandedZone.value == 'proxy'
                                ? theme.colorScheme.primary
                                : Colors.cyan)
                            .withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: expandedZone.value == 'proxy'
                              ? theme.colorScheme.primary
                              : Colors.cyan,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            expandedZone.value == 'proxy'
                                ? FluentIcons.arrow_routing_20_regular
                                : FluentIcons.arrow_bidirectional_up_down_20_regular,
                            size: 12,
                            color: expandedZone.value == 'proxy'
                                ? theme.colorScheme.primary
                                : (isDark ? Colors.cyanAccent : Colors.teal),
                          ),
                          const Gap(4),
                          Text(
                            "全屏: ${expandedZone.value == 'proxy' ? '代理' : '直连'} (双击恢复)",
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: expandedZone.value == 'proxy'
                                  ? theme.colorScheme.primary
                                  : (isDark ? Colors.cyanAccent : Colors.teal),
                            ),
                          ),
                          const Gap(4),
                          const Icon(FluentIcons.dismiss_12_regular, size: 12),
                        ],
                      ),
                    ),
                  ),
                ],
                // Active Outbound Filter Tag (e.g. 直连 or 代理)
                if (state.activeOutboundFilter != null) ...[
                  const Gap(8),
                  InkWell(
                    onTap: () {
                      notifier.clearFilterAndHover();
                      cachedLayout.value = null;
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: state.activeOutboundFilter == '直连'
                            ? Colors.cyan.withOpacity(0.2)
                            : theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.activeOutboundFilter == '直连'
                              ? Colors.cyan
                              : theme.colorScheme.primary,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "只看: ${state.activeOutboundFilter}",
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: state.activeOutboundFilter == '直连'
                                  ? (isDark ? Colors.cyanAccent : Colors.teal)
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          const Gap(4),
                          const Icon(FluentIcons.dismiss_12_regular, size: 12),
                        ],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Search box (responsive for mobile and desktop)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190, minWidth: 90),
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: searchController,
                          onChanged: notifier.updateSearch,
                          style: theme.textTheme.bodySmall,
                          decoration: InputDecoration(
                            hintText: "检索域名/IP...",
                            hintStyle: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                            ),
                            prefixIcon: const Icon(FluentIcons.search_16_regular, size: 14),
                            prefixIconConstraints: const BoxConstraints(minWidth: 28),
                            suffixIcon: state.searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(FluentIcons.dismiss_16_regular, size: 12),
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      searchController.clear();
                                      notifier.updateSearch('');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            filled: true,
                            fillColor: theme.colorScheme.surface.withOpacity(0.6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Gap(10),

            // Main Flowchart Body
            Expanded(
              child: disconnected
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            FluentIcons.plug_disconnected_28_regular,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                          ),
                          const Gap(8),
                          Text(
                            "未连接代理服务",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                          return const SizedBox.shrink();
                        }

                        final isWaitingTraffic = state.aggregate.hosts.isEmpty;
                        final effectiveAggregate = isWaitingTraffic
                            ? ConnectionsAggregate(
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
                              )
                            : state.aggregate;

                        // 1. Calculate or use locked cached layout only when hovering a specific node
                        TopoLayoutResult layout;
                        if (state.hoveredNode != null &&
                            cachedLayout.value != null &&
                            cachedLayout.value!.nodes.isNotEmpty &&
                            cachedLayout.value!.expandedZone == expandedZone.value) {
                          layout = cachedLayout.value!;
                        } else {
                          layout = computeTopologyLayout(
                            aggregate: effectiveAggregate,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            sourceLabel: "本机设备",
                            othersLabel: "其他访问",
                            primaryColor: theme.colorScheme.primary,
                            isDark: isDark,
                            filterOutbound: state.activeOutboundFilter,
                            expandedZone: expandedZone.value,
                          );
                          cachedLayout.value = layout;
                        }

                            // 2. Identify highlighted links/nodes
                            final highlighted = <String>{};
                            if (state.searchQuery.isNotEmpty) {
                              highlighted.addAll(matchNodeIds(layout.nodes, state.searchQuery));
                            } else if (state.hoveredNode != null) {
                              highlighted.addAll(collectLinkedIds(layout.links, [state.hoveredNode!.id]));
                            } else if (state.hoveredLink != null) {
                              highlighted.add(state.hoveredLink!.id);
                              highlighted.add(state.hoveredLink!.source);
                              highlighted.add(state.hoveredLink!.target);
                            }

                            return GestureDetector(
                              onDoubleTapDown: (details) => _handleDoubleTap(
                                details.localPosition,
                                layout,
                                expandedZone,
                                cachedLayout,
                              ),
                              onTapUp: (details) => _handleTap(
                                details.localPosition,
                                details.globalPosition,
                                layout,
                                notifier,
                                context,
                                ref,
                              ),
                              onSecondaryTapUp: (details) => _handleSecondaryTap(
                                details.localPosition,
                                details.globalPosition,
                                layout,
                                context,
                                ref,
                              ),
                              onLongPressStart: (details) => _handleSecondaryTap(
                                details.localPosition,
                                details.globalPosition,
                                layout,
                                context,
                                ref,
                              ),
                              child: MouseRegion(
                                onEnter: (_) {
                                  isMouseOverCanvas.value = true;
                                },
                                onHover: (event) {
                                  final pos = event.localPosition;
                                  _handleHitTest(
                                    pos,
                                    layout,
                                    notifier,
                                    animController,
                                  );
                                },
                                onExit: (_) {
                                  isMouseOverCanvas.value = false;
                                  if (!animController.isAnimating) {
                                    animController.repeat();
                                  }
                                  notifier.clearHover();
                                },
                                child: Stack(
                                  children: [
                                    CustomPaint(
                                      size: Size(constraints.maxWidth, constraints.maxHeight),
                                      painter: ConnectionTopologyPainter(
                                        layout: layout,
                                        highlightedIds: highlighted,
                                        animation: animController,
                                        isDark: isDark,
                                        colDeviceLabel: "本机设备",
                                        colTargetLabel: "访问网站",
                                        colOutboundLabel: "流向走向",
                                      ),
                                    ),
                                    if (isWaitingTraffic)
                                      Positioned(
                                        bottom: 2,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.surface.withOpacity(0.88),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: theme.colorScheme.primary.withOpacity(0.25),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 10,
                                                  height: 10,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: theme.colorScheme.primary,
                                                  ),
                                                ),
                                                const Gap(8),
                                                Text(
                                                  "流向引擎监听中 · 访问任意网页或应用即可动态上屏",
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (state.tooltipText != null && state.tooltipPosition != null)
                                      _buildTooltip(
                                        context,
                                        state.tooltipText!,
                                        state.tooltipPosition!,
                                        constraints.biggest,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Footer Row: "隐藏" and "置顶" buttons under "本机设备" (left column)
            if (onHide != null || PlatformUtils.isDesktop)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    if (onHide != null)
                      OutlinedButton.icon(
                        onPressed: onHide,
                        icon: const Icon(FluentIcons.eye_off_20_regular, size: 16),
                        label: const Text("隐藏"),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    const Gap(8),
                    OutlinedButton.icon(
                      onPressed: () => const RulesOverviewRoute().push(context),
                      icon: const Icon(FluentIcons.filter_20_regular, size: 16),
                      label: const Text("规则"),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (PlatformUtils.isDesktop) ...[
                      const Gap(8),
                      Tooltip(
                        message: isAlwaysOnTop.value ? "取消窗口置顶" : "窗口置顶（保持最前）",
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final next = !isAlwaysOnTop.value;
                            try {
                              await windowManager.setAlwaysOnTop(next);
                              isAlwaysOnTop.value = next;
                            } catch (_) {}
                          },
                          icon: Icon(
                            isAlwaysOnTop.value
                                ? FluentIcons.pin_20_filled
                                : FluentIcons.pin_20_regular,
                            size: 16,
                            color: isAlwaysOnTop.value ? theme.colorScheme.primary : null,
                          ),
                          label: Text(
                            isAlwaysOnTop.value ? "已置顶" : "置顶",
                            style: TextStyle(
                              color: isAlwaysOnTop.value ? theme.colorScheme.primary : null,
                              fontWeight: isAlwaysOnTop.value ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            side: isAlwaysOnTop.value
                                ? BorderSide(color: theme.colorScheme.primary)
                                : null,
                            backgroundColor: isAlwaysOnTop.value
                                ? theme.colorScheme.primary.withOpacity(0.12)
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Placeholder space for the connection button placed at bottom-right
                    const SizedBox(width: 80, height: 32),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleDoubleTap(
    Offset pos,
    TopoLayoutResult layout,
    ValueNotifier<String?> expandedZoneNotifier,
    ObjectRef<TopoLayoutResult?> cachedLayout,
  ) {
    for (final node in layout.nodes) {
      if (node.hitBox().contains(pos)) {
        cachedLayout.value = null;
        if (expandedZoneNotifier.value == node.zone) {
          expandedZoneNotifier.value = null; // Toggle back to dual view!
        } else {
          expandedZoneNotifier.value = node.zone; // Expand this flow to full view!
        }
        return;
      }
    }
    // If clicked empty space while in expanded view -> restore dual view!
    if (expandedZoneNotifier.value != null) {
      cachedLayout.value = null;
      expandedZoneNotifier.value = null;
    }
  }

  void _handleTap(
    Offset pos,
    Offset globalPos,
    TopoLayoutResult layout,
    ConnectionTopologyNotifier notifier,
    BuildContext context,
    WidgetRef ref,
  ) {
    // 1. Check if an outbound node was clicked ("直连" or "代理")
    for (final node in layout.nodes) {
      if (node.type == TopoNodeType.outbound && node.hitBox().contains(pos)) {
        notifier.toggleOutboundFilter(node.name);
        return;
      }
    }

    // 2. Check if a host node was clicked
    for (final node in layout.nodes) {
      if (node.type == TopoNodeType.host && node.hitBox().contains(pos)) {
        if (node.name == '等待网络请求...') return;
        notifier.setHover(node: node);
        if (!PlatformUtils.isDesktop) {
          _handleSecondaryTap(pos, globalPos, layout, context, ref);
        }
        return;
      }
    }

    // 3. Click on blank/empty space -> restore original full view!
    notifier.clearFilterAndHover();
  }

  Future<void> _handleSecondaryTap(
    Offset pos,
    Offset globalPos,
    TopoLayoutResult layout,
    BuildContext context,
    WidgetRef ref,
  ) async {
    for (final node in layout.nodes) {
      if (node.type == TopoNodeType.host && node.hitBox().contains(pos)) {
        if (node.name == '等待网络请求...') return;
        final domain = node.name;
        final customRules = ref.read(customDomainRulesProvider);
        final existingRule = customRules.firstOrNullWhere((r) => r.domain == domain);

        final selected = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            globalPos.dx,
            globalPos.dy,
            globalPos.dx + 1,
            globalPos.dy + 1,
          ),
          items: [
            PopupMenuItem<String>(
              enabled: false,
              child: Row(
                children: [
                  const Icon(FluentIcons.globe_search_20_regular, size: 16),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      domain,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'proxy',
              child: Row(
                children: [
                  const Icon(FluentIcons.globe_20_regular, size: 16, color: Colors.blueAccent),
                  const Gap(8),
                  const Text('设置代理'),
                  if (existingRule?.isProxy == true) ...[
                    const Spacer(),
                    const Icon(FluentIcons.checkmark_16_regular, size: 14, color: Colors.blueAccent),
                  ],
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'bypass',
              child: Row(
                children: [
                  const Icon(FluentIcons.arrow_routing_20_regular, size: 16, color: Colors.teal),
                  const Gap(8),
                  const Text('设置直连'),
                  if (existingRule?.isDirect == true) ...[
                    const Spacer(),
                    const Icon(FluentIcons.checkmark_16_regular, size: 14, color: Colors.teal),
                  ],
                ],
              ),
            ),
            if (existingRule != null) ...[
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(FluentIcons.delete_20_regular, size: 16, color: Colors.redAccent),
                    Gap(8),
                    Text('清除规则', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ],
        );

        if (selected == 'proxy') {
          await ref.read(customDomainRulesProvider.notifier).setRule(domain, 'proxy');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已将 $domain 设置为「代理」'),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: '查看规则',
                  onPressed: () => const RulesOverviewRoute().push(context),
                ),
              ),
            );
          }
        } else if (selected == 'bypass') {
          await ref.read(customDomainRulesProvider.notifier).setRule(domain, 'bypass');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已将 $domain 设置为「直连」'),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: '查看规则',
                  onPressed: () => const RulesOverviewRoute().push(context),
                ),
              ),
            );
          }
        } else if (selected == 'remove') {
          await ref.read(customDomainRulesProvider.notifier).removeRule(domain);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已清除 $domain 的自定义规则'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }
    }
  }

  void _handleHitTest(
    Offset pos,
    TopoLayoutResult layout,
    ConnectionTopologyNotifier notifier,
    AnimationController animController,
  ) {
    // 1. Check nodes
    for (final node in layout.nodes) {
      if (node.hitBox().contains(pos)) {
        if (node.name == '等待网络请求...') {
          notifier.setHover(
            node: node,
            tooltipText: "流向引擎实时监听中\n访问任意网站即可在此动态显示",
            tooltipPosition: pos,
          );
          return;
        }
        final recentText = node.recent ? " · 最近访问" : "";
        final role = node.type == TopoNodeType.outbound ? "走向: " : "";
        final doubleClickHint = node.type == TopoNodeType.host ? " (双击全屏展示)" : "";
        notifier.setHover(
          node: node,
          tooltipText: "$role${node.name} · ${node.value} 次请求$recentText$doubleClickHint",
          tooltipPosition: pos,
        );

        // When mouse is over a domain (host node), pause dynamic animations!
        if (node.type == TopoNodeType.host) {
          if (animController.isAnimating) {
            animController.stop();
          }
        } else {
          if (!animController.isAnimating) {
            animController.repeat();
          }
        }
        return;
      }
    }

    // 2. Check links
    for (final link in layout.links) {
      if (link.path.contains(pos)) {
        final srcNode = layout.nodes.firstWhere((n) => n.id == link.source, orElse: () => layout.nodes.first);
        final tgtNode = layout.nodes.firstWhere((n) => n.id == link.target, orElse: () => layout.nodes.first);
        notifier.setHover(
          link: link,
          tooltipText: "${srcNode.name} → ${tgtNode.name} · ${link.value} 次连接",
          tooltipPosition: pos,
        );
        if (!animController.isAnimating) {
          animController.repeat();
        }
        return;
      }
    }

    // Over empty canvas: clear hover
    if (!animController.isAnimating) {
      animController.repeat();
    }
    notifier.clearHover();
  }

  Widget _buildTooltip(
    BuildContext context,
    String text,
    Offset position,
    Size containerSize,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    const tooltipWidth = 190.0;

    double left = position.dx + 14;
    double top = position.dy - 38;

    if (left + tooltipWidth > containerSize.width) {
      left = math.max(8.0, position.dx - tooltipWidth - 10);
    }
    if (top < 0) {
      top = position.dy + 14;
    }

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xE61E293B) : const Color(0xE6FFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopologyLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onPaused;
  final VoidCallback onResumed;

  _TopologyLifecycleObserver({required this.onPaused, required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      onPaused();
    } else if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}

class _TopologyWindowListener extends WindowListener {
  final VoidCallback onHidden;
  final VoidCallback onShown;

  _TopologyWindowListener({required this.onHidden, required this.onShown});

  @override
  void onWindowMinimize() => onHidden();

  @override
  void onWindowRestore() => onShown();

  @override
  void onWindowFocus() => onShown();
}
