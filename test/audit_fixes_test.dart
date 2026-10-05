import 'dart:convert';
import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  group('without the national number', () {
    test('returns no signature that would give it away', () async {
      final eid = await BelgianEidReader(SimulatedBelgianCard()).read(
        parts: {BelgianEidPart.address, BelgianEidPart.signatures},
      );
      expect(eid.signaturesVerified, isTrue);
      expect(eid.identitySignature, isNull);
      expect(eid.addressSignature, isNull);
    });

    test('keeps it out of onApdu', () async {
      final exchanges = <ApduExchange>[];
      await BelgianEidReader(SimulatedBelgianCard(), onApdu: exchanges.add)
          .read(parts: {});
      final logged = exchanges.map((e) => '$e').join();
      expect(logged, isNot(contains(hexString(utf8.encode('90051512391')))));
    });
  });

  test('skips the chip proof when the signatures are not checked', () async {
    final eid = await BelgianEidReader(SimulatedBelgianCard(cloned: true))
        .read(verifySignatures: false);
    expect(eid.authenticity, isNull);
  });

  group('certificates', () {
    test('tell a CA from a holder', () async {
      final certificates =
          await BelgianEidReader(SimulatedBelgianCard()).readCertificates();
      expect(certificates.root!.isCa, isTrue);
      expect(certificates.ca!.isCa, isTrue);
      expect(certificates.authentication!.isCa, isFalse);
      expect(certificates.nationalRegister!.isCa, isFalse);
    });

    test('never chain through a certificate that is not a CA', () async {
      final certificates =
          await BelgianEidReader(SimulatedBelgianCard()).readCertificates();
      final verifier = BelgianSignatureVerifier(
        trustedRoots: [SimulatedBelgianCard.rootCertificate],
      );
      await expectLater(
        verifier.verifyCertificateChain(
          certificates.signing!.der,
          intermediates: [certificates.authentication!.der],
        ),
        throwsA(isA<BelgianSignatureException>()),
      );
    });

    test('are read to their length, not their padding', () async {
      final exchanges = <ApduExchange>[];
      final reader =
          BelgianEidReader(SimulatedBelgianCard(), onApdu: exchanges.add);
      final der = await reader
          .readCertificate(BelgianEidFile.nationalRegisterCertificate);
      final reads = exchanges.where((e) => e.command[1] == 0xB0).length;
      // About 420 bytes: two blocks, perhaps a resend for the last one.
      expect(der, isNotNull);
      expect(reads, lessThanOrEqualTo(3));
    });
  });

  group('watcher', () {
    late SimulatedBelgianCard card;
    late BelgianEidWatcher watcher;
    late List<BelgianEidEvent> events;
    const tick = Duration(milliseconds: 5);

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 400 && !done(); i++) {
        await Future<void>.delayed(tick);
      }
    }

    setUp(() {
      card = SimulatedBelgianCard()..remove();
      events = [];
    });

    tearDown(() => watcher.dispose());

    test('reports the card as removed when stopped', () async {
      watcher = BelgianEidWatcher(card, interval: tick)
        ..events.listen(events.add)
        ..start();
      card.insert();
      await until(() => events.whereType<BelgianCardRead>().isNotEmpty);
      await watcher.stop();
      await Future<void>.delayed(Duration.zero);
      expect(events.last, isA<BelgianCardRemoved>());
      expect(watcher.hasCard, isFalse);
    });

    test('shares one read, and one PIN prompt, between callers', () async {
      var prompts = 0;
      watcher = BelgianEidWatcher(
        card,
        autoRead: false,
        interval: tick,
        pinPrompt: (_) async {
          prompts++;
          await Future<void>.delayed(tick * 4);
          return '1234';
        },
      )
        ..events.listen(events.add)
        ..start();
      card.insert();
      await until(() => watcher.hasCard);

      final first = watcher.read();
      final second = watcher.read();
      expect(identical(await first, await second), isTrue);
      expect(prompts, 1);
      expect(card.pinTriesLeft, 3);
    });
  });

  group('BelgianPhotoCache', () {
    test('drops the least recently used photo past its capacity', () async {
      final cache = BelgianPhotoCache(capacity: 1);
      final alice = await BelgianEidReader(SimulatedBelgianCard())
          .read(photoCache: cache);
      expect(cache.length, 1);
      final other = Uint8List.fromList(List.generate(500, (i) => i % 251));
      await BelgianEidReader(SimulatedBelgianCard(photo: other))
          .read(photoCache: cache);
      expect(cache.length, 1);
      expect(cache.lookup(alice.identity), isNull);

      final none = BelgianPhotoCache(capacity: 0);
      await BelgianEidReader(SimulatedBelgianCard()).read(photoCache: none);
      expect(none.length, 0);
    });
  });
}
