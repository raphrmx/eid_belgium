import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  final trusted = BelgianSignatureVerifier(
    trustedRoots: [SimulatedBelgianCard.rootCertificate],
  );

  test('reads whom each certificate names, and when it is valid', () async {
    final certificates =
        await BelgianEidReader(SimulatedBelgianCard()).readCertificates();

    final authentication = certificates.authentication!;
    expect(
      authentication.subject.commonName,
      'Alice Marie Specimen (Authentication)',
    );
    expect(authentication.subject.surname, 'Specimen');
    expect(authentication.subject.givenName, 'Alice Marie');
    expect(authentication.subject.serialNumber, '90051512391');
    expect(authentication.subject.country, 'BE');
    expect(authentication.issuer.commonName, 'Simulated Citizen CA');
    expect(authentication.notBefore, DateTime.utc(2020));
    expect(authentication.notAfter, DateTime.utc(2049, 12, 31, 23, 59, 59));
    expect(authentication.keyAlgorithm, 'EC P-384');
    expect(authentication.isSelfIssued, isFalse);

    expect(certificates.signing!.subject.commonName, endsWith('(Signature)'));
    expect(certificates.ca!.subject.commonName, 'Simulated Citizen CA');
    expect(certificates.root!.isSelfIssued, isTrue);
    expect(certificates.nationalRegister!.subject.commonName, 'Simulated RRN');
  });

  test('chains every certificate up to a trusted root', () async {
    final certificates =
        await BelgianEidReader(SimulatedBelgianCard()).readCertificates();
    expect(await certificates.verify(trusted), isEmpty);

    final failures = await certificates.verify(BelgianSignatureVerifier());
    expect(failures.keys, hasLength(4));
    expect(
      failures[certificates.authentication]!.message,
      contains('does not come from a trusted root'),
    );
  });

  test('needs the CA to chain the holder up', () async {
    final certificates =
        await BelgianEidReader(SimulatedBelgianCard()).readCertificates();
    await expectLater(
      trusted.verifyCertificateChain(certificates.authentication!.der),
      throwsA(isA<BelgianSignatureException>()),
    );
    await trusted.verifyCertificateChain(
      certificates.authentication!.der,
      intermediates: [certificates.ca!.der],
    );
  });

  test('says when a card holds no certificate of its holder', () async {
    final certificates = await BelgianEidReader(
      SimulatedBelgianCard(holderCertificates: false),
    ).readCertificates();
    expect(certificates.authentication, isNull);
    expect(certificates.signing, isNull);
    expect(certificates.ca, isNull);
    expect(await certificates.verify(trusted), isEmpty);
  });

  test('reads the Belgian roots', () {
    final roots = [
      for (final der in belgianRootCertificates) BelgianCertificate.parse(der),
    ];
    expect(roots.map((root) => root.subject.commonName), [
      'Belgium Root CA',
      'Belgium Root CA2',
      'Belgium Root CA3',
      'Belgium Root CA4',
      'Belgium Root CA6',
    ]);
    expect(roots.every((root) => root.isSelfIssued), isTrue);
    expect(roots[3].notAfter.year, 2032);
    expect(roots[4].keyAlgorithm, 'EC P-384');
    expect(roots[2].keyAlgorithm, 'RSA 4096');
    expect(roots.first.isExpiredOn(DateTime.utc(2026)), isTrue);
  });
}
