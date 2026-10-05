import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_root_certificates.dart';
import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/ecdsa.dart';
import 'package:eid_belgium/src/public_key.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

part 'belgian_certificate.dart';

/// Card data whose national register signature could not be verified.
final class BelgianSignatureException implements Exception {
  /// A failure described by [message].
  const BelgianSignatureException(this.message);

  /// What failed, such as `The identity file does not match its signature`.
  final String message;

  @override
  String toString() => 'BelgianSignatureException: $message';
}

/// Checks that the national register signed a card's identity and address
/// files, and that its certificate comes from a trusted root.
///
/// Takes files and signatures as the card holds them, so it can run on a
/// server. On the web, signatures are checked by the browser's WebCrypto.
final class BelgianSignatureVerifier {
  /// A verifier trusting [trustedRoots], DER encoded, or the Belgian roots.
  /// A national register certificate among them is trusted as is.
  factory BelgianSignatureVerifier({List<Uint8List>? trustedRoots}) {
    if (trustedRoots == null) {
      return BelgianSignatureVerifier._(_belgianRoots, '');
    }
    final roots = [
      for (final root in trustedRoots) BelgianCertificate.parse(root),
    ];
    // Each root as parsed, its length in front, so that no other list of
    // roots shares the key.
    final key = crypto.sha256.convert([
      for (final root in roots) ...[
        ...bigIntBytes(BigInt.from(root.der.length), 4),
        ...root.der,
      ],
    ]).toString();
    return BelgianSignatureVerifier._(roots, key);
  }

  BelgianSignatureVerifier._(this._roots, this._rootsKey);

  static final _belgianRoots = [
    for (final root in belgianRootCertificates) BelgianCertificate.parse(root),
  ];

  final List<BelgianCertificate> _roots;

  // Tells apart the verified certificates of verifiers with other roots.
  final String _rootsKey;

  /// Checks the national register's DER [certificate] against the roots.
  ///
  /// Throws a [BelgianSignatureException] unless a trusted root issued it.
  Future<void> verifyCertificate(Uint8List certificate) => _issued(certificate);

  /// Checks that a trusted root issued [certificate], directly or through
  /// [intermediates], such as the card's CA certificate. Each issuer but the
  /// root must be a CA.
  ///
  /// Dates are not checked. Throws a [BelgianSignatureException] when no
  /// chain holds.
  Future<void> verifyCertificateChain(
    Uint8List certificate, {
    List<Uint8List> intermediates = const [],
  }) async {
    final issuers = [
      for (final intermediate in intermediates) _parse(intermediate),
    ];
    await _chain(_parse(certificate), issuers, 0);
  }

  /// Checks the national register's signature of the identity file.
  ///
  /// Throws a [BelgianSignatureException] when the signature or
  /// [certificate] does not hold.
  Future<void> verifyIdentity({
    required Uint8List identityFile,
    required Uint8List identitySignature,
    required Uint8List certificate,
  }) async {
    final register = await _issued(certificate);
    if (!await _verify(register, identityFile, identitySignature)) {
      throw const BelgianSignatureException(
        'The identity file does not match its signature',
      );
    }
  }

  /// Checks the national register's signature of the address file.
  ///
  /// Throws a [BelgianSignatureException] as [verifyIdentity] does.
  Future<void> verifyAddress({
    required Uint8List addressFile,
    required Uint8List addressSignature,
    required Uint8List identitySignature,
    required Uint8List certificate,
  }) async {
    final register = await _issued(certificate);
    var end = addressFile.length;
    while (end > 0 && addressFile[end - 1] == 0) {
      end--;
    }
    final signed = Uint8List(end + identitySignature.length)
      ..setRange(0, end, addressFile)
      ..setRange(end, end + identitySignature.length, identitySignature);
    if (!await _verify(register, signed, addressSignature)) {
      throw const BelgianSignatureException(
        'The address file does not match its signature',
      );
    }
  }

  // The register's certificate is the same on many cards: once verified, it
  // is not verified again by a verifier with the same roots.
  static final _verified = <String, BelgianCertificate>{};

