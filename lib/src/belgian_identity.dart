import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_document_type.dart';
import 'package:eid_belgium/src/simplified_tlv.dart';
import 'package:eid_belgium/src/text_fields.dart';

/// The identity file of a Belgian card.
///
/// Text is as printed, in the issuing municipality's language.
final class BelgianIdentity {
  /// The identity file with the given fields; see also [parse].
  const BelgianIdentity({
    required this.file,
    required this.fields,
    required this.cardNumber,
    required this.chipNumber,
    required this.validFrom,
    required this.validUntil,
    required this.issuingMunicipality,
    required this.nationalNumber,
    required this.lastName,
    required this.firstNames,
    required this.thirdGivenNameInitial,
    required this.nationality,
    required this.birthPlace,
    required this.birthDateText,
    required this.birthDate,
    required this.sex,
    required this.nobleCondition,
    required this.documentTypeCode,
    required this.specialStatus,
    required this.photoHash,
    required this.duplicate,
    required this.specialOrganisation,
    required this.memberOfFamily,
    required this.dateAndCountryOfProtection,
    required this.workPermitMention,
    required this.employerVatNumber1,
    required this.employerVatNumber2,
    required this.regionalFileNumber,
    required this.basicKeyHash,
    required this.brexitMention1,
    required this.brexitMention2,
    required this.cardAMention1,
    required this.cardAMention2,
    required this.registrationDate,
  });

  /// Reads the identity [file] as the card holds it.
  ///
  /// Unless [withNationalNumber], the national number is removed from
  /// [nationalNumber] and [fields], and [file] is not kept. Throws a
  /// [FormatException] when the file is malformed or incomplete.
  factory BelgianIdentity.parse(
    Uint8List file, {
    bool withNationalNumber = true,
  }) {
    var fields = parseSimplifiedTlv(file);
    fields.requiredText(0x06, 'national number');
    if (!withNationalNumber) {
      fields = Map.unmodifiable({
        for (final MapEntry(:key, :value) in fields.entries)
          if (key != 0x06) key: Uint8List.fromList(value),
      });
    }
    return BelgianIdentity.fromFields(
      fields,
      file: withNationalNumber ? file : null,
    );
  }

  /// The identity file from its [fields] by tag, and its raw [file] when
  /// known. Throws a [FormatException] when a required field is missing.
  factory BelgianIdentity.fromFields(
    Map<int, Uint8List> fields, {
    Uint8List? file,
  }) {
    final birthDateText = fields.requiredText(0x0C, 'birth date');
    return BelgianIdentity(
      file: file,
      fields: Map.unmodifiable(fields),
      cardNumber: fields.requiredText(0x01, 'card number'),
      chipNumber: fields[0x02] ?? Uint8List(0),
      validFrom: _requiredDate(fields, 0x03, 'validity start'),
      validUntil: _requiredDate(fields, 0x04, 'validity end'),
      issuingMunicipality: fields.requiredText(0x05, 'issuing municipality'),
      nationalNumber: fields.text(0x06),
      lastName: fields.requiredText(0x07, 'name'),
      firstNames: fields.text(0x08) ?? '',
      thirdGivenNameInitial: fields.text(0x09),
      nationality: fields.requiredText(0x0A, 'nationality'),
      birthPlace: fields.requiredText(0x0B, 'birth place'),
      birthDateText: birthDateText,
      birthDate: parseBirthDate(birthDateText),
      sex: switch (fields.text(0x0D)) {
        'M' => Sex.male,
        'F' || 'V' || 'W' => Sex.female,
        _ => Sex.unspecified,
      },
      nobleCondition: fields.text(0x0E),
      documentTypeCode: _requiredNumber(fields, 0x0F, 'document type'),
      specialStatus: int.tryParse(fields.text(0x10) ?? '') ?? 0,
      photoHash: fields[0x11] ?? Uint8List(0),
      duplicate: fields.text(0x12),
      specialOrganisation: fields.text(0x13),
      memberOfFamily: fields.containsKey(0x14),
      dateAndCountryOfProtection: fields.text(0x15),
      workPermitMention: fields.text(0x16),
      employerVatNumber1: fields.text(0x17),
      employerVatNumber2: fields.text(0x18),
      regionalFileNumber: fields.text(0x19),
      basicKeyHash: fields[0x1A],
      brexitMention1: fields.text(0x1B),
      brexitMention2: fields.text(0x1C),
      cardAMention1: fields.text(0x1D),
      cardAMention2: fields.text(0x1E),
      registrationDate: parseDottedDate(fields.text(0x1F)),
    );
  }

