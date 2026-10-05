import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_card_rejected.dart';
import 'package:eid_belgium/src/belgian_formatting.dart';
import 'package:eid_belgium/src/belgian_language.dart';
import 'package:eid_belgium/src/pin.dart';

/// A sentence to show the holder for [error], in [language]: whatever a
/// `BelgianCardReadFailed` carries, a `PinException` or a
/// `CardTransportException`.
///
/// ```dart
/// case BelgianCardReadFailed failed:
///   showError(belgianErrorMessage(failed.error, BelgianLanguage.fr));
/// ```
String belgianErrorMessage(Exception error, BelgianLanguage language) {
  String say(String fr, String nl, String de, String en) =>
      [fr, nl, de, en][language.index];

  switch (error) {
    case BelgianCardRejectedException(:final reason, :final identity):
      switch (reason) {
        case BelgianCardRejection.expired:
          final day = formatBelgianDate(
            identity.validUntil,
            language,
            numeric: true,
          );
          return say(
            'Carte expirée le $day',
            'Kaart vervallen op $day',
            'Karte abgelaufen am $day',
            'Card expired on $day',
          );
        case BelgianCardRejection.documentType:
          final type = identity.documentType?.label(language) ??
              '${identity.documentTypeCode}';
          return say(
            "Ce type de carte n'est pas accepté : $type",
            'Dit kaarttype wordt niet aanvaard: $type',
            'Dieser Kartentyp wird nicht akzeptiert: $type',
            'This card type is not accepted: $type',
          );
        case BelgianCardRejection.signature:
          return say(
            'Les données de la carte ne sont pas signées par le Registre '
                'national',
            'De gegevens op de kaart zijn niet ondertekend door het '
                'Rijksregister',
            'Die Kartendaten sind nicht vom Nationalregister signiert',
            "The card's data is not signed by the National Register",
          );
        case BelgianCardRejection.notGenuine:
          return say(
            "La puce n'a pas pu prouver qu'elle est authentique",
            'De chip kon niet bewijzen dat hij echt is',
            'Der Chip konnte seine Echtheit nicht nachweisen',
            'The chip could not prove it is genuine',
          );
      }
    case PinException(isBlocked: true):
      return say(
        'PIN bloqué : seule la commune peut le débloquer',
        'Pincode geblokkeerd: alleen de gemeente kan hem deblokkeren',
        'PIN gesperrt: nur die Gemeinde kann sie entsperren',
        'PIN blocked: only the municipality can unblock it',
      );
    case PinException(triesLeft: 1):
      return say(
        "PIN erroné, plus qu'un essai",
        'Verkeerde pincode, nog één poging',
        'Falsche PIN, noch ein Versuch',
        'Wrong PIN, 1 try left',
      );
    case PinException(:final triesLeft):
      return say(
        'PIN erroné, $triesLeft essais restants',
        'Verkeerde pincode, nog $triesLeft pogingen',
        'Falsche PIN, noch $triesLeft Versuche',
        'Wrong PIN, $triesLeft tries left',
      );
    case PinCancelledException():
      return say(
        "Le PIN n'a pas été saisi",
        'De pincode werd niet ingevoerd',
        'Die PIN wurde nicht eingegeben',
        'No PIN was given',
      );
    case CardTransportException():
      return say(
        'La carte ne répond pas : est-elle bien insérée ?',
        'De kaart antwoordt niet: zit ze goed in de lezer?',
        'Die Karte antwortet nicht: steckt sie richtig im Leser?',
        'The card does not answer: is it in the reader?',
      );
    case FormatException():
      return say(
        'La carte contient des données inattendues',
        'De kaart bevat onverwachte gegevens',
        'Die Karte enthält unerwartete Daten',
        'The card holds unexpected data',
      );
    default:
      return say(
        'La carte a refusé la lecture',
        'De kaart weigerde het lezen',
        'Die Karte hat das Lesen verweigert',
        'The card refused to be read',
      );
  }
}