  Future<BelgianCertificate> _issued(Uint8List certificate) async {
    final key = '$_rootsKey:${base64Encode(certificate)}';
    final known = _verified[key];
    if (known != null) return known;
    final checked = await _chain(_parse(certificate), const [], 0);
    if (_verified.length >= 64) _verified.clear();
    return _verified[key] = checked;
  }

  static BelgianCertificate _parse(Uint8List certificate) {
    try {
      return BelgianCertificate.parse(certificate);
    } on FormatException catch (error) {
      throw BelgianSignatureException(
        'A certificate is malformed: ${error.message}',
      );
    }
  }

  // Three links at most.
  Future<BelgianCertificate> _chain(
    BelgianCertificate certificate,
    List<BelgianCertificate> intermediates,
    int depth,
  ) async {
    for (final root in _roots) {
      if (sameBytes(root.der, certificate.der) ||
          await _issuedBy(certificate, root)) {
        return certificate;
      }
    }
    if (depth < 3) {
      for (final issuer in intermediates) {
        if (!issuer.isCa || !await _issuedBy(certificate, issuer)) continue;
        await _chain(issuer, intermediates, depth + 1);
        return certificate;
      }
    }
    throw BelgianSignatureException(
      'The certificate of ${certificate.subject.commonName ?? 'the card'} '
      'does not come from a trusted root',
    );
  }

  static Future<bool> _issuedBy(
    BelgianCertificate certificate,
    BelgianCertificate issuer,
  ) async {
    if (!sameBytes(issuer._subjectName, certificate._issuerName)) return false;
    final algorithm = certificate._signatureAlgorithm;
    final digest = _certificateDigests[algorithm];
    final ecdsa = algorithm.startsWith('1.2.840.10045.');
    if (digest == null || ecdsa != (issuer._publicKey is ECPublicKey)) {
      return false;
    }
    return await _verify(
      issuer,
      certificate._signed,
      certificate._signature,
      digest: digest,
    );
  }

  // Without [digest], each RSA hash is tried; EC signatures use SHA-384.
  static Future<bool> _verify(
    BelgianCertificate signer,
    Uint8List data,
    Uint8List signature, {
    _Digest? digest,
  }) async {
    try {
      final key = signer._publicKey;
      if (key is ECPublicKey) {
        final value = DerElement.parse(signature);
        final values = value.children;
        if (value.tag != 0x30 || values.length != 2) return false;
        return await verifyP384(
          publicKeyInfo: signer._keyInfo,
          data: data,
          hash: switch (digest) {
            _Digest.sha256 => EcHash.sha256,
            _Digest.sha512 => EcHash.sha512,
            _ => EcHash.sha384,
          },
          r: values[0].integer,
          s: values[1].integer,
        );
      }
      if (key is RSAPublicKey) {
        final length = (key.modulus!.bitLength + 7) ~/ 8;
        if (signature.length < length) return false;
        final bytes = Uint8List.sublistView(signature, 0, length);
        for (final candidate in digest == null ? _Digest.values : [digest]) {
          final rsa = RSASigner(candidate.create(), candidate.identifier)
            ..init(false, PublicKeyParameter<RSAPublicKey>(key));
          if (rsa.verifySignature(data, RSASignature(bytes))) return true;
        }
      }
      return false;
    } on FormatException {
      return false;
    }
  }

  static const _certificateDigests = {
    '1.2.840.113549.1.1.5': _Digest.sha1,
    '1.2.840.113549.1.1.11': _Digest.sha256,
    '1.2.840.113549.1.1.12': _Digest.sha384,
    '1.2.840.113549.1.1.13': _Digest.sha512,
    '1.2.840.10045.4.3.2': _Digest.sha256,
    '1.2.840.10045.4.3.3': _Digest.sha384,
    '1.2.840.10045.4.3.4': _Digest.sha512,
  };
}

/// The hashes used, with their PKCS#1 v1.5 DER identifier.
enum _Digest {
  sha256('0609608648016503040201'),
  sha384('0609608648016503040202'),
  sha1('06052b0e03021a'),
  sha512('0609608648016503040203');

  const _Digest(this.identifier);

  final String identifier;

  Digest create() => switch (this) {
        sha1 => SHA1Digest(),
        sha256 => SHA256Digest(),
        sha384 => SHA384Digest(),
        sha512 => SHA512Digest(),
      };
}
