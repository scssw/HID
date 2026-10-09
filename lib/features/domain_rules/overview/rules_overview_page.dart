import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/common/nested_app_bar.dart';
import 'package:hiddify/features/domain_rules/notifier/custom_domain_rules_notifier.dart';
import 'package:hiddify/features/domain_rules/widget/add_domain_rule_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class RulesOverviewPage extends HookConsumerWidget {
  const RulesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rules = ref.watch(customDomainRulesProvider);
    final notifier = ref.read(customDomainRulesProvider.notifier);

    final searchQuery = useState('');
    final filterMode = useState<String>('all');
    final searchController = useTextEditingController();

    // Filter rules by search query and category
    final filteredRules = rules.where((rule) {
      if (searchQuery.value.isNotEmpty &&
          !rule.domain.toLowerCase().contains(searchQuery.value.toLowerCase())) {
        return false;
      }
      if (filterMode.value == 'proxy' && !rule.isProxy) return false;
      if (filterMode.value == 'direct' && !rule.isDirect) return false;
      return true;
    }).toList();

    final proxyCount = rules.where((r) => r.isProxy).length;
    final directCount = rules.where((r) => r.isDirect).length;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: MultiSliver(
                children: [
                  NestedAppBar(
                    forceElevated: innerBoxIsScrolled,
                    title: const Text('域名规则'),
                    actions: [
                      IconButton(
                        icon: const Icon(FluentIcons.add_circle_20_regular),
                        tooltip: '添加域名规则',
                        onPressed: () => AddDomainRuleDialog.show(context),
                      ),
                      if (rules.isNotEmpty)
                        PopupMenuButton<String>(
                          icon: const Icon(FluentIcons.more_vertical_20_regular),
                          tooltip: '更多操作',
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'clear',
                              child: Row(
                                children: [
                                  Icon(FluentIcons.delete_20_regular, size: 16, color: Colors.red),
                                  Gap(8),
                                  Text('清空所有规则', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (val) {
                            if (val == 'clear') {
                              showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('确认清空规则'),
                                  content: const Text('确定要清空所有自定义域名规则吗？此操作不可撤销。'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () {
                                        notifier.clearAll();
                                        Navigator.of(ctx).pop(true);
                                      },
                                      child: const Text('清空'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            return CustomScrollView(
              slivers: [
                SliverOverlapInjector(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
                // Search and Filter Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        TextField(
                          controller: searchController,
                          onChanged: (val) => searchQuery.value = val,
                          decoration: InputDecoration(
                            hintText: '搜索已设置的域名规则...',
                            prefixIcon: const Icon(FluentIcons.search_16_regular),
                            suffixIcon: searchQuery.value.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(FluentIcons.dismiss_16_regular),
                                    onPressed: () {
                                      searchController.clear();
                                      searchQuery.value = '';
                                    },
                                  )
                                : null,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const Gap(12),
                        // Filter row & statistics
                        Row(
                          children: [
                            SegmentedButton<String>(
                              segments: [
                                ButtonSegment<String>(
                                  value: 'all',
                                  label: Text('全部 (${rules.length})'),
                                ),
                                ButtonSegment<String>(
                                  value: 'proxy',
                                  label: Text('代理 ($proxyCount)'),
                                ),
                                ButtonSegment<String>(
                                  value: 'direct',
                                  label: Text('直连 ($directCount)'),
                                ),
                              ],
                              selected: {filterMode.value},
                              onSelectionChanged: (set) => filterMode.value = set.first,
                              showSelectedIcon: false,
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: () => AddDomainRuleDialog.show(context),
                              icon: const Icon(FluentIcons.add_16_regular, size: 16),
                              label: const Text('添加域名'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Rules List or Empty State
                if (filteredRules.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              rules.isEmpty
                                  ? FluentIcons.branch_fork_hint_24_regular
                                  : FluentIcons.search_24_regular,
                              size: 56,
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                            ),
                            const Gap(16),
                            Text(
                              rules.isEmpty
                                  ? '暂无自定义域名规则'
                                  : '没有找到匹配「${searchQuery.value}」的域名',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Gap(8),
                            Text(
                              rules.isEmpty
                                  ? '您可以在首页连接流向图中右键点击任意域名直接添加，\n也可以点击下方按钮手动添加。'
                                  : '尝试搜索其他关键词，或切换筛选条件。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                              ),
                            ),
                            if (rules.isEmpty) ...[
                              const Gap(20),
                              FilledButton.icon(
                                onPressed: () => AddDomainRuleDialog.show(context),
                                icon: const Icon(FluentIcons.add_16_regular),
                                label: const Text('添加新规则'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final rule = filteredRules[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  // Leading type indicator icon
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: rule.isProxy
                                          ? theme.colorScheme.primary.withOpacity(0.12)
                                          : Colors.teal.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      rule.isProxy
                                          ? FluentIcons.globe_20_regular
                                          : FluentIcons.arrow_routing_20_regular,
                                      size: 18,
                                      color: rule.isProxy
                                          ? theme.colorScheme.primary
                                          : Colors.teal,
                                    ),
                                  ),
                                  const Gap(14),
                                  // Domain name and subtitle
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rule.domain,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Gap(2),
                                        Text(
                                          '匹配: domain:${rule.domain} · 当前走向: ${rule.isProxy ? '代理' : '直连'}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Switch / Toggle between Proxy and Direct
                                  SegmentedButton<String>(
                                    style: const ButtonStyle(
                                      visualDensity: VisualDensity.compact,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    segments: const [
                                      ButtonSegment<String>(
                                        value: 'proxy',
                                        label: Text('代理'),
                                      ),
                                      ButtonSegment<String>(
                                        value: 'bypass',
                                        label: Text('直连'),
                                      ),
                                    ],
                                    selected: {rule.outbound},
                                    onSelectionChanged: (newSel) {
                                      notifier.setRule(rule.domain, newSel.first);
                                    },
                                    showSelectedIcon: false,
                                  ),
                                  const Gap(8),
                                  // Delete button
                                  IconButton(
                                    icon: const Icon(FluentIcons.delete_20_regular, size: 18),
                                    color: theme.colorScheme.error,
                                    tooltip: '删除此规则',
                                    onPressed: () {
                                      notifier.removeRule(rule.domain);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('已删除 ${rule.domain} 的自定义规则'),
                                          duration: const Duration(seconds: 2),
                                          action: SnackBarAction(
                                            label: '撤回',
                                            onPressed: () {
                                              notifier.setRule(rule.domain, rule.outbound);
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filteredRules.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
