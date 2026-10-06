import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('reads the whole card', () async {
    final card = fakeCard();
    final eid = await BelgianEidReader(card).read(
      verifySignatures: false,
      verifyCard: false,
      showPrivateData: true,
    );

    expect(eid.identity.lastName, 'Dupont');
    expect(eid.address?.municipality, 'Bruxelles');
    expect(eid.identitySignature, [0x30, 0x02, 0x01, 0x02]);
    expect(eid.addressSignature, [0x30, 0x02, 0x03, 0x04, 0, 0]);
    expect(eid.photo, photo);
    expect(eid.photoMatches, isTrue);
  });

  test('selects one file identifier at a time, from the master file', () async {
    final card = fakeCard();
    await BelgianEidReader(card).readAddress();
    // The file first, as when its directory is already selected, then the
    // whole path.
    expect(card.sent.take(4), [
      '00A4020C024033',
      '00A4020C023F00',
      '00A4020C02DF01',
      '00A4020C024033',
    ]);
  });

  test('leaves the photo out on request', () async {
    final card = fakeCard();
    final eid = await BelgianEidReader(card).read(
      verifySignatures: false,
      verifyCard: false,
      parts: BelgianEidPart.all.difference({BelgianEidPart.photo}),
    );
    expect(eid.photo, isNull);
    expect(eid.photoMatches, isFalse);
    expect(card.sent.where((c) => c.endsWith('4035')), isEmpty);
  });

  test('reads the identity file alone when no part is asked for', () async {
    final card = fakeCard();
    final eid = await BelgianEidReader(card).read(
      parts: {},
      verifySignatures: false,
      verifyCard: false,
    );
    expect(eid.identity.lastName, 'Dupont');
    expect(eid.identity.nationalNumber, isNull);
    expect(eid.identity.file, isNull);
    expect(eid.identity.fields.containsKey(0x06), isFalse);
    expect(eid.address, isNull);
    expect(eid.identitySignature, isNull);
    expect(eid.addressSignature, isNull);
    expect(eid.photo, isNull);
    final files = card.sent.where((c) => c.startsWith('00A4020C024'));
    expect(files.toSet(), {'00A4020C024031'});
  });

  test('leaves the national number out of everything it returns, by default',
      () async {
    final eid = await BelgianEidReader(fakeCard()).read(
      verifySignatures: false,
      verifyCard: false,
    );
    final identity = eid.identity;
    expect(identity.nationalNumber, isNull);
    expect(identity.file, isNull);
    final digits = '85073003328'.codeUnits;
    for (final field in identity.fields.values) {
      expect(String.fromCharCodes(field), isNot(contains('85073003328')));
      expect(field, isNot(digits));
    }
    // The rest of the card is still read, the photo checked.
    expect(eid.address?.municipality, 'Bruxelles');
    expect(eid.photoMatches, isTrue);
  });

  test('reads the national number only with the part and showPrivateData',
      () async {
    Future<BelgianEid> read(Set<BelgianEidPart> parts, {required bool show}) =>
        BelgianEidReader(fakeCard()).read(
          verifySignatures: false,
          verifyCard: false,
          parts: parts,
          showPrivateData: show,
        );
    final withoutPart =
        BelgianEidPart.all.difference({BelgianEidPart.nationalNumber});
    final noPart = await read(withoutPart, show: true);
    expect(noPart.identity.nationalNumber, isNull);
    final notShown = await read(BelgianEidPart.all, show: false);
    expect(notShown.identity.nationalNumber, isNull);
    expect(notShown.identitySignature, isNull);
    final both = await read(BelgianEidPart.all, show: true);
    expect(both.identity.nationalNumber, '85073003328');
    expect(both.identitySignature, isNotNull);
  });

  test('selects the Belpic applet again when another was left selected',
      () async {
    final card = fakeCard(otherAppletSelected: true);
    final identity = await BelgianEidReader(card).readIdentity();
    expect(identity.cardNumber, '592123456789');
    expect(card.sent, contains('00A404000FA00000003029057000AD13100101FF'));
  });

  test('reads a certificate without its padding', () async {
    final reader = BelgianEidReader(fakeCard());
    final certificate = await reader
        .readCertificate(BelgianEidFile.nationalRegisterCertificate);
    expect(certificate, hasLength(904));
    expect(certificate!.sublist(0, 4), [0x30, 0x82, 0x03, 0x84]);
  });

  test('reports a certificate the card was issued without', () async {
    final reader = BelgianEidReader(fakeCard());
    expect(
      await reader.readCertificate(BelgianEidFile.authenticationCertificate),
      isNull,
    );
  });

  test('refuses to read a file that is not a certificate as one', () {
    final reader = BelgianEidReader(fakeCard());
    expect(
      () => reader.readCertificate(BelgianEidFile.photo),
      throwsArgumentError,
    );
  });

  test('reads the card info', () async {
    final info = await BelgianEidReader(fakeCard()).readCardInfo();
    expect(info.serialNumber, List.generate(16, (i) => 0x50 + i));
    expect(info.appletVersion, 0x18);
    expect(info.isApplet18OrLater, isTrue);
    expect(info.globalOsVersion, 0x0001);
    expect(info.appletLifeCycle, 0x0F);
  });

  test('keeps overlapping reads from selecting under one another', () async {
    final reader = BelgianEidReader(fakeCard());
    final results = await Future.wait([
      reader.readIdentity(),
      reader.readAddress(),
      reader.readPhoto(),
    ]);
    expect((results[0] as BelgianIdentity).lastName, 'Dupont');
    expect((results[1] as BelgianAddress).postalCode, '1000');
    expect(results[2] as Uint8List, photo);
  });

  group('verifyPin', () {
    test('sends the PIN block the card expects', () async {
      final card = fakeCard();
      await BelgianEidReader(card).verifyPin('1234');
      expect(card.sent, ['0020000108241234FFFFFFFFFF']);
    });

    test('reports the tries left, then the block', () async {
      final card = fakeCard();
      final reader = BelgianEidReader(card);
      final isWrong = isA<PinException>();

      await expectLater(
        reader.verifyPin('0000'),
        throwsA(isWrong.having((e) => e.triesLeft, 'triesLeft', 2)),
      );
      await expectLater(
        reader.verifyPin('0000'),
        throwsA(isWrong.having((e) => e.triesLeft, 'triesLeft', 1)),
      );
      await expectLater(
        reader.verifyPin('0000'),
        throwsA(isWrong.having((e) => e.isBlocked, 'isBlocked', true)),
      );
      await expectLater(
        reader.verifyPin('1234'),
        throwsA(isWrong.having((e) => e.isBlocked, 'isBlocked', true)),
      );
    });

    test('refuses a malformed PIN without spending a try', () {
      final card = fakeCard();
      final reader = BelgianEidReader(card);
      for (final pin in ['123', '1234567890123', '12a4', '']) {
        expect(() => reader.verifyPin(pin), throwsArgumentError);
      }
      expect(card.sent, isEmpty);
    });

    test('writes a twelve digit PIN without padding', () async {
      final card = FakeBelpicCard({});
      await expectLater(
        BelgianEidReader(card).verifyPin('123456789012'),
        throwsA(isA<PinException>()),
      );
      expect(card.sent.single, '00200001082C123456789012FF');
    });
  });

  test('reports a file the card does not have', () async {
    final card = FakeBelpicCard({'3F00DF014031': identityFile()});
    await expectLater(
      BelgianEidReader(card).readAddress(),
      throwsA(
          isA<CardException>().having((e) => e.isNotFound, 'isNotFound', true)),
    );
  });

  group('turns down', () {
    test('an expired card, after its identity file only', () async {
      final card = SimulatedBelgianCard(validUntil: DateTime.utc(2020, 1, 31));
      final reader = BelgianEidReader(card);
      await expectLater(
        reader.read(),
        throwsA(
          isA<BelgianCardRejectedException>()
              .having((e) => e.reason, 'reason', BelgianCardRejection.expired)
              .having((e) => e.identity.lastName, 'name', 'Specimen'),
        ),
      );
      // Accepted when expired cards are.
      final eid = await reader.read(acceptExpired: true);
      expect(eid.identity.isExpired, isTrue);
    });

    test('a card of a type not accepted', () async {
      final card = SimulatedBelgianCard(
        documentType: BelgianDocumentType.euCard,
      );
      final reader = BelgianEidReader(card);
      await expectLater(
        reader.read(acceptedTypes: {BelgianDocumentType.eid}),
        throwsA(
          isA<BelgianCardRejectedException>().having(
            (e) => e.reason,
            'reason',
            BelgianCardRejection.documentType,
          ),
        ),
      );
      final eid = await reader.read(
        acceptedTypes: {BelgianDocumentType.eid, BelgianDocumentType.euCard},
      );
      expect(eid.identity.documentType, BelgianDocumentType.euCard);
    });
  });

  group('photoCache', () {
    test('takes a photo read before from the cache', () async {
      final cache = BelgianPhotoCache();
      final first = fakeCard();
      await BelgianEidReader(first).read(
        photoCache: cache,
        verifySignatures: false,
        verifyCard: false,
      );
      expect(cache.length, 1);

      final again = fakeCard();
      final eid = await BelgianEidReader(again).read(
        photoCache: cache,
        verifySignatures: false,
        verifyCard: false,
      );
      expect(eid.photo, photo);
      expect(eid.photoMatches, isTrue);
      expect(again.sent.where((c) => c.endsWith('4035')), isEmpty);
      // The address is read again: it changes when the holder moves.
      expect(again.sent.where((c) => c.endsWith('4033')), hasLength(1));
    });

    test('keeps only photos that match their hash, the latest first', () async {
      final cache = BelgianPhotoCache(capacity: 1);
      final alice = BelgianIdentity.parse(identityFile());
      cache.store(alice, Uint8List.fromList([1, 2, 3]));
      expect(cache.length, 0);

      cache.store(alice, photo);
      expect(cache.lookup(alice), photo);

      final card = SimulatedBelgianCard();
      final eid = await BelgianEidReader(card).read(photoCache: cache);
      expect(cache.length, 1);
      expect(cache.lookup(alice), isNull);
      expect(cache.lookup(eid.identity), specimenPhoto);

      cache.clear();
      expect(cache.length, 0);
    });
  });

  test('reports each exchange to onApdu, the PIN left out', () async {
    final exchanges = <ApduExchange>[];
    final reader = BelgianEidReader(
      SimulatedBelgianCard(),
      onApdu: exchanges.add,
    );
    await reader.readIdentity();
    await reader.verifyPin('1234');
    expect(hexString(exchanges.first.command), '00A4020C024031');
    expect(exchanges.last.isRedacted, isTrue);
    expect(exchanges.map((e) => '$e').join(), isNot(contains('1234')));
  });

  test('follows the read with onProgress, growing to 1', () async {
    final progress = <double>[];
    await BelgianEidReader(SimulatedBelgianCard()).read(
      onProgress: progress.add,
    );
    expect(progress.length, greaterThan(5));
    expect(progress.last, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThan(progress[i - 1]));
    }
  });
}