  /// The file as read and signed, or null when the national number was
  /// left out.
  final Uint8List? file;

  /// Every field of the file by tag, including unknown ones.
  final Map<int, Uint8List> fields;

  /// The card number, such as `592123456789`.
  final String cardNumber;

  /// The chip's serial number.
  final Uint8List chipNumber;

  /// The first day the card is valid.
  final DateTime validFrom;

  /// The last day the card is valid.
  final DateTime validUntil;

  /// The municipality that issued the card.
  final String issuingMunicipality;

  /// The national register number, eleven digits, or null when left out.
  ///
  /// Belgian law restricts storing or processing it without authorisation.
  final String? nationalNumber;

  /// The last name.
  final String lastName;

  /// The first two given names, separated by a space, or empty.
  final String firstNames;

  /// The initial of the third given name, when there is one.
  final String? thirdGivenNameInitial;

  /// The nationality, in the language of the card.
  final String nationality;

  /// The place of birth.
  final String birthPlace;

  /// The birth date as written on the card, such as `12 MARS 1985`.
  final String birthDateText;

  /// [birthDateText] as a date, possibly without day or month, or null when
  /// unreadable.
  final PartialDate? birthDate;

  /// The sex.
  final Sex sex;

  /// The noble title, when the holder has one.
  final String? nobleCondition;

  /// The document type code; see [documentType].
  final int documentTypeCode;

  /// The special status code, 0 for none; see [hasWhiteCane].
  final int specialStatus;

  /// The hash of the photo file; see [matchesPhoto].
  final Uint8List photoHash;

  /// The duplicate number, when the card is one.
  final String? duplicate;

  /// The special organisation code of a residence card, such as `2` (NATO).
  final String? specialOrganisation;

  /// Whether the residence card marks the holder as a family member.
  final bool memberOfFamily;

  /// The date and country of protection, as `dd.MM.yyyy-CC`.
  final String? dateAndCountryOfProtection;

  /// The labour market mention of a residence card, such as `7` (unlimited).
  final String? workPermitMention;

  /// The first employer's VAT number, as `xxxx.xxx.xxx`.
  final String? employerVatNumber1;

  /// The second employer's VAT number, as `xxxx.xxx.xxx`.
  final String? employerVatNumber2;

  /// The regional file number.
  final String? regionalFileNumber;

  /// The hash of the basic public key file, on cards from applet 1.8 on.
  final Uint8List? basicKeyHash;

  /// The first Brexit withdrawal agreement mention, such as `B`.
  final String? brexitMention1;

  /// The second Brexit withdrawal agreement mention, such as `C`.
  final String? brexitMention2;

  /// The first mention of an A-card, such as `D` for a student.
  final String? cardAMention1;

  /// The second mention of an A-card: `K` for a mobility programme.
  final String? cardAMention2;

  /// The registration date of an EU card, or of permanent residence (EU+).
  final DateTime? registrationDate;

  /// The document type, or null when [documentTypeCode] is unknown.
  BelgianDocumentType? get documentType =>
      BelgianDocumentType.fromCode(documentTypeCode);

  /// The given names then the last name: `Alice Marie Specimen`.
  String get fullName =>
      firstNames.isEmpty ? lastName : '$firstNames $lastName';

  /// The holder's age today; see [ageOn].
  int? get age => ageOn(DateTime.now());

  /// The holder's age in full years on [date], or null when the partial
  /// birth date does not settle it.
  int? ageOn(DateTime date) => birthDate?.ageOn(date);

