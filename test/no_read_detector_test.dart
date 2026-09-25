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
}
