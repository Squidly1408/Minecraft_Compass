import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Number of frames in assets/frames (frame_01.png ... frame_64.png).
const int kFrameCount = 64;

/// Screen angle (degrees clockwise from straight up) of the needle tip in
/// frame_01. The frames start with the needle pointing down.
const double kFirstFrameAngle = 180.0;

/// Whether each next frame turns the needle clockwise.
const bool kFramesClockwise = true;

String framePath(int index) =>
    'assets/frames/frame_${(index + 1).toString().padLeft(2, '0')}.png';

/// Maps a needle screen angle (degrees clockwise from up) to a frame index.
int frameForAngle(double angle) {
  const step = 360.0 / kFrameCount;
  var rel = angle - kFirstFrameAngle;
  if (!kFramesClockwise) rel = -rel;
  return (rel / step).round() % kFrameCount;
}

/// Degrees in [-180, 180) to turn from [from] to reach [to].
double shortestDelta(double from, double to) =>
    ((to - from) % 360 + 540) % 360 - 180;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CompassApp());
}

class CompassApp extends StatelessWidget {
  const CompassApp({super.key, this.events});

  /// Compass events; defaults to the device magnetometer. Overridable for tests.
  final Stream<CompassEvent>? events;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Compass',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: CompassScreen(events: events),
    );
  }
}

class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key, this.events});

  final Stream<CompassEvent>? events;

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<CompassEvent>? _sub;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  double? _heading; // degrees, phone top relative to magnetic north
  double? _accuracy;
  bool _noSensor = false;

  // Needle state: screen angle (deg, clockwise from up) and angular velocity.
  double _needle = kFirstFrameAngle;
  double _velocity = 0;
  bool _precached = false;

  // Spring tuning: stiffness and damping (under-damped so it wobbles).
  static const double _stiffness = 90;
  static const double _damping = 9;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    final events = widget.events ?? FlutterCompass.events;
    if (events == null) {
      _noSensor = true;
    } else {
      _sub = events.listen(
        (e) => setState(() {
          _heading = e.heading;
          _accuracy = e.accuracy;
          _noSensor = e.heading == null;
        }),
        onError: (_) => setState(() => _noSensor = true),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      for (var i = 0; i < kFrameCount; i++) {
        precacheImage(AssetImage(framePath(i)), context);
      }
    }
  }

  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _lastTick).inMicroseconds / 1e6, 0.05);
    _lastTick = elapsed;
    if (dt <= 0) return;

    final previousFrame = frameForAngle(_needle);
    if (_heading == null) {
      // No sensor: spin like a Minecraft compass outside the Overworld.
      _velocity = 0;
      _needle = (_needle + 360 * dt) % 360;
    } else {
      // North sits at -heading on screen; pull the needle there on a spring.
      final error = shortestDelta(_needle, -_heading!);
      _velocity += (_stiffness * error - _damping * _velocity) * dt;
      _needle = (_needle + _velocity * dt) % 360;
    }
    if (frameForAngle(_needle) != previousFrame) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = frameForAngle(_needle);
    final heading = _heading;
    final lowAccuracy = _accuracy != null && _accuracy! > 30;

    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text(
              heading == null ? '--' : '${heading.round() % 360}°',
              style: _pixelText(48),
            ),
            Text(
              heading == null ? '' : cardinal(heading),
              style: _pixelText(24, color: const Color(0xFFFFFF55)),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = math.min(c.maxWidth, c.maxHeight) * 0.85;
                    return Image.asset(
                      framePath(frame),
                      width: side,
                      height: side,
                      filterQuality: FilterQuality.none,
                      gaplessPlayback: true,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Text(
                _noSensor
                    ? 'No compass sensor found'
                    : lowAccuracy
                        ? 'Low accuracy: wave your phone in a figure 8'
                        : 'Needle points to magnetic north',
                textAlign: TextAlign.center,
                style: _pixelText(
                  16,
                  color: _noSensor || lowAccuracy
                      ? const Color(0xFFFF5555)
                      : const Color(0xFFAAAAAA),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String cardinal(double heading) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return names[((heading % 360) / 45).round() % 8];
}

TextStyle _pixelText(double size, {Color color = Colors.white}) => TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      fontWeight: FontWeight.bold,
      color: color,
      shadows: const [Shadow(color: Color(0xFF3F3F3F), offset: Offset(2, 2))],
    );
