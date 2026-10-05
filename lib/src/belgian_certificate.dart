part of 'belgian_signature_verifier.dart';

/// An X.509 certificate from a card.
///
/// The holder's certificates carry the national number as the subject's
/// `serialNumber`.
final class BelgianCertificate {
  BelgianCertificate._({
    required this.der,
    required this.serialNumber,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required Uint8List signed,
    required String signatureAlgorithm,
    required Uint8List signature,
    required Uint8List issuerName,
    required Uint8List subjectName,
    required Uint8List keyInfo,
    required PublicKey publicKey,
    required this.isCa,
  })  : _signed = signed,
        _keyInfo = keyInfo,
        _signatureAlgorithm = signatureAlgorithm,
        _signature = signature,
        _issuerName = issuerName,
        _subjectName = subjectName,
        _publicKey = publicKey;

  /// Reads the DER certificate at the start of [bytes], padding allowed.
  ///
  /// Throws a [FormatException] when it is malformed or its key is neither
  /// RSA nor EC P-384.
  factory BelgianCertificate.parse(Uint8List bytes) {
    // A copy: the caller's bytes may change afterwards.
    final element =
        DerElement.parse(Uint8List.fromList(DerElement.parse(bytes).encoded));
    final certificate = element.children;
    if (certificate.length != 3 || certificate[1].children.isEmpty) {
      throw const FormatException('Not a certificate');
    }
    final fields = certificate[0].children;
    // Version 1 certificates have no explicit version field.
    final base = fields.isNotEmpty && fields[0].tag == 0xA0 ? 1 : 0;
    if (fields.length < base + 6) {
      throw const FormatException('Not a certificate');
    }
    final validity = fields[base + 3].children;
    if (validity.length != 2) throw const FormatException('Not a validity');
    return BelgianCertificate._(
      der: element.encoded,
      serialNumber: hexString(fields[base].content),
      issuer: BelgianCertificateName._parse(fields[base + 2]),
      subject: BelgianCertificateName._parse(fields[base + 4]),
      notBefore: _time(validity[0]),
      notAfter: _time(validity[1]),
      signed: certificate[0].encoded,
      signatureAlgorithm: certificate[1].children.first.objectIdentifier,
      signature: certificate[2].bitString,
      issuerName: fields[base + 2].encoded,
      subjectName: fields[base + 4].encoded,
      keyInfo: fields[base + 5].encoded,
      publicKey: parseSubjectPublicKeyInfo(fields[base + 5]),
      isCa: _isCa(fields.skip(base + 6)),
    );
  }

  // basicConstraints cA true, and keyCertSign in keyUsage when present.
  static bool _isCa(Iterable<DerElement> optional) {
    var ca = false;
    var signsCertificates = true;
    for (final field in optional.where(
      (field) => field.tag == 0xA3 && field.children.isNotEmpty,
    )) {
      for (final extension in field.children.first.children) {
        final parts = extension.children;
        if (parts.length < 2) continue;
        final value = DerElement.parse(parts.last.content);
        switch (parts.first.objectIdentifier) {
          case '2.5.29.19':
            final constraints = value.children;
            ca = constraints.isNotEmpty &&
                constraints.first.tag == 0x01 &&
                constraints.first.content.isNotEmpty &&
                constraints.first.content.first != 0;
          case '2.5.29.15':
            final bits = value.content;
            signsCertificates = bits.length > 1 && bits[1] & 0x04 != 0;
        }
      }
    }
    return ca && signsCertificates;
  }

  /// The certificate, DER encoded, without padding.
  final Uint8List der;

  /// The serial number, in hexadecimal.
  final String serialNumber;

  /// Who issued it.
  final BelgianCertificateName issuer;

  /// Whom it names.
  final BelgianCertificateName subject;

  /// The first moment it is valid, in UTC.
  final DateTime notBefore;

  /// The last moment it is valid, in UTC.
  final DateTime notAfter;

  final Uint8List _signed;
  final String _signatureAlgorithm;
  final Uint8List _signature;
  final Uint8List _issuerName;
  final Uint8List _subjectName;
  final Uint8List _keyInfo;
  final PublicKey _publicKey;

  /// Whether it may issue certificates: a root or a CA.
  final bool isCa;

  /// The key type, such as `EC P-384` or `RSA 2048`.
  String get keyAlgorithm => switch (_publicKey) {
        final RSAPublicKey key => 'RSA ${key.modulus!.bitLength}',
        _ => 'EC P-384',
      };

  /// Whether it names its own issuer, as a root does.
  bool get isSelfIssued => sameBytes(_issuerName, _subjectName);

  /// Whether [date] is past [notAfter].
  bool isExpiredOn(DateTime date) => date.toUtc().isAfter(notAfter);

  /// Whether it is past [notAfter] now.
  bool get isExpired => isExpiredOn(DateTime.now());

  @override
  String toString() => 'BelgianCertificate(${subject.commonName})';

  // UTCTime, YYMMDDHHMMSSZ, or GeneralizedTime, YYYYMMDDHHMMSSZ.
  static DateTime _time(DerElement element) {
    final text = ascii.decode(element.content, allowInvalid: true);
    final match = switch (element.tag) {
      0x17 => RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$')
          .firstMatch(text),
      0x18 => RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$')
          .firstMatch(text),
      _ => null,
    };
    if (match == null) throw FormatException('Not a certificate time', text);
    var year = int.parse(match[1]!);
    // UTCTime years 50 to 99 are 1950 to 1999.
    if (element.tag == 0x17) year += year < 50 ? 2000 : 1900;
    return DateTime.utc(
      year,
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }
}

/// The name a certificate gives its subject or issuer.
final class BelgianCertificateName {
  const BelgianCertificateName._(this.attributes);

  factory BelgianCertificateName._parse(DerElement name) {
    final attributes = <String, String>{};
    for (final relative in name.children) {
      for (final pair in relative.children) {
        final parts = pair.children;
        if (parts.length != 2) continue;
        attributes[parts[0].objectIdentifier] = _text(parts[1]);
      }
    }
    return BelgianCertificateName._(Map.unmodifiable(attributes));
  }

  /// Every attribute by object identifier, such as `2.5.4.3`.
  final Map<String, String> attributes;

  /// The common name, such as `Citizen CA`.
  String? get commonName => attributes['2.5.4.3'];

  /// The surname.
  String? get surname => attributes['2.5.4.4'];

  /// The given names.
  String? get givenName => attributes['2.5.4.42'];

  /// The serial number; the national number in the holder's certificates.
  String? get serialNumber => attributes['2.5.4.5'];

  /// The country, such as `BE`.
  String? get country => attributes['2.5.4.6'];

  /// The organisation.
  String? get organization => attributes['2.5.4.10'];

  @override
  String toString() => [
        if (commonName case final name?) 'CN=$name',
        if (organization case final organization?) 'O=$organization',
        if (country case final country?) 'C=$country',
      ].join(', ');

  static String _text(DerElement value) {
    final bytes = value.content;
    return switch (value.tag) {
      // BMPString: UTF-16, big endian.
      0x1E => String.fromCharCodes([
          for (var i = 0; i + 1 < bytes.length; i += 2)
            bytes[i] << 8 | bytes[i + 1],
        ]),
      // TeletexString: Latin-1 in practice.
      0x14 => latin1.decode(bytes),
      _ => utf8.decode(bytes, allowMalformed: true),
    };
  }
}
