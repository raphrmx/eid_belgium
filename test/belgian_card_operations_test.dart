import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  Future<BelgianCardAuthenticity> prove(SimulatedBelgianCard card) async {
    final reader = BelgianEidReader(card);
    return await reader.proveGenuine(
      await reader.readIdentity(withNationalNumber: false),
    );
  }

  group('proveGenuine', () {
    test('finds a genuine chip genuine', () async {
      expect(
        await prove(SimulatedBelgianCard()),
        BelgianCardAuthenticity.genuine,
      );
    });

    test('finds out a chip holding copied files', () async {
      expect(
        await prove(SimulatedBelgianCard(cloned: true)),
        BelgianCardAuthenticity.notGenuine,
      );
    });

    test('says an older card cannot tell', () async {
      expect(
        await prove(SimulatedBelgianCard(appletVersion: 0x17)),
        BelgianCardAuthenticity.notSupported,
      );
    });

    test('sends the challenge the Belpic applet expects', () async {
      final exchanges = <ApduExchange>[];
      final reader =
          BelgianEidReader(SimulatedBelgianCard(), onApdu: exchanges.add);
      await reader.proveGenuine(await reader.readIdentity());
      final challenge = exchanges.last;
      expect(hexString(challenge.command.sublist(0, 7)), '0088028132' '9430');
      expect(challenge.command, hasLength(55));
      expect(challenge.responseDataLength, 96);
    });

    test('turns a copy down when read asks for it', () async {
      final reader = BelgianEidReader(SimulatedBelgianCard(cloned: true));
      await expectLater(
        reader.read(),
        throwsA(
          isA<BelgianCardRejectedException>().having(
            (e) => e.reason,
            'reason',
            BelgianCardRejection.notGenuine,
          ),
        ),
      );
      final genuine = await BelgianEidReader(SimulatedBelgianCard()).read();
      expect(genuine.authenticity, BelgianCardAuthenticity.genuine);
      // Only the chip can prove itself: JSON does not carry it over.
      expect(BelgianEid.fromJson(genuine.toJson()).authenticity, isNull);
    });
  });

  group('pinTriesLeft', () {
    test('reads the counter without spending a try', () async {
      final card = SimulatedBelgianCard();
      final reader = BelgianEidReader(card);
      expect(await reader.pinTriesLeft(), 3);
      expect(await reader.pinTriesLeft(), 3);

      await expectLater(reader.verifyPin('0000'), throwsA(isA<PinException>()));
      expect(await reader.pinTriesLeft(), 2);

      await reader.verifyPin('1234');
      expect(await reader.pinTriesLeft(), 3);
    });

    test('says 0 once the PIN is blocked', () async {
      final reader = BelgianEidReader(SimulatedBelgianCard());
      for (var i = 0; i < 3; i++) {
        await expectLater(
          reader.verifyPin('0000'),
          throwsA(isA<PinException>()),
        );
      }
      expect(await reader.pinTriesLeft(), 0);
    });
  });

  group('changePin', () {
    test('replaces the PIN', () async {
      final reader = BelgianEidReader(SimulatedBelgianCard());
      await reader.changePin('1234', '987654');
      await reader.verifyPin('987654');
      await expectLater(
        reader.verifyPin('1234'),
        throwsA(isA<PinException>()),
      );
    });

    test('spends a try on a wrong current PIN', () async {
      final reader = BelgianEidReader(SimulatedBelgianCard());
      await expectLater(
        reader.changePin('0000', '5678'),
        throwsA(isA<PinException>().having((e) => e.triesLeft, 'tries', 2)),
      );
      await reader.verifyPin('1234');
    });

    test('refuses a malformed PIN before it reaches the card', () {
      final card = SimulatedBelgianCard();
      final reader = BelgianEidReader(card);
      expect(() => reader.changePin('1234', '12'), throwsArgumentError);
      expect(() => reader.changePin('12ab', '5678'), throwsArgumentError);
      expect(card.pinTriesLeft, 3);
    });

    test('keeps the PINs out of onApdu', () async {
      final exchanges = <ApduExchange>[];
      await BelgianEidReader(SimulatedBelgianCard(), onApdu: exchanges.add)
          .changePin('1234', '5678');
      expect(exchanges.single.isRedacted, isTrue);
      expect('${exchanges.single}', isNot(contains('1234')));
      expect('${exchanges.single}', isNot(contains('5678')));
    });
  });

  test('names each document type in four languages', () {
    for (final type in BelgianDocumentType.values) {
      for (final language in BelgianLanguage.values) {
        expect(type.label(language), isNotEmpty);
      }
    }
    expect(
      BelgianDocumentType.eid.label(BelgianLanguage.fr),
      "Carte d'identité",
    );
    expect(BelgianDocumentType.ePlusCard.label(BelgianLanguage.nl), 'E+-kaart');
    expect(
      BelgianDocumentType.kidsEuPlusCard.label(BelgianLanguage.en),
      'EU+ card (child under 12)',
    );
    expect(
      BelgianDocumentType.fPlusCardUniformFormat.label(BelgianLanguage.de),
      'F+-Karte (einheitliches Format)',
    );
  });
}
