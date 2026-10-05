import 'dart:convert';
import 'dart:typed_data';

import 'package:eid/eid.dart';

/// Text decoding of simplified TLV fields.
extension TextFields on Map<int, Uint8List> {
  /// The field [tag] as text, trimmed, or null when absent or blank.
  String? text(int tag) {
    final bytes = this[tag];
    if (bytes == null) return null;
    final value = utf8.decode(bytes, allowMalformed: true).trim();
    return value.isEmpty ? null : value;
  }

  /// The field [tag] as text; throws a [FormatException] if absent or blank.
  String requiredText(int tag, String name) =>
      text(tag) ?? (throw FormatException('The card has no $name'));
}

/// Reads a `DD.MM.YYYY` date, or null when [text] is not one.
DateTime? parseDottedDate(String? text) {
  if (text == null) return null;
  final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  // DateTime rolls 31.02 over into March; the card never means that.
  return date.month == month && date.day == day ? date : null;
}

/// Reads a birth date such as `12 MARS 1985` or `12.MÄR.1985`. An unknown
/// day or month is null; returns null when the year cannot be read.
PartialDate? parseBirthDate(String text) {
  final parts = text.trim().split(_dateSeparators);
  final year = int.tryParse(parts.last);
  if (year == null || year < 1 || year > 9999) return null;

  // Blank days and months vanish in the split, so read from the right.
  final head = parts.sublist(0, parts.length - 1);
  final month = head.isEmpty ? null : _months[head.last.toUpperCase()];
  final dayText = head.length < 2 ? null : head[head.length - 2];
  final day = month == null || dayText == null ? null : int.tryParse(dayText);
  final isDay =
      day != null && day >= 1 && day <= DateTime.utc(year, month! + 1, 0).day;

  return PartialDate(year, month, isDay ? day : null);
}

final _dateSeparators = RegExp('[ .]+');

/// Month abbreviations in French, Dutch, German and English, accented or not.
const _months = {
  'JAN': 1,
  'FEV': 2,
  'FÉV': 2,
  'FEB': 2,
  'MARS': 3,
  'MAAR': 3,
  'MÄR': 3,
  'MAR': 3,
  'AVR': 4,
  'APR': 4,
  'MAI': 5,
  'MEI': 5,
  'MAY': 5,
  'JUIN': 6,
  'JUN': 6,
  'JUIL': 7,
  'JUL': 7,
  'AOUT': 8,
  'AOÛT': 8,
  'AUG': 8,
  'SEPT': 9,
  'SEP': 9,
  'OCT': 10,
  'OKT': 10,
  'NOV': 11,
  'DEC': 12,
  'DÉC': 12,
  'DEZ': 12,
};
