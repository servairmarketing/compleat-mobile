import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Zebra DataWedge scanner-status bridge (Joe's ruling 2026-09-25, option 1 —
/// "no-read = skip").
///
/// Problem: DataWedge keystroke output sends NOTHING when the trigger is pulled
/// with no barcode to decode, so "Enter on an empty field skips it" never
/// fires from the scanner. The one documented signal is DataWedge's
/// Notification API (>= 6.4): SCANNER_STATUS changes — SCANNING when the beam
/// is on, WAITING (or IDLE) when it goes off. [NoReadDetector] turns
/// "SCANNING → WAITING with no keystrokes in between" into a no-read.
///
/// GRACEFUL DEGRADATION (Joe's requirement 1): on a device without DataWedge
/// the native side registers a receiver that never fires; on a platform
/// without our native plugin the channel throws once and we swallow it. In
/// both cases [events] simply stays silent — no crash, no delay, the keyboard
/// Enter keeps working as the skip.
///
/// Screens opt in (Receive today) by listening to [events] and feeding a
/// [NoReadDetector]. Also carries hardware KEY events forwarded by
/// MainActivity for the TC22 walkthrough diagnostics (does the trigger key
/// ever reach the app?).
class ScannerEvent {
  final String type;            // 'status' | 'key' | 'listening'
  final String status;          // for 'status': WAITING / SCANNING / IDLE / CONNECTED / DISCONNECTED / DISABLED
  final String profile;         // DataWedge profile name (status events)
  final int keyCode;            // for 'key'
  final String keyName;         // for 'key' (KEYCODE_… string)
  final int action;             // for 'key': 0 = down, 1 = up
  final int scanCode;           // for 'key'
  final int repeat;             // for 'key'
  final DateTime at;

  const ScannerEvent({
    required this.type,
    this.status = '',
    this.profile = '',
    this.keyCode = -1,
    this.keyName = '',
    this.action = -1,
    this.scanCode = -1,
    this.repeat = 0,
    required this.at,
  });

  bool get isStatus => type == 'status';
  bool get isKey => type == 'key';

  static ScannerEvent? fromPlatform(dynamic raw) {
    if (raw is! Map) return null;
    int i(dynamic v, [int d = -1]) => v is int ? v : (v is num ? v.toInt() : d);
    final t = i(raw['t'], 0);
    return ScannerEvent(
      type: '${raw['type'] ?? ''}',
      status: '${raw['status'] ?? ''}'.toUpperCase(),
      profile: '${raw['profile'] ?? ''}',
      keyCode: i(raw['keyCode']),
      keyName: '${raw['keyName'] ?? ''}',
      action: i(raw['action']),
      scanCode: i(raw['scanCode']),
      repeat: i(raw['repeat'], 0),
      at: t > 0 ? DateTime.fromMillisecondsSinceEpoch(t) : DateTime.now(),
    );
  }

  @override
  String toString() => isKey
      ? 'key $keyName($keyCode) ${action == 0 ? 'down' : action == 1 ? 'up' : action} scan=$scanCode'
      : isStatus
          ? 'status $status${profile.isEmpty ? '' : ' [$profile]'}'
          : type;
}

class ScannerStatusService {
  ScannerStatusService._();
  static final ScannerStatusService instance = ScannerStatusService._();

  static const EventChannel _channel = EventChannel('com.compleat/scanner_status');

  final StreamController<ScannerEvent> _out = StreamController<ScannerEvent>.broadcast();
  StreamSubscription<dynamic>? _platformSub;
  bool _started = false;

  /// Broadcast stream of scanner status + key events. Silent when no
  /// DataWedge / no native plugin is present.
  Stream<ScannerEvent> get events {
    _ensureStarted();
    return _out.stream;
  }

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid) return;
    } catch (_) {
      return;
    }
    try {
      _platformSub = _channel.receiveBroadcastStream().listen(
        (raw) {
          final e = ScannerEvent.fromPlatform(raw);
          if (e != null && !_out.isClosed) _out.add(e);
        },
        // MissingPluginException / PlatformException on a build without the
        // native side: swallow — the feature just stays off.
        onError: (Object err) => debugPrint('ScannerStatusService: $err'),
        cancelOnError: true,
      );
    } catch (err) {
      debugPrint('ScannerStatusService: unavailable ($err)');
    }
  }

  /// Test seam: push an event as if it came from the platform.
  @visibleForTesting
  void inject(ScannerEvent e) {
    _started = true;
    _out.add(e);
  }

  @visibleForTesting
  Future<void> reset() async {
    await _platformSub?.cancel();
    _platformSub = null;
    _started = false;
  }
}

/// Pure-Dart no-read detector (unit-tested, no Flutter dependency).
///
/// Feed it every SCANNER_STATUS change via [onStatus] and call [noteInput]
/// whenever ANY text arrives in the entry fields (controller listeners).
/// A no-read is: SCANNING (beam on) followed by WAITING or IDLE (beam off),
/// with no input during the beam and none within [grace] after it — the
/// grace window covers keystrokes DataWedge is still delivering after the
/// beam went off on a REAL decode, so a successful scan never counts as a
/// no-read. [onNoRead] fires at most once per pull.
class NoReadDetector {
  NoReadDetector({required this.onNoRead, this.grace = const Duration(milliseconds: 400)});

  final void Function() onNoRead;
  final Duration grace;

  bool _armed = false;       // beam is on (SCANNING seen)
  bool _inputSeen = false;   // any text arrived since the beam came on
  Timer? _timer;

  /// Number of no-reads detected (diagnostics).
  int noReads = 0;

  bool get isArmed => _armed;

  void onStatus(String status) {
    final s = status.toUpperCase();
    if (s == 'SCANNING') {
      _timer?.cancel();
      _timer = null;
      _armed = true;
      _inputSeen = false;
      return;
    }
    if ((s == 'WAITING' || s == 'IDLE') && _armed) {
      _armed = false;
      if (_inputSeen) return;               // real decode, data already here
      _timer?.cancel();
      _timer = Timer(grace, () {
        _timer = null;
        if (_inputSeen) return;             // data arrived just after beam-off
        noReads++;
        onNoRead();
      });
      return;
    }
    // CONNECTED / DISCONNECTED / DISABLED / anything else: stand down.
    _armed = false;
    _timer?.cancel();
    _timer = null;
  }

  void noteInput() {
    _inputSeen = true;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _armed = false;
  }
}
