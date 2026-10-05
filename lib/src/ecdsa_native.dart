import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/p384.dart';

/// The hashes an ECDSA signature on a card is computed over.
enum EcHash {
  /// SHA-256.
  sha256,

  /// SHA-384.
  sha384,

  /// SHA-512.
  sha512,
}

/// Whether ([r], [s]) is the ECDSA signature of [data], hashed with [hash],
/// by the P-384 key in [publicKeyInfo], a DER SubjectPublicKeyInfo.
Future<bool> verifyP384({
  required Uint8List publicKeyInfo,
  required Uint8List data,
  required EcHash hash,
  required BigInt r,
  required BigInt s,
}) async {
  final parts = DerElement.parse(publicKeyInfo).children;
  if (parts.length != 2 || parts[0].children.length != 2) return false;
  if (parts[0].children[1].objectIdentifier != '1.3.132.0.34') return false;
  final point = parts[1].bitString;
  if (point.length != 97 || point[0] != 4) return false;
  final digest = switch (hash) {
    EcHash.sha256 => sha256,
    EcHash.sha384 => sha384,
    EcHash.sha512 => sha512,
  }
      .convert(data)
      .bytes;
  return p384Verify(
    unsignedBigInt(point.sublist(1, 49)),
    unsignedBigInt(point.sublist(49)),
    digest,
    r,
    s,
  );
}

/// The DER ECDSA signature of [data] with SHA-384 by [d], whose public point
/// is [point]. For the simulated cards only.
Future<Uint8List> signP384(BigInt d, Uint8List point, Uint8List data) async {
  final (r, s) = p384Sign(d, sha384.convert(data).bytes);
  return derSequence([derInteger(r), derInteger(s)]);
}
