import 'dart:typed_data';

import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/p384.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp384r1.dart';

/// The RSA or P-384 key a SubjectPublicKeyInfo holds.
/// Throws a [FormatException] for any other key.
PublicKey parseSubjectPublicKeyInfo(DerElement info) {
  final parts = info.children;
  if (parts.length != 2) throw const FormatException('Not a public key');
  final algorithm = parts[0].children;
  if (algorithm.isEmpty) throw const FormatException('Not a public key');
  final key = parts[1].bitString;
  switch (algorithm[0].objectIdentifier) {
    case '1.2.840.113549.1.1.1':
      final numbers = DerElement.parse(key).children;
      if (numbers.length < 2) throw const FormatException('Not an RSA key');
      final modulus = numbers[0].integer;
      if (modulus.bitLength < 1024) {
        throw const FormatException('RSA key too short');
      }
      return RSAPublicKey(modulus, numbers[1].integer);
    case '1.2.840.10045.2.1':
      if (algorithm.length < 2 ||
          algorithm[1].objectIdentifier != '1.3.132.0.34') {
        throw const FormatException('Only P-384 keys are supported');
      }
      // An uncompressed point: 04, then x and y on 48 bytes each.
      if (key.length != 97 || key[0] != 0x04) {
        throw const FormatException('Malformed P-384 key');
      }
      if (!p384OnCurve(
        unsignedBigInt(key.sublist(1, 49)),
        unsignedBigInt(key.sublist(49)),
      )) {
        throw const FormatException('Not a point of P-384');
      }
      final curve = ECCurve_secp384r1();
      return ECPublicKey(curve.curve.decodePoint(key), curve);
    default:
      throw const FormatException('Unsupported key algorithm');
  }
}

/// Reads [bytes] as a SubjectPublicKeyInfo, padding allowed.
PublicKey parsePublicKeyFile(Uint8List bytes) =>
    parseSubjectPublicKeyInfo(DerElement.parse(bytes));
