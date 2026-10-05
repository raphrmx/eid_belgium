import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid/eid.dart';
import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/ecdsa.dart';
import 'package:eid_belgium/src/p384.dart';

/// A made-up national register for the simulated cards, on P-384.
///
/// Its private keys are public test keys and protect nothing. The fixed
/// certificates and public points below are derived from them.
final class SimulatedPki {
  SimulatedPki._();

  /// The register shared by every simulated card.
  static final instance = SimulatedPki._();

  static BigInt _key(String hex) => BigInt.parse(hex, radix: 16);

  static Uint8List _bytes(String hex) => Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);

  static final _registerKey = _key(
    '219ab4676d981b37604e7f94384969754343f6a546bf5928069bb9a3118b35ff'
    'a7b840b1e39bb3beabaa5f3b60c63f89',
  );

  static final _caKey = _key(
    'ea3b3da8c6885e1b279faf8859d7eebdc81c4ca0d506cac471e4eb9eb0ccdb75'
    'f7d215e3cf5c2e6944dacc84a29130ec',
  );

  /// The basic key of every simulated card, from applet 1.8 on.
  final basicKey = _key(
    '23afa104358e3890b3d0b3aadea8161611924473c01ef4adca95c32230b92d91'
    '7bad4f3775fe193b7fda76b64fb3fff7',
  );

  /// The key a cloned card signs with instead of [basicKey].
  final cloneKey = _key(
    '01ea2d2aa8633accb2f7ebbc42d2010de4df0ce96ed814aab7843321b2c27571'
    '891fbd46f22ca5c2fd55851cf4770818',
  );

  static final _registerPoint = _bytes(
    '04fa4fa7104550a7fbd959e65c997507e89943f3b9ace5124fc371f266b58db6'
    '035cf0ca94a15b3a19877b4eb458c6b896603a07a5f514e52349d527399f9104'
    '6102a124dbd2cd94870858fbc164f7483d6c056e1f19afe720fc7e8bca78c0bc'
    '0f',
  );

  static final _basicPoint = _bytes(
    '04b5b7d8d6cf13428e5cfd70623aca30094305341cd2dc1304c0cfe82398b420'
    'd46df107b0dafdf5bb5b965b5f09c57c58b1f0a898fab54ac8654efd083e6e89'
    'ef127bcfed77b6faefcd32d65a83f4f3c101c23998cd52a94561f9262677ffda'
    '13',
  );

  static final _caPoint = _bytes(
    '048076877a1d75583121249a574168384f77d6d00b56f8f334d31fa1aef9f1f5'
    'b5fc769828199576f00659c350def5b7c157fe04ac2ef613a9092c5ff75aa73b'
    'ef596b9dd30ab65b295031ce9e91c58ee036de5db0c2b82fed4c5477fbf7358a'
    'b1',
  );

  static final _authenticationPoint = _bytes(
    '04b346cb365bc2373a1945af13e839d3947bd0dc3bee102d9d3b979ca96e7ff4'
    'e71294831c18554bd4d154780789794b98655a9088687e691130aaf305990f73'
    '03ad460caabc653ce08da004ed7467b4f024d87344e0d9b3546ab0b24f4e85cd'
    '93',
  );

  static final _signingPoint = _bytes(
    '046f4b776a43730a261884dcbcd3a29c20745bf5f66e80b82e8f54217395b369'
    '6b979a3aca5dbb5a8afe2b8ea30bda03e59abf7f93971214a3a5b5b4952ce271'
    'df729224d361fe645665e4ba3896d316b04484387e1853d3803242b02013b82c'
    '8a',
  );

  /// The public half of [basicKey], as a SubjectPublicKeyInfo file.
  late final Uint8List basicPublicKeyFile = _publicKeyInfo(_basicPoint);

  /// The root certificate, self-signed, a CA.
  final rootCertificate = base64Decode(
    'MIIB0jCCAVmgAwIBAgIBATAKBggqhkjOPQQDAzBCMQswCQYDVQQGDAJCRTESMBAG'
    'A1UECgwJU0lNVUxBVEVEMR8wHQYDVQQDDBZTaW11bGF0ZWQgQmVsZ2l1bSBSb290'
    'MB4XDTIwMDEwMTAwMDAwMFoXDTQ5MTIzMTIzNTk1OVowQjELMAkGA1UEBgwCQkUx'
    'EjAQBgNVBAoMCVNJTVVMQVRFRDEfMB0GA1UEAwwWU2ltdWxhdGVkIEJlbGdpdW0g'
    'Um9vdDB2MBAGByqGSM49AgEGBSuBBAAiA2IABIXOa228hotX7dAOx526OuUYnb2Y'
    '+SV+ZXOBHDjBxoV8XsTsA9QL/Oz1Tok/ABH7/XFJe74jLw8s+Hyw6tM4iz+rgUlw'
    'i1ttlVIvh18AANBHHZuFpCfjecSsvdL7zcuz9qMjMCEwDwYDVR0TAQH/BAUwAwEB'
    '/zAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDZwAwZAIwFndSkEw9ME6RUWjT'
    'Xl0LwaU9q8P7lCWCwIKU8WHfmD2+DgEGFIFZDEj74z+BdMajAjBGAul0OQlp/BGX'
    'tCaiLZreSsdjx6B/LebawhtuV6yNE44q0Z8C9ASrR7ZPVhHrdAk=',
  );

  /// The national register's certificate, issued by [rootCertificate].
  final registerCertificate = base64Decode(
    'MIIBpTCCASugAwIBAgIBAjAKBggqhkjOPQQDAzBCMQswCQYDVQQGDAJCRTESMBAG'
    'A1UECgwJU0lNVUxBVEVEMR8wHQYDVQQDDBZTaW11bGF0ZWQgQmVsZ2l1bSBSb290'
    'MB4XDTIwMDEwMTAwMDAwMFoXDTQ5MTIzMTIzNTk1OVowOTELMAkGA1UEBgwCQkUx'
    'EjAQBgNVBAoMCVNJTVVMQVRFRDEWMBQGA1UEAwwNU2ltdWxhdGVkIFJSTjB2MBAG'
    'ByqGSM49AgEGBSuBBAAiA2IABPpPpxBFUKf72VnmXJl1B+iZQ/O5rOUST8Nx8ma1'
    'jbYDXPDKlKFbOhmHe060WMa4lmA6B6X1FOUjSdUnOZ+RBGECoSTb0s2UhwhY+8Fk'
    '90g9bAVuHxmv5yD8fovKeMC8DzAKBggqhkjOPQQDAwNoADBlAjAqgOrZodCl9pi5'
    'Xb1OHPClf6TOEp6oJdlIwnLygvTL5ZSQAqDExKG7+DoHD0Je+IUCMQDrlllILkG7'
    'lpgf5rzxt/OxKjI50LE/IPuebFZlmbfv+5ekcTXR2ZUJi6l5i+eIE0A=',
  );

  /// The citizen CA's certificate, issued by [rootCertificate].
  final caCertificate = base64Decode(
    'MIIB0TCCAVegAwIBAgIBAzAKBggqhkjOPQQDAzBCMQswCQYDVQQGDAJCRTESMBAG'
    'A1UECgwJU0lNVUxBVEVEMR8wHQYDVQQDDBZTaW11bGF0ZWQgQmVsZ2l1bSBSb290'
    'MB4XDTIwMDEwMTAwMDAwMFoXDTQ5MTIzMTIzNTk1OVowQDELMAkGA1UEBgwCQkUx'
    'EjAQBgNVBAoMCVNJTVVMQVRFRDEdMBsGA1UEAwwUU2ltdWxhdGVkIENpdGl6ZW4g'
    'Q0EwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAASAdod6HXVYMSEkmldBaDhPd9bQC1b4'
    '8zTTH6Gu+fH1tfx2mCgZlXbwBlnDUN71t8FX/gSsLvYTqQksX/dapzvvWWud0wq2'
    'WylQMc6ekcWO4DbeXbDCuC/tTFR3+/c1irGjIzAhMA8GA1UdEwEB/wQFMAMBAf8w'
    'DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCLauZnzS8XuByzteqW'
    'utt0uzQLmTNCdP5NFLPXwsmbTsIhuhN+U4vFDbZgutrftYgCMEyllZpO8cyzYtMe'
    'Ti8KlEhZ017+Tgla/AfxHv+8NJPMxf7KS8ddD1hSaHlKOzeKlw==',
  );

  static final _caName = _name('Simulated Citizen CA');

  /// Signs a 48 byte [digest] with [key], unhashed, as raw r and s.
  Uint8List signDigest(BigInt key, List<int> digest) {
    final (r, s) = p384Sign(key, digest);
    return Uint8List.fromList([...bigIntBytes(r, 48), ...bigIntBytes(s, 48)]);
  }

  /// The register's DER encoded ECDSA P-384 signature of [data].
  Future<Uint8List> sign(List<int> data) =>
      _sign(_registerKey, _registerPoint, data);

  /// The holder's authentication and signature certificates, issued by
  /// [caCertificate].
  Future<(Uint8List, Uint8List)> holderCertificates({
    required String lastName,
    required String firstNames,
    required String nationalNumber,
  }) async {
    final key = '$lastName|$firstNames|$nationalNumber';
    return _holders[key] ??= await () async {
      Future<Uint8List> holder(int serial, String purpose, Uint8List point) =>
          _certificate(
            serial,
            derSequence([
              _attribute('2.5.4.6', 'BE'),
              _attribute('2.5.4.3', '$firstNames $lastName ($purpose)'),
              _attribute('2.5.4.4', lastName),
              _attribute('2.5.4.42', firstNames),
              _attribute('2.5.4.5', nationalNumber),
            ]),
            point,
          );
      return (
        await holder(10, 'Authentication', _authenticationPoint),
        await holder(11, 'Signature', _signingPoint),
      );
    }();
  }

  // Signing is slow: each result is kept for the next card. Values, not
  // futures, which may belong to a zone that is gone.
  final _holders = <String, (Uint8List, Uint8List)>{};
  static final _signatures = <String, Uint8List>{};

  static Future<Uint8List> _sign(
    BigInt key,
    Uint8List point,
    List<int> data,
  ) async {
    final bytes = Uint8List.fromList(data);
    final id = '${hexString(point)}:${sha384.convert(bytes)}';
    return _signatures[id] ??= await signP384(key, point, bytes);
  }

  // A certificate for [subjectPoint], issued by the citizen CA.
  static Future<Uint8List> _certificate(
    int serial,
    Uint8List subject,
    Uint8List subjectPoint,
  ) async {
    final algorithm = derSequence([derObjectIdentifier('1.2.840.10045.4.3.3')]);
    final signed = derSequence([
      derEncode(0xA0, derInteger(BigInt.two)),
      derInteger(BigInt.from(serial)),
      algorithm,
      _caName,
      derSequence([_time('200101000000Z'), _time('491231235959Z')]),
      subject,
      _publicKeyInfo(subjectPoint),
    ]);
    return derSequence([
      signed,
      algorithm,
      derBitString(await _sign(_caKey, _caPoint, signed)),
    ]);
  }

  static Uint8List _publicKeyInfo(Uint8List point) => derSequence([
        derSequence([
          derObjectIdentifier('1.2.840.10045.2.1'),
          derObjectIdentifier('1.3.132.0.34'),
        ]),
        derBitString(point),
      ]);

  static Uint8List _name(String commonName) => derSequence([
        _attribute('2.5.4.6', 'BE'),
        _attribute('2.5.4.10', 'SIMULATED'),
        _attribute('2.5.4.3', commonName),
      ]);

  static Uint8List _attribute(String type, String value) => derEncode(0x31, [
        ...derSequence([
          derObjectIdentifier(type),
          derEncode(0x0C, utf8.encode(value)),
        ]),
      ]);

  static Uint8List _time(String utc) => derEncode(0x17, ascii.encode(utc));
}
