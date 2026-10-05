import 'package:eid_belgium/src/belgian_identity.dart';
import 'package:eid_belgium/src/belgian_signature_verifier.dart';

/// Why a read turned a card down.
enum BelgianCardRejection {
  /// The card is expired.
  expired,

  /// The document type is not accepted.
  documentType,

  /// The national register's signatures do not hold.
  signature,

  /// The chip could not prove it is genuine.
  notGenuine,
}

/// A read turned the card down.
final class BelgianCardRejectedException implements Exception {
  /// The card [identity] was read from, turned down for [reason].
  const BelgianCardRejectedException(this.reason, this.identity, {this.cause});

  /// Why the card was turned down.
  final BelgianCardRejection reason;

  /// The identity file of the card turned down.
  final BelgianIdentity identity;

  /// What failed, when the [reason] is the signatures.
  final BelgianSignatureException? cause;

  @override
  String toString() => switch (reason) {
        BelgianCardRejection.expired =>
          'BelgianCardRejectedException: the card expired on '
              '${identity.validUntil.toIso8601String().substring(0, 10)}',
        BelgianCardRejection.documentType =>
          'BelgianCardRejectedException: document type '
              '${identity.documentType?.name ?? identity.documentTypeCode} '
              'is not accepted',
        BelgianCardRejection.notGenuine =>
          'BelgianCardRejectedException: the chip could not prove it is '
              'genuine',
        BelgianCardRejection.signature =>
          'BelgianCardRejectedException: ${cause?.message ?? 'bad signature'}',
      };
}
