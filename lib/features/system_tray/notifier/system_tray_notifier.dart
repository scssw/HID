import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/router.dart';
import 'package:hiddify/features/config_option/data/config_option_repository.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'system_tray_notifier.g.dart';

@Riverpod(keepAlive: true)
class SystemTrayNotifier extends _$SystemTrayNotifier with AppLogger {
  @override
  Future<void> build() async {
    if (!PlatformUtils.isDesktop) return;

    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final delay = activeProxy?.urlTestDelay ?? 0;
    final newConnectionStatus = delay > 0 && delay < 65000;
    ConnectionStatus connection;
    try {
      connection = await ref.watch(connectionNotifierProvider.future);
    } catch (e) {
      loggy.warning("error getting connection status", e);
      connection = const ConnectionStatus.disconnected();
    }

    final t = ref.watch(translationsProvider);

    var tooltip = Constants.appName;
    final serviceMode = ref.watch(ConfigOptions.serviceMode);
    if (connection == const Disconnected()) {
      setIcon(connection);
    } else if (newConnectionStatus) {
      setIcon(const Connected());
      tooltip = "$tooltip - ${connection.present(t)} : ${delay}ms";
    } else {
      setIcon(const Disconnecting());
      tooltip = "$tooltip - ${connection.present(t)}";
    }
    if (Platform.isMacOS) {
      windowManager.setBadgeLabel("${delay}ms");
    }
    if (!Platform.isLinux) {
      trayManager.setToolTip(tooltip).catchError((_) {});
    }

    try {
      final menu = Menu(
        items: [
          MenuItem(
            label: t.tray.dashboard,
            onClick: (_) async {
              await ref.read(windowNotifierProvider.notifier).open();
            },
          ),
          MenuItem.separator(),
          MenuItem.checkbox(
            label: switch (connection) {
              Disconnected() => t.tray.status.connect,
              Connecting() => t.tray.status.connecting,
              Connected() => t.tray.status.disconnect,
              Disconnecting() => t.tray.status.disconnecting,
            },
            checked: false,
            disabled: connection.isSwitching,
            onClick: (_) async {
              await ref.read(connectionNotifierProvider.notifier).toggleConnection();
            },
          ),
          MenuItem.separator(),
          MenuItem(
            label: t.config.serviceMode,
            disabled: true,
          ),

          ...ServiceMode.values.map(
            (e) => MenuItem.checkbox(
              checked: e == serviceMode,
              key: e.name,
              label: e.present(t),
              onClick: (menuItem) async {
                final newMode = ServiceMode.values.byName(menuItem.key!);
                loggy.debug("switching service mode: [$newMode]");
                await ref.read(ConfigOptions.serviceMode.notifier).update(newMode);
              },
            ),
          ),

          MenuItem.separator(),
          MenuItem(
            label: t.tray.quit,
            onClick: (_) async {
              return ref.read(windowNotifierProvider.notifier).quit();
            },
          ),
        ],
      );

      await trayManager.setContextMenu(menu);
    } catch (e) {
      loggy.warning("error updating system tray menu", e);
      // Fallback essential menu so right click never shows an empty unclickable window
      try {
        final fallbackMenu = Menu(
          items: [
            MenuItem(
              label: t.tray.dashboard,
              onClick: (_) async {
                await ref.read(windowNotifierProvider.notifier).open();
              },
            ),
            MenuItem.separator(),
            MenuItem(
              label: t.tray.quit,
              onClick: (_) async {
                return ref.read(windowNotifierProvider.notifier).quit();
              },
            ),
          ],
        );
        await trayManager.setContextMenu(fallbackMenu);
      } catch (_) {}
    }
  }

  static void setIcon(ConnectionStatus status) {
    if (!PlatformUtils.isDesktop) return;
    try {
      final iconPath = _trayIconPath(status);
      trayManager.setIcon(
        iconPath,
        isTemplate: Platform.isMacOS,
      ).catchError((_) {});
    } catch (_) {}
  }

  static String _trayIconPath(ConnectionStatus status) {
    if (Platform.isWindows) {
      final Brightness brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final isDarkMode = brightness == Brightness.dark;
      switch (status) {
        case Connected():
          return Assets.images.trayIconConnectedIco;
        case Connecting():
          return Assets.images.trayIconDisconnectedIco;
        case Disconnecting():
          return Assets.images.trayIconDisconnectedIco;
        case Disconnected():
          if (isDarkMode) {
            return Assets.images.trayIconIco;
          } else {
            return Assets.images.trayIconDarkIco;
          }
      }
    }
    final isDarkMode = false;
    switch (status) {
      case Connected():
        return Assets.images.trayIconConnectedPng.path;
      case Connecting():
        return Assets.images.trayIconDisconnectedPng.path;
      case Disconnecting():
        return Assets.images.trayIconDisconnectedPng.path;
      case Disconnected():
        if (isDarkMode) {
          return Assets.images.trayIconDarkPng.path;
        } else {
          return Assets.images.trayIconPng.path;
        }
    }
    // return Assets.images.trayIconPng.path;
  }
}
