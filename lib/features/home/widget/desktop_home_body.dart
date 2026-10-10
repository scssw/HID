import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/features/config_option/data/config_option_repository.dart';
import 'package:hiddify/features/config_option/notifier/config_option_notifier.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/widget/experimental_feature_notice.dart';
import 'package:hiddify/features/connection/widget/missing_privilege_dialog.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_card.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/proxy/active/active_proxy_footer.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class DesktopHomeBody extends HookConsumerWidget {
  const DesktopHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final delay = activeProxy.valueOrNull?.urlTestDelay ?? 0;
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;

    final statusValue = connectionStatus.valueOrNull;
    final isConnected = statusValue is Connected;
    final isConnecting = statusValue is Connecting;
    final isConnectedOrConnecting = isConnected || isConnecting;

    // Topology display state: expanded by default when connected
    final isTopologyExpanded = useState(true);

    ref.listen(
      connectionNotifierProvider,
      (_, next) {
        if (next case AsyncError(:final error)) {
          CustomAlertDialog.fromErr(t.presentError(error)).show(context);
        }
        if (next case AsyncData(value: Disconnected(:final connectionFailure?))) {
          if (connectionFailure is MissingPrivilege) {
            MissingPrivilegeDialog.show(context);
          } else {
            CustomAlertDialog.fromErr(t.presentError(connectionFailure)).show(context);
          }
        }
        if (next case AsyncData(value: Connected())) {
          isTopologyExpanded.value = true;
        }
      },
    );

    final buttonTheme = Theme.of(context).extension<ConnectionButtonTheme>()!;

    Future<bool> showExperimentalNotice() async {
      final hasExperimental = ref.read(ConfigOptions.hasExperimentalFeatures);
      final canShowNotice = !ref.read(disableExperimentalFeatureNoticeProvider);
      if (hasExperimental && canShowNotice && context.mounted) {
        return await const ExperimentalFeatureNoticeDialog().show(context) ?? false;
      }
      return true;
    }

    final VoidCallback onTap = switch (connectionStatus) {
      AsyncData(value: Disconnected()) || AsyncError() => () async {
          if (await showExperimentalNotice()) {
            return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          }
        },
      AsyncData(value: Connected()) => () async {
          if (requiresReconnect == true && await showExperimentalNotice()) {
            return await ref.read(connectionNotifierProvider.notifier).reconnect(await ref.read(activeProfileProvider.future));
          }
          return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        },
      _ => () {},
    };

    final bool enabled = switch (connectionStatus) {
      AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
      _ => false,
    };

    final String label = switch (connectionStatus) {
      AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
      AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
      AsyncData(value: final status) => status.present(t),
      _ => "",
    };

    final Color buttonColor = switch (connectionStatus) {
      AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
      AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => const Color.fromARGB(255, 185, 176, 103),
      AsyncData(value: Connected()) => buttonTheme.connectedColor!,
      AsyncData(value: _) => buttonTheme.idleColor!,
      _ => Colors.red,
    };

    // When connected and topology is expanded, button is in bottom-right under "代理 / 直连"
    final bool showInBottomRight = isConnectedOrConnecting && isTopologyExpanded.value;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Connection Topology Card at original center position
            AnimatedPositioned(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              left: 16,
              right: 16,
              top: 12,
              bottom: 16,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                opacity: showInBottomRight ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !showInBottomRight,
                  child: ConnectionTopologyCard(
                    onHide: () => isTopologyExpanded.value = false,
                  ),
                ),
              ),
            ),

            // 2. "连接流向" Expand Button above the center connection button icon
            AnimatedPositioned(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              top: (constraints.maxHeight / 2) - 135,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  opacity: (isConnectedOrConnecting && !isTopologyExpanded.value) ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !(isConnectedOrConnecting && !isTopologyExpanded.value),
                    child: FilledButton.tonalIcon(
                      onPressed: () => isTopologyExpanded.value = true,
                      icon: const Icon(FluentIcons.arrow_routing_20_filled),
                      label: const Text("连接流向"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Animated Center Text & Delay Indicator when disconnected or collapsed
            AnimatedAlign(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              alignment: showInBottomRight ? Alignment.bottomRight : Alignment.center,
              child: IgnorePointer(
                ignoring: showInBottomRight,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  opacity: showInBottomRight ? 0.0 : 1.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 220),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedText(
                          label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(8),
                        const ActiveProxyDelayIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4. Mobile Active Proxy Footer when collapsed
            if (MediaQuery.sizeOf(context).width < 840)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  opacity: showInBottomRight ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: showInBottomRight,
                    child: const ActiveProxyFooter(),
                  ),
                ),
              ),

            // 5. Connection Button (Transforms from Center 148px to Bottom-Right 60-64px)
            AnimatedAlign(
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOutCubic,
              alignment: showInBottomRight ? Alignment.bottomRight : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(
                  right: showInBottomRight ? (PlatformUtils.isDesktop ? 32.0 : 20.0) : 0.0,
                  bottom: showInBottomRight ? (PlatformUtils.isDesktop ? 28.0 : 20.0) : 0.0,
                ),
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: label,
                  child: Tooltip(
                    message: isConnectedOrConnecting ? "$label · 点击断开" : label,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeInOutCubic,
                      width: showInBottomRight ? 60 : 148,
                      height: showInBottomRight ? 60 : 148,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            blurRadius: showInBottomRight ? 12 : 20,
                            spreadRadius: showInBottomRight ? 2 : 0,
                            color: buttonColor.withOpacity(showInBottomRight ? 0.6 : 0.45),
                          ),
                        ],
                      ),
                      child: Material(
                        shape: const CircleBorder(),
                        color: Colors.white,
                        child: InkWell(
                          onTap: onTap,
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeInOutCubic,
                            padding: EdgeInsets.all(showInBottomRight ? 14 : 36),
                            child: TweenAnimationBuilder<Color?>(
                              tween: ColorTween(end: buttonColor),
                              duration: const Duration(milliseconds: 250),
                              builder: (context, value, child) {
                                return Assets.images.logo.svg(
                                  colorFilter: ColorFilter.mode(
                                    value ?? buttonColor,
                                    BlendMode.srcIn,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
