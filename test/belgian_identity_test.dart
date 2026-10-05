import 'package:crypto/crypto.dart';
import 'package:eid_belgium/eid_belgium.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('BelgianIdentity.parse', () {
    final identity = BelgianIdentity.parse(identityFile());

    test('reads the fields every card carries', () {
      expect(identity.cardNumber, '592123456789');
      expect(identity.chipNumber, List.generate(16, (i) => i));
      expect(identity.validFrom, DateTime.utc(2022, 3, 14));
      expect(identity.validUntil, DateTime.utc(2032, 3, 14));
      expect(identity.issuingMunicipality, 'Bruxelles');
      expect(identity.nationalNumber, '85073003328');
      expect(identity.lastName, 'Dupont');
      expect(identity.firstNames, 'Marie Élise');
      expect(identity.thirdGivenNameInitial, 'J');
      expect(identity.nationality, 'Belge');
      expect(identity.birthPlace, 'Namur');
      expect(identity.birthDate, PartialDate(1985, 7, 30));
      expect(identity.sex, Sex.female);
      expect(identity.documentType, BelgianDocumentType.eid);
      expect(identity.basicKeyHash, hasLength(48));
    });

    test('leaves blank fields null', () {
      expect(identity.nobleCondition, isNull);
      expect(identity.duplicate, isNull);
      expect(identity.workPermitMention, isNull);
      expect(identity.memberOfFamily, isFalse);
      expect(identity.hasWhiteCane, isFalse);
    });

    test('reads the fields of a residence card', () {
      final card = BelgianIdentity.parse(
        identityFile(
          extra: {
            0x0F: '31',
            0x10: '3',
            0x14: '',
            0x16: '7',
            0x17: '0123.456.789',
            0x1F: '02.05.2019',
          },
        ),
      );
      expect(card.documentType, BelgianDocumentType.euCard);
      expect(card.hasWhiteCane, isTrue);
      expect(card.hasExtendedMinority, isTrue);
      expect(card.memberOfFamily, isTrue);
      expect(card.workPermitMention, '7');
      expect(card.employerVatNumber1, '0123.456.789');
      expect(card.registrationDate, DateTime.utc(2019, 5, 2));
    });

    test('keeps a document type it does not know', () {
      final card = BelgianIdentity.parse(identityFile(extra: {0x0F: '99'}));
      expect(card.documentTypeCode, 99);
      expect(card.documentType, isNull);
    });

    test('keeps a field it does not name', () {
      final card = BelgianIdentity.parse(identityFile(extra: {0x30: 'new'}));
      expect(card.fields[0x30], 'new'.codeUnits);
    });

    test('refuses a file without a mandatory field', () {
      expect(
        () => BelgianIdentity.parse(tlv({0x01: '592123456789'})),
        throwsFormatException,
      );
    });
  });

  group('birth date', () {
    PartialDate? read(String text) =>
        BelgianIdentity.parse(identityFile(birthDate: text)).birthDate;

    test('reads the three languages of the card', () {
      expect(read('12 MARS 1985'), PartialDate(1985, 3, 12));
      expect(read('12 MAAR 1985'), PartialDate(1985, 3, 12));
      expect(read('12.MÄR.1985'), PartialDate(1985, 3, 12));
      expect(read('01 AOUT 2001'), PartialDate(2001, 8, 1));
      expect(read('01 MEI 2001'), PartialDate(2001, 5, 1));
      expect(read('24.DEZ.1970'), PartialDate(1970, 12, 24));
    });

    test('leaves out what the civil register does not know', () {
      expect(read('   .   .1950'), PartialDate(1950));
      expect(read('00 JAN 1950'), PartialDate(1950, 1));
      expect(read('     JAN 1950'), PartialDate(1950, 1));
      expect(read('31 FEV 1985'), PartialDate(1985, 2));
    });

    test('keeps the text when not even the year can be read', () {
      final card = BelgianIdentity.parse(identityFile(birthDate: 'unknown'));
      expect(card.birthDate, isNull);
      expect(card.birthDateText, 'unknown');
    });
  });

  group('matchesPhoto', () {
    test('checks the SHA-384 hash of applet 1.8', () {
      final identity = BelgianIdentity.parse(identityFile());
      expect(identity.matchesPhoto(photo), isTrue);
      expect(identity.matchesPhoto([...photo, 0]), isFalse);
    });

    test('checks the SHA-1 hash of earlier applets', () {
      final identity = BelgianIdentity.parse(
        identityFile(photoHash: sha1.convert(photo).bytes),
      );
      expect(identity.matchesPhoto(photo), isTrue);
    });
  });

  test('BelgianAddress.parse reads the address', () {
    final address = BelgianAddress.parse(addressFile());
    expect(address.streetAndNumber, 'Rue de la Loi 16');
    expect(address.postalCode, '1000');
    expect(address.municipality, 'Bruxelles');
    expect(address.toString(), 'Rue de la Loi 16, 1000 Bruxelles');
  });

  group('isValidBelgianNationalNumber', () {
    test('accepts a number born before 2000, printed or bare', () {
      expect(isValidBelgianNationalNumber('85.07.30-033.28'), isTrue);
      expect(isValidBelgianNationalNumber('85073003328'), isTrue);
    });

    test('accepts a number born from 2000 on', () {
      expect(isValidBelgianNationalNumber('05051512381'), isTrue);
      // The same digits with the check of a birth before 2000.
      expect(isValidBelgianNationalNumber('05051512352'), isTrue);
    });

    test('refuses a wrong check or a wrong length', () {
      expect(isValidBelgianNationalNumber('85073003329'), isFalse);
      expect(isValidBelgianNationalNumber('8507300332'), isFalse);
      expect(isValidBelgianNationalNumber('8507300332A'), isFalse);
    });
  });

  group('formatBelgianNationalNumber', () {
    test('writes the number as the card prints it', () {
      expect(formatBelgianNationalNumber('85073003328'), '85.07.30-033.28');
      expect(formatBelgianNationalNumber('85.07.30-033.28'), '85.07.30-033.28');
    });

    test('hides the sequence and check digits on request', () {
      expect(
        formatBelgianNationalNumber('85073003328', masked: true),
        '85.07.30-***.**',
      );
    });

    test('leaves anything else as it is', () {
      expect(formatBelgianNationalNumber('1234'), '1234');
    });
  });

  test('formatBelgianCardNumber writes the number as the card prints it', () {
    expect(formatBelgianCardNumber('591000000106'), '591-0000001-06');
    expect(formatBelgianCardNumber('B01234567'), 'B01234567');
  });

  group('dates', () {
    final identity = BelgianIdentity.parse(identityFile());

    test('give the age, and whether the holder is an adult', () {
      // Born 30 July 1985.
      expect(identity.ageOn(DateTime(2003, 7, 29)), 17);
      expect(identity.isAdultOn(DateTime(2003, 7, 29)), isFalse);
      expect(identity.ageOn(DateTime(2003, 7, 30)), 18);
      expect(identity.isAdultOn(DateTime(2003, 7, 30)), isTrue);
      expect(identity.isAdultOn(DateTime(2006, 7, 30), age: 21), isTrue);
    });

    test('count an uncertain birth date as late as it can be', () {
      final bornIn1985 = BelgianIdentity.parse(
        identityFile(birthDate: '     1985'),
      );
      expect(bornIn1985.ageOn(DateTime(2003, 7, 30)), isNull);
      expect(bornIn1985.isAdultOn(DateTime(2003, 12, 30)), isFalse);
      expect(bornIn1985.isAdultOn(DateTime(2003, 12, 31)), isTrue);
    });

    test('say whether the card has expired', () {
      // Valid until 14 March 2032, that day included.
      expect(identity.isExpiredOn(DateTime(2032, 3, 14, 23, 59)), isFalse);
      expect(identity.isExpiredOn(DateTime(2032, 3, 15)), isTrue);
    });
  });
}
