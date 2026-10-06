import 'dart:typed_data';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/public_key.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  test('keeps the verified certificates of other roots apart', () async {
    final register = await BelgianEidReader(SimulatedBelgianCard())
        .readCertificate(BelgianEidFile.nationalRegisterCertificate);
    final belgian = belgianRootCertificates.first;
    final simulated = SimulatedBelgianCard.rootCertificate;

    await BelgianSignatureVerifier(trustedRoots: [belgian, simulated])
        .verifyCertificate(register!);
    // The same bytes end to end: only the first root is read from them.
    final joined = Uint8List.fromList([...belgian, ...simulated]);
    await expectLater(
      BelgianSignatureVerifier(trustedRoots: [joined])
          .verifyCertificate(register),
      throwsA(isA<BelgianSignatureException>()),
    );
  });

  group('refuses as malformed', () {
    test('a P-384 key off the curve', () async {
      final key = Uint8List.fromList(
        await BelgianEidReader(SimulatedBelgianCard())
            .readFile(BelgianEidFile.basicPublicKey),
      )..fillRange(24, 72, 0xFF);
      expect(() => parsePublicKeyFile(key), throwsFormatException);
    });

    test('an RSA key too short to mean anything', () {
      final key = derSequence([
        derSequence([
          derObjectIdentifier('1.2.840.113549.1.1.1'),
          derEncode(0x05, []),
        ]),
        derBitString(
          derSequence(
              [derInteger(BigInt.from(255)), derInteger(BigInt.from(3))]),
        ),
      ]);
      expect(() => parsePublicKeyFile(key), throwsFormatException);
    });
  });

  test('keeps the signatures out of onApdu without the national number',
      () async {
    final whole = await BelgianEidReader(SimulatedBelgianCard())
        .read(showPrivateData: true);
    final signature = hexString(whole.identitySignature!.sublist(4, 40));

    final exchanges = <ApduExchange>[];
    await BelgianEidReader(SimulatedBelgianCard(), onApdu: exchanges.add)
        .read(parts: {BelgianEidPart.address});
    expect(exchanges.map((e) => '$e').join(), isNot(contains(signature)));
  });

  test('ends a simulated connection when the card is pulled out', () async {
    final card = SimulatedBelgianCard();
    final connection = await card.connect();
    card
      ..remove()
      ..insert();
    await expectLater(
      connection.transmit(Uint8List.fromList([0x00, 0xCA, 0x00, 0x00, 0x01])),
      throwsA(isA<CardTransportException>()),
    );
    final again = await card.connect();
    await again.disconnect();
    await expectLater(
      again.transmit(Uint8List.fromList([0x00, 0xCA, 0x00, 0x00, 0x01])),
      throwsA(isA<CardTransportException>()),
    );
  });
}
