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
/// configurable as a SET ([ScannerStatusService.triggerKeyCodes], Settings → Scanner,
/// default [kDefaultTriggerKeyCodes] = both buttons of Joe's scanner) and always
/// visible in the diagnostics.
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
  final String src;             // 'native' (MainActivity.dispatchKeyEvent / DataWedge) | 'dart' (Flutter HardwareKeyboard)
  final int keyId;              // for 'dart' keys: the raw Flutter LogicalKeyboardKey.keyId
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
    this.src = 'native',
    this.keyId = -1,
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
      ? 'key $keyName($keyCode) ${action == 0 ? 'down' : action == 1 ? 'up' : action} scan=$scanCode via $src'
      : isStatus
          ? 'status $status${profile.isEmpty ? '' : ' [$profile]'}'
          : type;
}

/// Android key code carried inside a Flutter [LogicalKeyboardKey.keyId] when
/// the key has no Flutter mapping (the embedder emits `keyCode | androidPlane`
/// — VERIFIED for the framework's Android key mapping in
/// raw_keyboard_android.dart). Returns -1 for keys from any other plane, so a
/// mapped key never masquerades as an Android code.
int androidKeyCodeFromKeyId(int keyId) {
  const int planeMask = ~0xFFFFFFFF;
  if ((keyId & planeMask) != LogicalKeyboardKey.androidPlane) return -1;
  return keyId & 0xFFFFFFFF;
}

/// Why the scanner listener is (not) running — shown verbatim in the TEST
/// diagnostics so a "not listening" report explains itself.
enum ScannerListenState {
  idle,         // nobody has asked for events yet
  starting,     // 'listen' sent to the native plugin, no answer yet
  listening,    // native plugin answered: receiver registered, keys forwarded
  noReply,      // native never answered within the ack window (plugin missing?)
  unavailable,  // not Android / web — nothing to listen to
  error,        // the platform stream reported an error (details in reason)
  closed,       // the platform closed the stream (details in reason)
}

/// Hardware key codes of the scan trigger(s). Joe's non-Zebra test scanner
/// has TWO scan buttons: 563 (VERIFIED from the Receive diag 2026-09-25) and
/// 564 (VERIFIED by Joe the same day — setting 564 made the skip fire). A
/// default SET, not a rule — see [ScannerStatusService.triggerKeyCodes].
const Set<int> kDefaultTriggerKeyCodes = {563, 564};
const String kTriggerKeyCodesPref = 'scanner_trigger_keycodes';        // StringList of ints (v1.0.78+)
const String kLegacyTriggerKeyCodePref = 'scanner_trigger_keycode';    // single int (v1.0.75–77), migrated once

class ScannerStatusService {
  ScannerStatusService._();
  static final ScannerStatusService instance = ScannerStatusService._();

  static const EventChannel _channel = EventChannel('com.compleat/scanner_status');

  /// The key codes treated as the scan trigger (any of them). Persisted in
  /// SharedPreferences; [loadTriggerKeyCodes] reads once, the setters save.
  Set<int> triggerKeyCodes = {...kDefaultTriggerKeyCodes};
  bool _prefLoaded = false;

  /// "563, 564" — sorted, for the diagnostics and the settings screen.
  String get triggerKeysText =>
      triggerKeyCodes.isEmpty ? 'none (trigger-skip off)' : (triggerKeyCodes.toList()..sort()).join(', ');

