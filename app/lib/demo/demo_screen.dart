import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import '../guide/guide_controller.dart';
import '../hazard/detection.dart';
import '../theme.dart';
import 'demo_source.dart';

class _Decoded {
  const _Decoded(this.rgb, this.w, this.h);
  final Uint8List rgb;
  final int w, h;
}

_Decoded? _decode(Uint8List jpeg) {
  final im = img.decodeJpg(jpeg);
  if (im == null) return null;
  return _Decoded(im.getBytes(order: img.ChannelOrder.rgb), im.width, im.height);
}

/// Demo mode: replays recorded street video (as JPEG frames) through the same on-device
/// detector, walking-path policy and alert player the live camera uses. For judges and
/// testing, so it shows boxes and timings; the live screens never show debug text.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, required this.guide});
  final GuideController guide;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  DemoSource? _src;
  String _status = 'Loading demo…';
  Uint8List? _jpeg;
  List<Detection> _dets = const [];
  int _index = 0;
  bool _running = false;
  final _sw = Stopwatch();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final hazards = widget.guide.hazards;
    if (hazards == null) {
      setState(() => _status = 'Hazard detector not available.');
      return;
    }
    await hazards.stop(); // free the camera while the demo runs
    final src = await DemoSource.find();
    if (src == null) {
      setState(() => _status =
          'No demo frames found. Push them to /sdcard/Android/data/ng.safestep.app/files/demo/ (see ml/README.md).');
      return;
    }
    _src = src;
    _running = true;
    _loop();
  }

  Future<void> _loop() async {
    final src = _src!;
    final hazards = widget.guide.hazards!;
    final frameMs = 1000 / src.manifest.fps;
    _sw.start();
    while (_running && mounted) {
      final due = (_index * frameMs).round();
      final wait = due - _sw.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (!_running || !mounted) break;
      final jpeg = await src.frame(_index);
      final decoded = await compute(_decode, jpeg);
      if (decoded != null) {
        final dets = await hazards.detector.detectRgb(decoded.rgb, decoded.w, decoded.h);
        if (dets != null) hazards.handleDetections(dets, DateTime.now());
        if (mounted) {
          setState(() {
            _jpeg = jpeg;
            _dets = dets ?? _dets;
            _status = 'Frame ${_index + 1}/${src.manifest.frames.length} · '
                '${hazards.detector.avgMs.toStringAsFixed(0)} ms/frame · '
                'last alert: ${hazards.lastAlert ?? '-'}';
          });
        }
      }
      _index = (_index + 1) % src.manifest.frames.length;
      if (_index == 0) {
        _sw
          ..reset()
          ..start();
        hazards.policy.reset();
      }
    }
  }

  @override
  void dispose() {
    _running = false;
    widget.guide.hazards?.start(); // back to the live camera
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _jpeg == null
                  ? Center(child: Text(_status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge))
                  : LayoutBuilder(
                      builder: (context, box) => Stack(fit: StackFit.expand, children: [
                        Image.memory(_jpeg!, fit: BoxFit.fill, gaplessPlayback: true),
                        CustomPaint(painter: _BoxPainter(_dets)),
                      ]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_status, style: const TextStyle(fontSize: 16, color: SafeStepColors.text)),
            ),
            Semantics(
              button: true,
              label: 'Close demo',
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close demo', style: TextStyle(fontSize: 22, color: SafeStepColors.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.dets);
  final List<Detection> dets;

  @override
  void paint(Canvas canvas, Size size) {
    // walking-path region used by HazardPolicy (x 0.2–0.8, bottom edge below 0.5)
    final path = Paint()
      ..color = SafeStepColors.accent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(size.width * 0.2, size.height * 0.5, size.width * 0.8, size.height), path);
    for (final d in dets) {
      final p = Paint()
        ..color = d.cls.critical ? SafeStepColors.danger : SafeStepColors.ok
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final r = Rect.fromLTRB(d.x1 * size.width, d.y1 * size.height, d.x2 * size.width, d.y2 * size.height);
      canvas.drawRect(r, p);
      final tp = TextPainter(
        text: TextSpan(text: '${d.cls.wire} ${(d.score * 100).round()}%', style: TextStyle(color: p.color, fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topLeft - const Offset(0, 18));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.dets != dets;
}
