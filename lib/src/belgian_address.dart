import 'dart:convert';
import 'dart:typed_data';

import 'package:eid_belgium/src/simplified_tlv.dart';
import 'package:eid_belgium/src/text_fields.dart';

/// The address file of a Belgian card, which only the contact chip holds.
final class BelgianAddress {
  /// The address with the given fields; [parse] reads one from the card.
  const BelgianAddress({
    required this.file,
    required this.fields,
    required this.streetAndNumber,
    required this.postalCode,
    required this.municipality,
  });

  /// Reads the address [file]. Throws a [FormatException] if malformed.
  factory BelgianAddress.parse(Uint8List file) {
    final fields = parseSimplifiedTlv(file);
    return BelgianAddress(
      file: file,
      fields: fields,
      streetAndNumber: fields.text(0x01) ?? '',
      postalCode: fields.text(0x02) ?? '',
      municipality: fields.text(0x03) ?? '',
    );
  }

  /// The file as read from the card, padding included.
  final Uint8List file;

  /// Every field of the file by tag.
  final Map<int, Uint8List> fields;

  /// The street and house number, such as `Rue de la Loi 16`.
  final String streetAndNumber;

  /// The postal code, such as `1000`.
  final String postalCode;

  /// The municipality, in the language of the card.
  final String municipality;

  /// The address as JSON, which [BelgianAddress.fromJson] reads back.
  Map<String, Object?> toJson() => {
        'file': base64Encode(file),
        'streetAndNumber': streetAndNumber,
        'postalCode': postalCode,
        'municipality': municipality,
      };

  /// Reads back what [toJson] wrote. Throws a [FormatException] if invalid.
  factory BelgianAddress.fromJson(Map<String, Object?> json) {
    final file = json['file'];
    if (file is! String) throw const FormatException('The address has no file');
    return BelgianAddress.parse(base64Decode(file));
  }

  /// The address on two lines, as on an envelope.
  List<String> get lines =>
      [streetAndNumber, '$postalCode $municipality'.trim()];

  @override
  String toString() => '$streetAndNumber, $postalCode $municipality';
}
