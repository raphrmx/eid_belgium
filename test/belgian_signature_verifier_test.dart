import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  final trusted = [SimulatedBelgianCard.rootCertificate];

  group('read(verifySignatures: true)', () {
    test('checks every signature of a genuine card', () async {
      final eid = await BelgianEidReader(SimulatedBelgianCard()).read(
        trustedRoots: trusted,
      );
      expect(eid.signaturesVerified, isTrue);
      expect(eid.nationalRegisterCertificate, isNotNull);
      expect(eid.photoMatches, isTrue);
    });

    test('checks them without the national number in hand', () async {
      final eid = await BelgianEidReader(SimulatedBelgianCard()).read(
        parts: {BelgianEidPart.address},
        trustedRoots: trusted,
      );
      expect(eid.signaturesVerified, isTrue);
      expect(eid.identity.nationalNumber, isNull);
      expect(eid.identity.file, isNull);
    });

    test('turns down a card whose identity was rewritten', () async {
      final card = SimulatedBelgianCard(tamperedLastName: 'Mallory');
      await expectLater(
        BelgianEidReader(card).read(
          trustedRoots: trusted,
        ),
        throwsA(
          isA<BelgianCardRejectedException>()
              .having((e) => e.reason, 'reason', BelgianCardRejection.signature)
              .having((e) => e.identity.lastName, 'name', 'Mallory')
              .having(
                (e) => e.cause?.message,
                'cause',
                'The identity file does not match its signature',
              ),
        ),
      );
    });

    test('turns down a card whose register the Belgian roots do not know',
        () async {
      await expectLater(
        BelgianEidReader(SimulatedBelgianCard()).read(
          trustedRoots: belgianRootCertificates,
        ),
        throwsA(
          isA<BelgianCardRejectedException>().having(
            (e) => e.cause?.message,
            'cause',
            contains('does not come from a trusted root'),
          ),
        ),
      );
    });

    test('is skipped when turned off', () async {
      final eid = await BelgianEidReader(
        SimulatedBelgianCard(tamperedLastName: 'Mallory'),
      ).read(verifySignatures: false);
      expect(eid.signaturesVerified, isFalse);
      expect(eid.identity.lastName, 'Mallory');
    });

    test('is on by default, the simulated root trusted for the simulator',
        () async {
      final eid = await BelgianEidReader(SimulatedBelgianCard()).read();
      expect(eid.signaturesVerified, isTrue);
      expect(eid.authenticity, BelgianCardAuthenticity.genuine);
    });

    test('never trusts the simulated root for another transport', () async {
      // The same bytes, through a transport that is not the simulator, as a
      // card copying the simulator would be.
      final copy = _Relay(SimulatedBelgianCard());
      await expectLater(
        BelgianEidReader(copy).read(),
        throwsA(
          isA<BelgianCardRejectedException>().having(
            (e) => e.reason,
            'reason',
            BelgianCardRejection.signature,
          ),
        ),
      );
    });
  });

  group('BelgianSignatureVerifier', () {
    late BelgianEid eid;
    late Uint8List certificate;
    final verifier = BelgianSignatureVerifier(trustedRoots: trusted);

    setUpAll(() async {
      eid = await BelgianEidReader(SimulatedBelgianCard()).read(
        trustedRoots: trusted,
        showPrivateData: true,
      );
      certificate = eid.nationalRegisterCertificate!;
    });

    test('checks the files again away from the card', () async {
      await verifier.verifyCertificate(certificate);
      await verifier.verifyIdentity(
        identityFile: eid.identity.file!,
        identitySignature: eid.identitySignature!,
        certificate: certificate,
      );
      await verifier.verifyAddress(
        addressFile: eid.address!.file,
        addressSignature: eid.addressSignature!,
        identitySignature: eid.identitySignature!,
        certificate: certificate,
      );
    });

    test('refuses an address moved to another card', () {
      final other = SimulatedBelgianCard(streetAndNumber: 'Rue Neuve 1');
      expect(
        () async {
          final moved = await BelgianEidReader(other).read();
          await verifier.verifyAddress(
            addressFile: moved.address!.file,
            addressSignature: eid.addressSignature!,
            identitySignature: eid.identitySignature!,
            certificate: certificate,
          );
        }(),
        throwsA(isA<BelgianSignatureException>()),
      );
    });

    test('refuses a certificate it cannot read', () async {
      await expectLater(
        verifier.verifyCertificate(Uint8List.fromList([0x30, 0x03, 1])),
        throwsA(isA<BelgianSignatureException>()),
      );
    });

    test('loads the Belgian roots', () async {
      expect(belgianRootCertificates, hasLength(5));
      await expectLater(
        BelgianSignatureVerifier().verifyCertificate(certificate),
        throwsA(isA<BelgianSignatureException>()),
      );
    });
  });
}

final class _Relay implements CardTransport {
  _Relay(this.card);

  final SimulatedBelgianCard card;

  @override
  Future<Uint8List> transmit(Uint8List command) => card.transmit(command);
}
