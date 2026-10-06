import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  test('reads as a consistent card', () async {
    final eid = await BelgianEidReader(SimulatedBelgianCard())
        .read(showPrivateData: true);
    final identity = eid.identity;

    expect(identity.lastName, 'Specimen');
    expect(identity.firstNames, 'Alice Marie');
    expect(identity.birthDate, PartialDate(1990, 5, 15));
    expect(identity.sex, Sex.female);
    expect(identity.documentType, BelgianDocumentType.eid);
    expect(identity.validUntil, DateTime.utc(2034, 3, 13));
    expect(identity.chipNumber, SimulatedBelgianCard.serialNumber);
    expect(isValidBelgianNationalNumber(identity.nationalNumber!), isTrue);
    expect(eid.address.toString(), 'Rue de la Loi 16, 1000 Bruxelles');
    expect(eid.photo, specimenPhoto);
    expect(eid.photoMatches, isTrue);
  });

  test('carries what it is given', () async {
    final card = SimulatedBelgianCard(
      lastName: 'Peeters',
      birthDate: '03 MAAR 1975',
      sex: 'M',
      documentType: BelgianDocumentType.euCard,
      municipality: 'Gent',
      extraIdentityFields: {0x1F: '02.05.2019'},
    );
    final eid = await BelgianEidReader(card).read(
      parts: {BelgianEidPart.address},
    );

    expect(eid.identity.lastName, 'Peeters');
    expect(eid.identity.birthDate, PartialDate(1975, 3, 3));
    expect(eid.identity.sex, Sex.male);
    expect(eid.identity.documentType, BelgianDocumentType.euCard);
    expect(eid.identity.registrationDate, DateTime.utc(2019, 5, 2));
    expect(eid.address?.municipality, 'Gent');
  });

  test('hashes the photo with SHA-1 on an older applet', () async {
    final card = SimulatedBelgianCard(appletVersion: 0x17);
    final reader = BelgianEidReader(card);
    final eid = await reader.read();

    expect(eid.identity.photoHash, hasLength(20));
    expect(eid.identity.basicKeyHash, isNull);
    expect(eid.photoMatches, isTrue);
    expect((await reader.readCardInfo()).isApplet18OrLater, isFalse);
  });

  test('counts PIN tries, and resets them on the right PIN', () async {
    final card = SimulatedBelgianCard(pin: '4321');
    final reader = BelgianEidReader(card);

    await expectLater(
      reader.verifyPin('1111'),
      throwsA(isA<PinException>().having((e) => e.triesLeft, 'triesLeft', 2)),
    );
    expect(card.isPinVerified, isFalse);

    await reader.verifyPin('4321');
    expect(card.isPinVerified, isTrue);
    expect(card.pinTriesLeft, 3);
  });

  test('blocks after three wrong PINs, even the right one after', () async {
    final card = SimulatedBelgianCard();
    final reader = BelgianEidReader(card);
    for (var i = 0; i < 3; i++) {
      await expectLater(reader.verifyPin('0000'), throwsA(isA<PinException>()));
    }
    await expectLater(
      reader.verifyPin('1234'),
      throwsA(
          isA<PinException>().having((e) => e.isBlocked, 'isBlocked', true)),
    );
  });

  test('a card pulled out fails like a reader does, and resets on return',
      () async {
    final card = SimulatedBelgianCard();
    final reader = BelgianEidReader(card);
    await reader.verifyPin('1234');

    card.remove();
    await expectLater(
      reader.readIdentity(),
      throwsA(isA<CardTransportException>()),
    );

    card.insert();
    expect(card.isPinVerified, isFalse);
    expect((await reader.readIdentity()).lastName, 'Specimen');
  });

  test('holds the certificates of a card, unless told otherwise', () async {
    final files =
        BelgianEidFile.values.where((file) => file.isCertificate).toList();
    final full = BelgianEidReader(SimulatedBelgianCard());
    for (final file in files) {
      expect(await full.readCertificate(file), isNotNull, reason: file.name);
    }

    final kid = BelgianEidReader(
      SimulatedBelgianCard(holderCertificates: false),
    );
    expect(
      await kid.readCertificate(BelgianEidFile.authenticationCertificate),
      isNull,
    );
    expect(
      await kid.readCertificate(BelgianEidFile.rootCertificate),
      SimulatedBelgianCard.rootCertificate,
    );
  });

  test('answers a file it does not have as a real card does', () async {
    final channel = CardChannel(SimulatedBelgianCard());
    await channel.selectPath([0x3F00, 0xDF01]);
    await expectLater(
      channel.selectFile(0x4099),
      throwsA(
          isA<CardException>().having((e) => e.isNotFound, 'isNotFound', true)),
    );
  });
}
