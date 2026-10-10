import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/config_option/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MissingPrivilegeDialog extends ConsumerWidget {
  const MissingPrivilegeDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => const MissingPrivilegeDialog(),
    );
  }

  static Future<bool> relaunchAsAdmin() async {
    try {
      final execPath = Platform.resolvedExecutable;
      if (Platform.isMacOS) {
        final homeDir = Platform.environment['HOME'] ?? '';
        final cmd = homeDir.isNotEmpty
            ? 'HOME="$homeDir" "$execPath"'
            : '"$execPath"';
        final script =
            'do shell script "$cmd > /dev/null 2>&1 &" with administrator privileges';
        final res = await Process.run('osascript', ['-e', script]);
        if (res.exitCode == 0) {
          exit(0);
        }
        return false;
      } else if (Platform.isWindows) {
        await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Start-Process',
          '-FilePath',
          '"$execPath"',
          '-Verb',
          'RunAs',
        ]);
        exit(0);
      } else if (Platform.isLinux) {
        await Process.run('pkexec', [execPath]);
        exit(0);
      }
    } catch (_) {}
    return false;
  }

  static String getTerminalCommand() {
    final execPath = Platform.resolvedExecutable;
    if (Platform.isWindows) {
      return 'powershell -Command "Start-Process \'$execPath\' -Verb RunAs"';
    }
    return 'sudo "$execPath"';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    String detailedExplanation = t.failure.singbox.missingPrivilegeMsg;
    if (Platform.isMacOS) {
      detailedExplanation =
          "macOS 系统机制说明：\n\n"
          "1. VPN (TUN) 全局模式需要创建虚拟网卡 (utun) 并接管核心路由，这属于系统底层网络接口，必须具备 macOS 的 Root 管理员最高权限。\n\n"
          "2. 在【系统设置 > 隐私与安全】中允许的仅为常规文件/辅助功能权限，无法替代操作系统底层的虚拟网卡控制权限。\n\n"
          "您可以点击下方【管理员授权并重启】直接输入密码授权启动，或使用终端命令运行。";
    } else if (Platform.isLinux) {
      detailedExplanation =
          "VPN (TUN) 模式需要创建虚拟网卡和核心路由表，需要 Root 权限。\n\n"
          "您可以点击下方【管理员授权并重启】或使用终端 sudo 运行。";
    }

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Colors.amber, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.failure.singbox.missingPrivilege,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detailedExplanation,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      getTerminalCommand(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: "复制命令",
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: getTerminalCommand()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("已复制启动命令到剪贴板"),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(t.general.cancel),
        ),
        TextButton(
          onPressed: () async {
            await ref
                .read(ConfigOptions.serviceMode.notifier)
                .update(ServiceMode.systemProxy);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text("切回系统代理"),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.security, size: 18),
          onPressed: () async {
            final elevated = await relaunchAsAdmin();
            if (!elevated && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("授权未完成或已取消，可尝试使用终端命令启动"),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          label: const Text("管理员授权并重启"),
        ),
      ],
    );
  }
}
