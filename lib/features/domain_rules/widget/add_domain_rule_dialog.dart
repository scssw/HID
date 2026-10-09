import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/domain_rules/notifier/custom_domain_rules_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddDomainRuleDialog extends HookConsumerWidget {
  const AddDomainRuleDialog({
    super.key,
    this.initialDomain,
    this.initialOutbound,
  });

  final String? initialDomain;
  final String? initialOutbound;

  static Future<bool?> show(
    BuildContext context, {
    String? initialDomain,
    String? initialOutbound,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AddDomainRuleDialog(
        initialDomain: initialDomain,
        initialOutbound: initialOutbound,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textController = useTextEditingController(text: initialDomain ?? '');
    final outbound = useState<String>(initialOutbound ?? 'proxy');
    final errorMessage = useState<String?>(null);

    void submit() {
      final raw = textController.text.trim();
      final clean = CustomDomainRulesNotifier.normalizeDomain(raw);
      if (clean.isEmpty) {
        errorMessage.value = '请输入有效的域名，例如 google.com';
        return;
      }
      ref.read(customDomainRulesProvider.notifier).setRule(clean, outbound.value);
      Navigator.of(context).pop(true);
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(FluentIcons.branch_fork_20_regular, color: theme.colorScheme.primary),
          const Gap(8),
          const Text('添加域名规则'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '为特定域名指定路由走向（代理或直连）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Gap(16),
            TextField(
              controller: textController,
              autofocus: initialDomain == null,
              decoration: InputDecoration(
                labelText: '目标域名',
                hintText: '例如: github.com 或 openai.com',
                prefixIcon: const Icon(FluentIcons.globe_16_regular),
                errorText: errorMessage.value,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSubmitted: (_) => submit(),
              onChanged: (_) {
                if (errorMessage.value != null) {
                  errorMessage.value = null;
                }
              },
            ),
            const Gap(16),
            Text(
              '走向选择',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Gap(8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'proxy',
                  label: Text('代理'),
                  icon: Icon(FluentIcons.globe_20_regular),
                ),
                ButtonSegment<String>(
                  value: 'bypass',
                  label: Text('直连'),
                  icon: Icon(FluentIcons.arrow_routing_20_regular),
                ),
              ],
              selected: {outbound.value},
              onSelectionChanged: (newSelection) {
                outbound.value = newSelection.first;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: submit,
          child: const Text('保存规则'),
        ),
      ],
    );
  }
}
