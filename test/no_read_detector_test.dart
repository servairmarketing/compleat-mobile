import 'package:flutter_test/flutter_test.dart';
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

  test('isTriggerKey follows the configured code (default 563)', () {
    final svc = ScannerStatusService.instance;
    expect(svc.triggerKeyCode, kDefaultTriggerKeyCode);
    final k563 = ScannerEvent(type: 'key', keyCode: 563, action: 0, at: DateTime.now());
    final k104 = ScannerEvent(type: 'key', keyCode: 104, action: 0, at: DateTime.now());
    final st = ScannerEvent(type: 'status', status: 'SCANNING', at: DateTime.now());
    expect(svc.isTriggerKey(k563), true);
    expect(svc.isTriggerKey(k104), false);
    expect(svc.isTriggerKey(st), false);
    svc.triggerKeyCode = 104;
    expect(svc.isTriggerKey(k104), true);
    expect(svc.isTriggerKey(k563), false);
    svc.triggerKeyCode = kDefaultTriggerKeyCode;
  });
}
