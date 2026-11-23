import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps SafeStep alive with the screen off. Android requires a visible notification and a
/// foreground service type for each sensor used in the background (camera, microphone,
/// location). The guidance itself keeps running in the main isolate; this service only stops
/// Android from killing it.
class GuidanceService {
  static bool _initialised = false;

  static void _init() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safestep_guidance',
        channelName: 'SafeStep guidance',
        channelDescription: 'Shown while SafeStep is guiding you',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialised = true;
  }

  static Future<void> start({required String title, required String text}) async {
    _init();
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 4242,
        serviceTypes: const [
          ForegroundServiceTypes.camera,
          ForegroundServiceTypes.microphone,
          ForegroundServiceTypes.location,
        ],
        notificationTitle: title,
        notificationText: text,
        callback: startKeepAlive,
      );
    } catch (e) {
      debugPrint('GuidanceService.start failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void startKeepAlive() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
