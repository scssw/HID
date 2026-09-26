import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'analytics_controller.g.dart';

const String enableAnalyticsPrefKey = "enable_analytics";

@Riverpod(keepAlive: true)
class AnalyticsController extends _$AnalyticsController with AppLogger {
  @override
  Future<bool> build() async {
    await _preferences.setBool(enableAnalyticsPrefKey, false);
    return false;
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider).requireValue;

  Future<void> enableAnalytics() async {
    loggy.debug("analytics is disabled in this build");
    await _preferences.setBool(enableAnalyticsPrefKey, false);
    await Sentry.close();
    LoggerController.instance.removePrinter("analytics");
    state = const AsyncData(false);
  }

  Future<void> disableAnalytics() async {
    if (state case AsyncData()) {
      loggy.debug("disabling analytics");
      state = const AsyncLoading();
      await _preferences.setBool(enableAnalyticsPrefKey, false);
      await Sentry.close();
      LoggerController.instance.removePrinter("analytics");
      state = const AsyncData(false);
    }
  }
}
