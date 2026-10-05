import 'dart:math';
import 'dart:typed_data';

import 'package:eid_belgium/src/p384.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp384r1.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:test/test.dart';

void main() {
  final curve = ECCurve_secp384r1();
  final random = Random(384);
  final secure = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i))));

  Uint8List bytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));

  BigInt scalar() =>
      bytes(48).fold(BigInt.zero, (v, b) => v << 8 | BigInt.from(b)) % curve.n +
      BigInt.one;

  test('agrees with pointycastle on its signatures and their forgeries', () {
    for (var i = 0; i < 20; i++) {
      final d = scalar();
      final q = (curve.G * d)!;
      final x = q.x!.toBigInteger()!;
      final y = q.y!.toBigInteger()!;
      final digest = bytes(48);
      final signer = ECDSASigner()
        ..init(
          true,
          ParametersWithRandom(
            PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(d, curve)),
            secure,
          ),
        );
      final signature = signer.generateSignature(digest) as ECSignature;

      expect(p384Verify(x, y, digest, signature.r, signature.s), isTrue);
      final altered = Uint8List.fromList(digest)..[i] ^= 1;
      expect(p384Verify(x, y, altered, signature.r, signature.s), isFalse);
      expect(
        p384Verify(x, y, digest, signature.r, signature.s + BigInt.one),
        isFalse,
      );
      expect(p384Verify(y, x, digest, signature.r, signature.s), isFalse);
    }
  });

  test('signs what pointycastle verifies', () {
    for (var i = 0; i < 10; i++) {
      final d = scalar();
      final digest = bytes(48);
      final (r, s) = p384Sign(d, digest);
      final verifier = ECDSASigner()
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(ECPublicKey(curve.G * d, curve)),
        );
      expect(verifier.verifySignature(digest, ECSignature(r, s)), isTrue);
      final point = p384PublicPoint(d);
      expect(point, (curve.G * d)!.getEncoded(false));
    }
  });

  test('refuses values out of range', () {
    final d = scalar();
    final point = p384PublicPoint(d);
    BigInt coordinate(int from) => point
        .sublist(from, from + 48)
        .fold(BigInt.zero, (v, b) => v << 8 | BigInt.from(b));
    final (x, y) = (coordinate(1), coordinate(49));
    final digest = bytes(48);
    final (r, s) = p384Sign(d, digest);
    expect(p384Verify(x, y, digest, r, s), isTrue);
    expect(p384Verify(x, y, digest, BigInt.zero, s), isFalse);
    expect(p384Verify(x, y, digest, r, curve.n), isFalse);
    expect(p384Verify(x, y + BigInt.one, digest, r, s), isFalse);
  });
}
