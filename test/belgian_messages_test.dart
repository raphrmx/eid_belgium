import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  group('formatBelgianDate', () {
    final date = DateTime.utc(2024, 3, 13);

    test('writes the month in each language', () {
      expect(formatBelgianDate(date, BelgianLanguage.fr), '13 mars 2024');
      expect(formatBelgianDate(date, BelgianLanguage.nl), '13 maart 2024');
      expect(formatBelgianDate(date, BelgianLanguage.de), '13. März 2024');
      expect(formatBelgianDate(date, BelgianLanguage.en), '13 March 2024');
      expect(
        formatBelgianDate(date, BelgianLanguage.fr, numeric: true),
        '13.03.2024',
      );
    });

    test('leaves out what the register does not know', () {
      expect(
        formatBelgianPartialDate(PartialDate(1990, 5), BelgianLanguage.fr),
        'mai 1990',
      );
      expect(
        formatBelgianPartialDate(
          PartialDate(1990, 5),
          BelgianLanguage.nl,
          numeric: true,
        ),
        '05.1990',
      );
      expect(
        formatBelgianPartialDate(PartialDate(1990), BelgianLanguage.de),
        '1990',
      );
    });
  });

  test('names the sex in each language', () {
    expect(Sex.female.label(BelgianLanguage.fr), 'Féminin');
    expect(Sex.male.label(BelgianLanguage.nl), 'Mannelijk');
    expect(Sex.unspecified.label(BelgianLanguage.en), 'Unspecified');
  });

  test('writes the full name and the address lines', () async {
    final eid = await BelgianEidReader(SimulatedBelgianCard()).read();
    expect(eid.identity.fullName, 'Alice Marie Specimen');
    expect(eid.address!.lines, ['Rue de la Loi 16', '1000 Bruxelles']);
  });

  group('belgianErrorMessage', () {
    Future<Exception> failure(SimulatedBelgianCard card) async {
      try {
        await BelgianEidReader(card).read();
      } on Exception catch (error) {
        return error;
      }
      fail('The card was read');
    }

    test('says why a card was turned down', () async {
      final expired = await failure(
        SimulatedBelgianCard(validUntil: DateTime.utc(2024, 3, 13)),
      );
      expect(
        belgianErrorMessage(expired, BelgianLanguage.fr),
        'Carte expirée le 13.03.2024',
      );
      expect(
        belgianErrorMessage(expired, BelgianLanguage.de),
        'Karte abgelaufen am 13.03.2024',
      );

      final cloned = await failure(SimulatedBelgianCard(cloned: true));
      expect(
        belgianErrorMessage(cloned, BelgianLanguage.nl),
        'De chip kon niet bewijzen dat hij echt is',
      );

      final tampered = await failure(
        SimulatedBelgianCard(tamperedLastName: 'Mallory'),
      );
      expect(
        belgianErrorMessage(tampered, BelgianLanguage.en),
        "The card's data is not signed by the National Register",
      );
    });

    test('names a document type not accepted', () async {
      Exception? error;
      try {
        await BelgianEidReader(
          SimulatedBelgianCard(documentType: BelgianDocumentType.euCard),
        ).read(acceptedTypes: {BelgianDocumentType.eid});
      } on Exception catch (e) {
        error = e;
      }
      expect(
        belgianErrorMessage(error!, BelgianLanguage.fr),
        "Ce type de carte n'est pas accepté : Carte EU",
      );
    });

    test('counts the PIN tries left', () {
      expect(
        belgianErrorMessage(const PinException(2), BelgianLanguage.fr),
        'PIN erroné, 2 essais restants',
      );
      expect(
        belgianErrorMessage(const PinException(1), BelgianLanguage.en),
        'Wrong PIN, 1 try left',
      );
      expect(
        belgianErrorMessage(const PinException(0), BelgianLanguage.nl),
        'Pincode geblokkeerd: alleen de gemeente kan hem deblokkeren',
      );
    });

    test('covers the card going away and anything else', () {
      for (final language in BelgianLanguage.values) {
        for (final error in <Exception>[
          const CardTransportException('gone'),
          const FormatException('bad'),
          const CardException('READ BINARY', 0x6982),
          const PinCancelledException(),
        ]) {
          expect(belgianErrorMessage(error, language), isNotEmpty);
        }
      }
    });
  });
}
