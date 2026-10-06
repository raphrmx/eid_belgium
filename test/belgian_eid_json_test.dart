import 'dart:convert';

import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  final trusted = [SimulatedBelgianCard.rootCertificate];

  Future<BelgianEid> read({
    Set<BelgianEidPart> parts = BelgianEidPart.all,
    bool showPrivateData = true,
  }) =>
      BelgianEidReader(SimulatedBelgianCard()).read(
        parts: parts,
        trustedRoots: trusted,
        showPrivateData: showPrivateData,
      );

  BelgianEid roundTrip(BelgianEid eid) => BelgianEid.fromJson(
        jsonDecode(jsonEncode(eid.toJson())) as Map<String, Object?>,
      );

  test('comes back whole from JSON', () async {
    final eid = await read();
    final json = eid.toJson();
    final identity = json['identity']! as Map<String, Object?>;
    expect(identity['lastName'], 'Specimen');
    expect(identity['birthDate'], '1990-05-15');
    expect(identity['validUntil'], '2034-03-13');
    expect(identity['sex'], 'female');

    final back = roundTrip(eid);
    expect(back.identity.lastName, 'Specimen');
    expect(back.identity.nationalNumber, eid.identity.nationalNumber);
    expect(back.address?.municipality, 'Bruxelles');
    expect(back.photo, eid.photo);
    expect(back.photoMatches, isTrue);
  });

  test('lets a server check the signatures again', () async {
    final back = roundTrip(await read());
    // Whatever the JSON claims, the server checks for itself.
    expect(back.signaturesVerified, isFalse);

    final certificate = back.nationalRegisterCertificate!;
    final verifier = BelgianSignatureVerifier(trustedRoots: trusted);
    await verifier.verifyIdentity(
      identityFile: back.identity.file!,
      identitySignature: back.identitySignature!,
      certificate: certificate,
    );
    await verifier.verifyAddress(
      addressFile: back.address!.file,
      addressSignature: back.addressSignature!,
      identitySignature: back.identitySignature!,
      certificate: certificate,
    );
  });

  test('keeps the national number out when the read did', () async {
    final eid = await read(
      parts: {BelgianEidPart.address},
      showPrivateData: false,
    );
    final text = jsonEncode(eid.toJson());
    expect(text, isNot(contains('90051512391')));
    expect(
      text,
      isNot(contains(base64Encode(utf8.encode('90051512391')))),
    );

    final back = roundTrip(eid);
    expect(back.identity.nationalNumber, isNull);
    expect(back.identity.lastName, 'Specimen');
    expect(back.photo, isNull);
  });

  test('refuses JSON it did not write', () {
    expect(
      () => BelgianEid.fromJson(const {'identity': 'nope'}),
      throwsFormatException,
    );
    expect(() => BelgianEid.fromJson(const {}), throwsFormatException);
  });
}