  /// Whether the holder is certainly 18 or older today.
  bool get isAdult => isAdultOn(DateTime.now());

  /// Whether the holder is certainly [age] or older on [date]. A partial
  /// birth date never answers yes too early; an unreadable one gives false.
  bool isAdultOn(DateTime date, {int age = 18}) =>
      (birthDate?.minimumAgeOn(date) ?? -1) >= age;

  /// Whether the card is past its last valid day today.
  bool get isExpired => isExpiredOn(DateTime.now());

  /// Whether the calendar day of [date] is after [validUntil].
  bool isExpiredOn(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).isAfter(validUntil);

  /// Whether the card carries the white cane status, for blind people.
  bool get hasWhiteCane => specialStatus == 1 || specialStatus == 3;

  /// Whether the card carries the yellow cane status, for low vision.
  bool get hasYellowCane => specialStatus == 4 || specialStatus == 5;

  /// Whether the card carries the extended minority status.
  bool get hasExtendedMinority =>
      specialStatus == 2 || specialStatus == 3 || specialStatus == 5;

  /// Whether [photo] matches [photoHash].
  bool matchesPhoto(List<int> photo) {
    final Hash? algorithm = switch (photoHash.length) {
      20 => sha1,
      32 => sha256,
      48 => sha384,
      _ => null,
    };
    if (algorithm == null) return false;
    final digest = algorithm.convert(photo).bytes;
    var difference = 0;
    for (var i = 0; i < digest.length; i++) {
      difference |= digest[i] ^ photoHash[i];
    }
    return difference == 0;
  }

  /// The identity as JSON: [file] or [fields] in base64, plus the main
  /// fields as plain values.
  Map<String, Object?> toJson() => {
        if (file case final file?) 'file': base64Encode(file),
        'fields': {
          for (final MapEntry(:key, :value) in fields.entries)
            '$key': base64Encode(value),
        },
        'cardNumber': cardNumber,
        'documentType': documentType?.name,
        'documentTypeCode': documentTypeCode,
        'validFrom': _isoDay(validFrom),
        'validUntil': _isoDay(validUntil),
        'issuingMunicipality': issuingMunicipality,
        if (nationalNumber case final number?) 'nationalNumber': number,
        'lastName': lastName,
        'firstNames': firstNames,
        'thirdGivenNameInitial': thirdGivenNameInitial,
        'nationality': nationality,
        'birthPlace': birthPlace,
        'birthDate': birthDate?.toString(),
        'birthDateText': birthDateText,
        'sex': sex.name,
      };

  /// The identity [toJson] wrote, rebuilt from the file or fields only.
  /// Throws a [FormatException] on malformed [json].
  factory BelgianIdentity.fromJson(Map<String, Object?> json) {
    final file = json['file'];
    if (file is String) return BelgianIdentity.parse(_base64(file));
    final fields = json['fields'];
    if (fields is! Map<String, Object?>) {
      throw const FormatException('The identity has neither file nor fields');
    }
    return BelgianIdentity.fromFields({
      for (final MapEntry(:key, :value) in fields.entries)
        int.tryParse(key) ?? (throw FormatException('Not a field tag', key)):
            _base64(value),
    });
  }

  @override
  String toString() => 'BelgianIdentity($lastName, $firstNames, $cardNumber)';
}

DateTime _requiredDate(Map<int, Uint8List> fields, int tag, String name) {
  final text = fields.requiredText(tag, name);
  return parseDottedDate(text) ??
      (throw FormatException('The $name is not a DD.MM.YYYY date', text));
}

int _requiredNumber(Map<int, Uint8List> fields, int tag, String name) {
  final text = fields.requiredText(tag, name);
  return int.tryParse(text) ??
      (throw FormatException('The $name is not a number', text));
}

String _isoDay(DateTime date) => date.toIso8601String().substring(0, 10);

Uint8List _base64(Object? value) {
  if (value is! String) throw FormatException('Not base64', value);
  return base64Decode(value);
}
