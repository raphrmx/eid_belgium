import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_language.dart';

/// Writes [date] in [language]: `13 mars 2024`, `13 maart 2024`,
/// `13. März 2024`, `13 March 2024`, or `13.03.2024` when [numeric].
String formatBelgianDate(
  DateTime date,
  BelgianLanguage language, {
  bool numeric = false,
}) =>
    formatBelgianPartialDate(
      PartialDate(date.year, date.month, date.day),
      language,
      numeric: numeric,
    );

/// Writes [date] in [language], leaving out what the register does not know:
/// `15 mai 1990`, `mai 1990`, `1990`; numeric, `15.05.1990`, `05.1990`.
String formatBelgianPartialDate(
  PartialDate date,
  BelgianLanguage language, {
  bool numeric = false,
}) {
  final PartialDate(:year, :month, :day) = date;
  if (month == null) return '$year';
  if (numeric) {
    final monthText = month.toString().padLeft(2, '0');
    return day == null
        ? '$monthText.$year'
        : '${day.toString().padLeft(2, '0')}.$monthText.$year';
  }
  final monthName = _months[language]![month - 1];
  if (day == null) return '$monthName $year';
  return language == BelgianLanguage.de
      ? '$day. $monthName $year'
      : '$day $monthName $year';
}

const _months = {
  BelgianLanguage.fr: [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', //
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ],
  BelgianLanguage.nl: [
    'januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', //
    'augustus', 'september', 'oktober', 'november', 'december',
  ],
  BelgianLanguage.de: [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', //
    'August', 'September', 'Oktober', 'November', 'Dezember',
  ],
  BelgianLanguage.en: [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ],
};

/// The name of a [Sex] in each language.
extension BelgianSexLabel on Sex {
  /// `Féminin`, `Vrouwelijk`, `Weiblich`, `Female`, and so on.
  String label(BelgianLanguage language) => switch (this) {
        Sex.female => const [
            'Féminin',
            'Vrouwelijk',
            'Weiblich',
            'Female',
          ][language.index],
        Sex.male => const [
            'Masculin',
            'Mannelijk',
            'Männlich',
            'Male',
          ][language.index],
        Sex.unspecified => const [
            'Non précisé',
            'Niet vermeld',
            'Nicht angegeben',
            'Unspecified',
          ][language.index],
      };
}
