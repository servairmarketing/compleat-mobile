import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// MainActivity. SECOND FEED (Joe's ruling 2026-09-25, after his non-Zebra
/// scanner reported the trigger as hardware key 563): the scan-trigger KEY
/// itself — down arms the detector, up starts the grace window — so a
/// device without DataWedge gets the same no-read = skip. The key code is
/// configurable ([ScannerStatusService.triggerKeyCode], Settings → Scanner,
/// default [kDefaultTriggerKeyCode]) and always visible in the diagnostics.
/// Both feeds drive ONE detector, which fires at most once per pull.
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

/// Hardware key code of the scan trigger on Joe's non-Zebra test scanner
/// (VERIFIED from the Receive diag line 2026-09-25: "last key 563(563) down").
/// A default, not a rule — see [ScannerStatusService.triggerKeyCode].
const int kDefaultTriggerKeyCode = 563;
const String kTriggerKeyCodePref = 'scanner_trigger_keycode';

class ScannerStatusService {
  ScannerStatusService._();
  static final ScannerStatusService instance = ScannerStatusService._();

  static const EventChannel _channel = EventChannel('com.compleat/scanner_status');

  /// The key code treated as the scan trigger. Persisted in SharedPreferences;
  /// [loadTriggerKeyCode] reads it once, [setTriggerKeyCode] saves it.
  int triggerKeyCode = kDefaultTriggerKeyCode;
  bool _prefLoaded = false;

  Future<int> loadTriggerKeyCode() async {
    if (_prefLoaded) return triggerKeyCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      triggerKeyCode = prefs.getInt(kTriggerKeyCodePref) ?? kDefaultTriggerKeyCode;
    } catch (_) {
      triggerKeyCode = kDefaultTriggerKeyCode;
    }
    _prefLoaded = true;
    return triggerKeyCode;
  }

  Future<void> setTriggerKeyCode(int code) async {
    triggerKeyCode = code;
    _prefLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kTriggerKeyCodePref, code);
    } catch (_) {}
  }

  bool isTriggerKey(ScannerEvent e) => e.isKey && e.keyCode == triggerKeyCode;

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
/// Two feeds, one detector:
///   * DataWedge (Zebra): [onStatus] — SCANNING arms (beam on), WAITING/IDLE
///     is beam-off.
///   * Trigger key (any device that delivers the scan button as a hardware
///     key): [onTriggerDown] arms, [onTriggerUp] is beam-off. Key repeats
///     while held are ignored by the caller.
/// Call [noteInput] whenever ANY text arrives in the entry fields.
/// A no-read is: armed, then beam-off, with no input while armed and none
/// within [grace] after beam-off — the grace window covers keystrokes still
/// being delivered after the beam went off on a REAL decode, so a successful
/// scan never counts. Beam-off only acts while armed and always disarms, so a
/// device that reports BOTH feeds (a Zebra whose trigger key is also visible)
/// still fires [onNoRead] at most once per pull.
class NoReadDetector {
  NoReadDetector({required this.onNoRead, this.grace = const Duration(milliseconds: 400)});

  final void Function() onNoRead;
  final Duration grace;

  bool _armed = false;       // beam is on (SCANNING seen / trigger key down)
  bool _inputSeen = false;   // any text arrived since the beam came on
  Timer? _timer;

  /// Number of no-reads detected (diagnostics).
  int noReads = 0;

  bool get isArmed => _armed;

  void _arm() {
    _timer?.cancel();
    _timer = null;
    _armed = true;
    _inputSeen = false;
  }

  void _beamOff() {
    if (!_armed) return;                    // not our pull (or already handled)
    _armed = false;
    if (_inputSeen) return;                 // real decode, data already here
    _timer?.cancel();
    _timer = Timer(grace, () {
      _timer = null;
      if (_inputSeen) return;               // data arrived just after beam-off
      noReads++;
      onNoRead();
    });
  }

  void _standDown() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
  }

  /// DataWedge SCANNER_STATUS feed.
  void onStatus(String status) {
    final s = status.toUpperCase();
    if (s == 'SCANNING') { _arm(); return; }
    if (s == 'WAITING' || s == 'IDLE') { _beamOff(); return; }
    // CONNECTED / DISCONNECTED / DISABLED / anything else: stand down.
    _standDown();
  }

  /// Trigger-key feed: the scan button went down (repeat events excluded).
  void onTriggerDown() => _arm();

  /// Trigger-key feed: the scan button was released.
  void onTriggerUp() => _beamOff();

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
