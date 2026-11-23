import 'package:permission_handler/permission_handler.dart';

import '../onboarding/onboarding_controller.dart';

class DevicePermissions implements PermissionGate {
  @override
  Future<MicResult> requestMicrophone() async {
    final s = await Permission.microphone.request();
    if (s.isGranted) return MicResult.granted;
    if (s.isPermanentlyDenied) return MicResult.permanentlyDenied;
    return MicResult.denied;
  }

  @override
  Future<bool> requestCameraAndLocation() async {
    final r = await [Permission.camera, Permission.locationWhenInUse].request();
    return r[Permission.camera]?.isGranted ?? false;
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