  Future<Set<int>> loadTriggerKeyCodes() async {
    if (_prefLoaded) return triggerKeyCodes;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(kTriggerKeyCodesPref);
      if (saved != null) {
        triggerKeyCodes = saved.map(int.tryParse).whereType<int>().toSet();
      } else {
        // First run on this build: start from the defaults and keep a code the
        // operator saved on v1.0.75–77 (single-key setting), then retire it.
        triggerKeyCodes = {...kDefaultTriggerKeyCodes};
        final legacy = prefs.getInt(kLegacyTriggerKeyCodePref);
        if (legacy != null) {
          triggerKeyCodes.add(legacy);
          await prefs.setStringList(kTriggerKeyCodesPref, _encode(triggerKeyCodes));
          await prefs.remove(kLegacyTriggerKeyCodePref);
        }
      }
    } catch (_) {
      triggerKeyCodes = {...kDefaultTriggerKeyCodes};
    }
    _prefLoaded = true;
    _notify();
    return triggerKeyCodes;
  }

  static List<String> _encode(Set<int> codes) => (codes.toList()..sort()).map((c) => '$c').toList();

  Future<void> setTriggerKeyCodes(Set<int> codes) async {
    triggerKeyCodes = codes.where((c) => c >= 0).toSet();
    _prefLoaded = true;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kTriggerKeyCodesPref, _encode(triggerKeyCodes));
    } catch (_) {}
  }

  Future<void> addTriggerKeyCode(int code) => setTriggerKeyCodes({...triggerKeyCodes, code});
  Future<void> removeTriggerKeyCode(int code) => setTriggerKeyCodes({...triggerKeyCodes}..remove(code));
  Future<void> resetTriggerKeyCodes() => setTriggerKeyCodes({...kDefaultTriggerKeyCodes});

  bool isTriggerKey(ScannerEvent e) => e.isKey && triggerKeyCodes.contains(e.keyCode);

  final StreamController<ScannerEvent> _out = StreamController<ScannerEvent>.broadcast();
  StreamSubscription<dynamic>? _platformSub;
  Timer? _ackTimer;
  bool _dartKeysHooked = false;

  /// How long we wait for the native plugin's 'listening' answer before
  /// declaring [ScannerListenState.noReply].
  static const Duration ackWindow = Duration(seconds: 3);

  // ── Listener state — DURABLE (v1.0.77 fix). Before this, "listening" was a
  // one-shot event consumed by whichever screen subscribed first (the new
  // Scanner Settings screen, or an earlier Receive visit), so the Receive
  // diag read "not listening" with no reason. Now the state lives here, every
  // screen reads it, and a dead stream restarts on the next subscriber.
  ScannerListenState state = ScannerListenState.idle;
  String reason = '';
  DateTime? stateAt;
  int nativeEvents = 0;      // everything the native plugin delivered
  int nativeKeyEvents = 0;
  int statusEvents = 0;
  int dartKeyEvents = 0;     // keys seen by Flutter's own HardwareKeyboard
  ScannerEvent? lastKey;     // last key from EITHER feed (repeats excluded)
  ScannerEvent? lastStatus;

  /// Bumped on every state/counter change so screens can `setState`.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  bool get isListening => state == ScannerListenState.listening;

  /// Plain-words state for the diagnostics line, always with the WHY.
  String get stateText {
    final when = stateAt == null ? '' : ' ${_hhmmss(stateAt!)}';
    switch (state) {
      case ScannerListenState.idle:
        return 'not listening — not started yet';
      case ScannerListenState.starting:
        return 'starting — listen sent to native$when, no reply yet';
      case ScannerListenState.listening:
        return 'listening (native ok$when)';
      case ScannerListenState.noReply:
        return 'NOT listening — native plugin never answered within ${ackWindow.inSeconds} s (plugin missing in this build?)';
      case ScannerListenState.unavailable:
        return 'NOT listening — $reason';
      case ScannerListenState.error:
        return 'NOT listening — platform stream error$when: $reason';
      case ScannerListenState.closed:
        return 'NOT listening — platform closed the stream$when: $reason';
    }
  }

  /// One-line counters for the diagnostics.
  String get countersText =>
      'rx native ${nativeEvents} (keys ${nativeKeyEvents}, status ${statusEvents}) · dart keys ${dartKeyEvents}';

  static String _hhmmss(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _setState(ScannerListenState s, [String why = '']) {
    state = s;
    reason = why;
    stateAt = DateTime.now();
    _notify();
  }

  void _notify() {
    if (!_out.isClosed) changes.value = changes.value + 1;
  }

  /// Broadcast stream of scanner status + key events. Silent when no
  /// DataWedge / no native plugin is present. Each subscriber (re)starts the
  /// platform stream if it is not currently alive.
  Stream<ScannerEvent> get events {
    _ensureStarted();
    return _out.stream;
  }

  void _ensureStarted() {
    _hookDartKeys();
    if (state == ScannerListenState.starting || state == ScannerListenState.listening) return;
    if (state == ScannerListenState.unavailable) return;
    if (kIsWeb) { _setState(ScannerListenState.unavailable, 'web build has no scanner plugin'); return; }
    try {
      if (!Platform.isAndroid) { _setState(ScannerListenState.unavailable, 'not an Android device'); return; }
    } catch (err) {
      _setState(ScannerListenState.unavailable, 'platform unknown ($err)');
      return;
    }
    _startPlatformStream();
  }

  void _startPlatformStream() {
    _platformSub?.cancel();
    _platformSub = null;
    _ackTimer?.cancel();
    try {
      _platformSub = _channel.receiveBroadcastStream().listen(
        _onPlatformEvent,
        // MissingPluginException / PlatformException on a build without the
        // native side: the feature just stays off — but SAY SO.
        onError: (Object err) {
          debugPrint('ScannerStatusService: $err');
          _ackTimer?.cancel();
          _setState(ScannerListenState.error, '$err');
        },
        onDone: () {
          debugPrint('ScannerStatusService: platform stream closed');
          _ackTimer?.cancel();
          if (state != ScannerListenState.error) {
            _setState(ScannerListenState.closed, 'end of stream from native (will restart on next screen open)');
          }
        },
        cancelOnError: true,
      );
      _setState(ScannerListenState.starting);
      _ackTimer = Timer(ackWindow, () {
        if (state == ScannerListenState.starting) _setState(ScannerListenState.noReply);
      });
    } catch (err) {
      debugPrint('ScannerStatusService: unavailable ($err)');
      _setState(ScannerListenState.error, 'listen threw: $err');
    }
  }

  void _onPlatformEvent(dynamic raw) {
    final e = ScannerEvent.fromPlatform(raw);
    if (e == null) return;
    nativeEvents++;
    if (e.type == 'listening') {
      _ackTimer?.cancel();
      _setState(ScannerListenState.listening);
    } else if (e.isKey) {
      nativeKeyEvents++;
      if (e.repeat == 0) lastKey = e;
    } else if (e.isStatus) {
      statusEvents++;
      lastStatus = e;
    }
    if (!_out.isClosed) _out.add(e);
    _notify();
  }

  // ── Dart key feed (v1.0.77). Flutter's HardwareKeyboard sees every key the
  // framework receives, INCLUDING keys handed over by the input method through
  // the text-input connection — those never pass MainActivity.dispatchKeyEvent,
  // so a keyboard-wedge scanner that talks to the focused text field can be
  // invisible to the native feed while a field has the cursor. Unmapped Android
  // key codes arrive as `keyCode | androidPlane`, so key 563 is still 563 here.
  // Both feeds land in the same stream; the detector is idempotent per pull.
  void _hookDartKeys() {
    if (_dartKeysHooked) return;
    _dartKeysHooked = true;
    try {
      HardwareKeyboard.instance.addHandler(_onDartKey);
    } catch (err) {
      debugPrint('ScannerStatusService: HardwareKeyboard hook failed ($err)');
    }
  }

  bool _onDartKey(KeyEvent k) {
    try {
      final id = k.logicalKey.keyId;
      final code = androidKeyCodeFromKeyId(id);
      final e = ScannerEvent(
        type: 'key',
        keyCode: code >= 0 ? code : id,
        keyName: code >= 0 ? 'android' : (k.logicalKey.keyLabel.isNotEmpty ? k.logicalKey.keyLabel : 'flutter'),
        action: k is KeyUpEvent ? 1 : 0,
        scanCode: androidKeyCodeFromKeyId(k.physicalKey.usbHidUsage),
        repeat: k is KeyRepeatEvent ? 1 : 0,
        src: 'dart',
        keyId: id,
        at: DateTime.now(),
      );
      dartKeyEvents++;
      if (e.repeat == 0) lastKey = e;
      if (!_out.isClosed) _out.add(e);
      _notify();
    } catch (err) {
      debugPrint('ScannerStatusService: dart key failed ($err)');
    }
    return false;   // never consume — the field still gets the key as before
  }

  /// Test seam: push an event as if it came from the platform.
  @visibleForTesting
  void inject(ScannerEvent e) => _onPlatformEvent({
        'type': e.type, 'status': e.status, 'profile': e.profile, 'keyCode': e.keyCode,
        'keyName': e.keyName, 'action': e.action, 'scanCode': e.scanCode, 'repeat': e.repeat,
        't': e.at.millisecondsSinceEpoch,
      });

  @visibleForTesting
  Future<void> reset() async {
    _ackTimer?.cancel();
    await _platformSub?.cancel();
    _platformSub = null;
    _prefLoaded = false;
    triggerKeyCodes = {...kDefaultTriggerKeyCodes};
    state = ScannerListenState.idle;
    reason = '';
    stateAt = null;
    nativeEvents = nativeKeyEvents = statusEvents = dartKeyEvents = 0;
    lastKey = null;
    lastStatus = null;
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
