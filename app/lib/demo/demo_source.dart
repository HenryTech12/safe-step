import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Frames for demo mode, made from a recorded street video by ml/scripts/video_to_frames.py.
/// A demo folder holds `manifest.json` ({"fps": 5, "frames": ["000001.jpg", ...]}) plus the
/// JPEGs. It is read from (first match wins):
///   1. the app's external files dir: /sdcard/Android/data/ng.safestep.app/files/demo/
///      (adb push frames/ /sdcard/Android/data/ng.safestep.app/files/demo)
///   2. bundled assets/demo/ (only if you add it to pubspec.yaml)
class DemoManifest {
  const DemoManifest(this.fps, this.frames);
  final double fps;
  final List<String> frames;

  static DemoManifest parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final fps = (j['fps'] as num?)?.toDouble() ?? 5;
    final frames = (j['frames'] as List).cast<String>();
    if (frames.isEmpty) throw const FormatException('no frames');
    return DemoManifest(fps <= 0 ? 5 : fps, frames);
  }
}

abstract class DemoSource {
  DemoManifest get manifest;
  Future<Uint8List> frame(int index);

  static Future<DemoSource?> find() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final f = File('${dir.path}/demo/manifest.json');
        if (await f.exists()) return _FileSource('${dir.path}/demo', DemoManifest.parse(await f.readAsString()));
      }
    } catch (_) {}
    try {
      final m = DemoManifest.parse(await rootBundle.loadString('assets/demo/manifest.json'));
      return _AssetSource(m);
    } catch (_) {}
    return null;
  }
}

class _FileSource implements DemoSource {
  _FileSource(this.dir, this.manifest);
  final String dir;
  @override
  final DemoManifest manifest;
  @override
  Future<Uint8List> frame(int i) => File('$dir/${manifest.frames[i]}').readAsBytes();
}

class _AssetSource implements DemoSource {
  _AssetSource(this.manifest);
  @override
  final DemoManifest manifest;
  @override
  Future<Uint8List> frame(int i) async =>
      (await rootBundle.load('assets/demo/${manifest.frames[i]}')).buffer.asUint8List();
}
