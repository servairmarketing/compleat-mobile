import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:compleat_mobile/services/scanner_status_service.dart';

void main() {
  const grace = Duration(milliseconds: 30);
  Future<void> settle() => Future<void>.delayed(grace * 3);

  test('SCANNING then WAITING with no input = one no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onStatus('WAITING');
    expect(fired, 0, reason: 'fires only after the grace window');
    await settle();
    expect(fired, 1);
    expect(d.noReads, 1);
  });

  test('IDLE after SCANNING counts as beam-off too', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('scanning');
    d.onStatus('idle');
    await settle();
    expect(fired, 1);
  });

  test('a real decode (input during the beam) is never a no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.noteInput();
    d.onStatus('WAITING');
    await settle();
    expect(fired, 0);
  });

  test('keystrokes landing just after beam-off (inside grace) cancel the no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onStatus('WAITING');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    d.noteInput();
    await settle();
    expect(fired, 0);
  });

  test('WAITING without a preceding SCANNING does nothing', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('WAITING');
    d.onStatus('WAITING');
    await settle();
    expect(fired, 0);
  });

  test('DISABLED / DISCONNECTED stand the detector down', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onStatus('DISABLED');
    d.onStatus('WAITING');
    await settle();
    expect(fired, 0);
  });

  test('a second pull while the first grace runs re-arms cleanly (one no-read each)', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onStatus('WAITING');
    d.onStatus('SCANNING');   // pulled again before the grace expired
    d.onStatus('WAITING');
    await settle();
    expect(fired, 1, reason: 'the first window was superseded, the second fires');
    d.onStatus('SCANNING');
    d.onStatus('WAITING');
    await settle();
    expect(fired, 2);
  });

  test('input outside any pull does not affect the next pull', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.noteInput();            // operator typed something earlier
    d.onStatus('SCANNING');   // inputSeen resets here
    d.onStatus('WAITING');
    await settle();
    expect(fired, 1);
  });

  test('dispose cancels a pending no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onStatus('WAITING');
    d.dispose();
    await settle();
    expect(fired, 0);
  });

  // ── trigger-key feed (Joe's ruling 2026-09-25, key 563 on his non-Zebra scanner) ──

  test('trigger down then up with no input = one no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerDown();
    d.onTriggerUp();
    expect(fired, 0);
    await settle();
    expect(fired, 1);
  });

  test('trigger down, characters arrive (real scan), then up = no no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerDown();
    d.noteInput();
    d.onTriggerUp();
    await settle();
    expect(fired, 0);
  });

  test('characters landing inside the grace after trigger-up cancel the no-read', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerDown();
    d.onTriggerUp();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    d.noteInput();
    await settle();
    expect(fired, 0);
  });

  test('trigger up without a preceding down does nothing', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerUp();
    await settle();
    expect(fired, 0);
  });

  test('a device reporting BOTH feeds fires once per pull (key first)', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerDown();
    d.onStatus('SCANNING');
    d.onTriggerUp();          // beam-off → grace timer, disarmed
    d.onStatus('WAITING');    // not armed any more → ignored
    await settle();
    expect(fired, 1);
  });

  test('a device reporting BOTH feeds fires once per pull (status first)', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onStatus('SCANNING');
    d.onTriggerDown();
    d.onStatus('WAITING');
    d.onTriggerUp();
    await settle();
    expect(fired, 1);
  });

  test('a late SCANNING after the key already fired does not double-fire', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    d.onTriggerDown();
    d.onTriggerUp();
    await settle();
    expect(fired, 1);
    d.onStatus('WAITING');    // stray beam-off, nothing armed
    await settle();
    expect(fired, 1);
  });

  test('ScannerEvent.fromPlatform parses status and key payloads, rejects junk', () {
    final s = ScannerEvent.fromPlatform({'type': 'status', 'status': 'scanning', 'profile': 'Profile0', 't': 1000});
    expect(s!.isStatus, true);
    expect(s.status, 'SCANNING');
    expect(s.profile, 'Profile0');
    final k = ScannerEvent.fromPlatform({'type': 'key', 'keyCode': 103, 'keyName': 'KEYCODE_BUTTON_L1', 'action': 0, 'scanCode': 254, 'repeat': 0, 't': 1000});
    expect(k!.isKey, true);
    expect(k.toString(), contains('KEYCODE_BUTTON_L1(103) down'));
    expect(ScannerEvent.fromPlatform('nope'), isNull);
    expect(ScannerEvent.fromPlatform(null), isNull);
  });

  test('androidKeyCodeFromKeyId: Android-plane ids yield the key code, other planes -1', () {
    expect(androidKeyCodeFromKeyId(LogicalKeyboardKey.androidPlane | 563), 563);
    expect(androidKeyCodeFromKeyId(LogicalKeyboardKey.androidPlane | 103), 103);
    expect(androidKeyCodeFromKeyId(LogicalKeyboardKey.enter.keyId), -1);
    expect(androidKeyCodeFromKeyId(LogicalKeyboardKey.keyA.keyId), -1);
  });

  test('a dart-fed trigger key (keyCode 563 via dart) is a trigger key too', () {
    final svc = ScannerStatusService.instance;
    final dart563 = ScannerEvent(type: 'key', keyCode: 563, action: 0, src: 'dart',
        keyId: LogicalKeyboardKey.androidPlane | 563, at: DateTime.now());
    expect(svc.isTriggerKey(dart563), true);
    expect(dart563.toString(), contains('via dart'));
  });

  test('listener state is durable and self-explaining (not Android here)', () async {
    final svc = ScannerStatusService.instance;
    await svc.reset();
    expect(svc.state, ScannerListenState.idle);
    expect(svc.stateText, contains('not started'));
    svc.events;                                   // a screen subscribes
    expect(svc.state, ScannerListenState.unavailable, reason: 'flutter test runs on the host, not Android');
    expect(svc.stateText, contains('NOT listening'));
    expect(svc.reason.isNotEmpty, true);
    final before = svc.changes.value;
    svc.inject(ScannerEvent(type: 'key', keyCode: 563, action: 0, at: DateTime.now()));
    expect(svc.nativeEvents, 1);
    expect(svc.nativeKeyEvents, 1);
    expect(svc.lastKey?.keyCode, 563);
    expect(svc.changes.value, greaterThan(before));
    expect(svc.countersText, contains('keys 1'));
    await svc.reset();
  });

  test('isTriggerKey follows the configured SET (default 563 + 564)', () async {
    final svc = ScannerStatusService.instance;
    await svc.reset();
    expect(svc.triggerKeyCodes, kDefaultTriggerKeyCodes);
    expect(svc.triggerKeysText, '563, 564');
    ScannerEvent key(int c, int action) => ScannerEvent(type: 'key', keyCode: c, action: action, at: DateTime.now());
    final st = ScannerEvent(type: 'status', status: 'SCANNING', at: DateTime.now());
    expect(svc.isTriggerKey(key(563, 0)), true);
    expect(svc.isTriggerKey(key(564, 0)), true);
    expect(svc.isTriggerKey(key(104, 0)), false);
    expect(svc.isTriggerKey(st), false);
    await svc.addTriggerKeyCode(104);
    expect(svc.isTriggerKey(key(104, 0)), true);
    expect(svc.triggerKeysText, '104, 563, 564');
    await svc.removeTriggerKeyCode(563);
    expect(svc.isTriggerKey(key(563, 0)), false);
    expect(svc.isTriggerKey(key(564, 0)), true);
    await svc.removeTriggerKeyCode(564);
    await svc.removeTriggerKeyCode(104);
    expect(svc.triggerKeyCodes, isEmpty);
    expect(svc.triggerKeysText, contains('off'));
    await svc.resetTriggerKeyCodes();
    expect(svc.triggerKeyCodes, kDefaultTriggerKeyCodes);
    await svc.reset();
  });

  test('either scan button gives exactly one no-read per pull', () async {
    var fired = 0;
    final d = NoReadDetector(onNoRead: () => fired++, grace: grace);
    // button 563
    d.onTriggerDown();
    d.onTriggerUp();
    await settle();
    expect(fired, 1);
    // button 564 — same detector, same behaviour
    d.onTriggerDown();
    d.onTriggerUp();
    await settle();
    expect(fired, 2);
    // both buttons pressed in one pull (down 563, down 564, up 564, up 563)
    d.onTriggerDown();
    d.onTriggerDown();
    d.onTriggerUp();
    d.onTriggerUp();
    await settle();
    expect(fired, 3, reason: 'second down only re-arms, second up finds nothing armed');
  });

  test('loadTriggerKeyCodes: defaults, saved list, and legacy single-key migration', () async {
    final svc = ScannerStatusService.instance;

    SharedPreferences.setMockInitialValues({});
    await svc.reset();
    expect(await svc.loadTriggerKeyCodes(), kDefaultTriggerKeyCodes);

    SharedPreferences.setMockInitialValues({kTriggerKeyCodesPref: ['103', 'junk', '563']});
    await svc.reset();
    expect(await svc.loadTriggerKeyCodes(), {103, 563});

    // v1.0.75–77 saved one code (Joe saved 564): keep it AND the defaults, retire the old key.
    SharedPreferences.setMockInitialValues({kLegacyTriggerKeyCodePref: 564});
    await svc.reset();
    expect(await svc.loadTriggerKeyCodes(), {563, 564});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(kTriggerKeyCodesPref), ['563', '564']);
    expect(prefs.getInt(kLegacyTriggerKeyCodePref), isNull);

    SharedPreferences.setMockInitialValues({kLegacyTriggerKeyCodePref: 999});
    await svc.reset();
    expect(await svc.loadTriggerKeyCodes(), {563, 564, 999});
    await svc.reset();
  });
}
