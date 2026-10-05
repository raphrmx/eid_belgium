import 'package:eid_belgium/src/belgian_signature_verifier.dart';

/// The certificates a card holds, each null when absent, as on a Kids ID.
final class BelgianCertificates {
  /// The certificates of one card.
  const BelgianCertificates({
    this.authentication,
    this.signing,
    this.ca,
    this.root,
    this.nationalRegister,
  });

  /// The holder's authentication certificate, used to log in.
  final BelgianCertificate? authentication;

  /// The holder's qualified signature certificate.
  final BelgianCertificate? signing;

  /// The CA that issued [authentication] and [signing].
  final BelgianCertificate? ca;

  /// The root as the card holds it. Not trusted: a
  /// [BelgianSignatureVerifier] uses its own roots.
  final BelgianCertificate? root;

  /// The national register's certificate.
  final BelgianCertificate? nationalRegister;

  /// Checks that a trusted root issued each certificate, and returns the
  /// failure for each one that does not hold.
  Future<Map<BelgianCertificate, BelgianSignatureException>> verify(
    BelgianSignatureVerifier verifier,
  ) async {
    final intermediates = [if (ca case final ca?) ca.der];
    final failures = <BelgianCertificate, BelgianSignatureException>{};
    for (final certificate in [authentication, signing, ca, nationalRegister]) {
      if (certificate == null) continue;
      try {
        await verifier.verifyCertificateChain(
          certificate.der,
          intermediates: intermediates,
        );
      } on BelgianSignatureException catch (failure) {
        failures[certificate] = failure;
      }
    }
    return failures;
  }
}
