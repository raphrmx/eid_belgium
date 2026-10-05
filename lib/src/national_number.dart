final _separators = RegExp(r'[\s.\-]');
final _elevenDigits = RegExp(r'^\d{11}$');

/// Whether [number] is a well formed Belgian national register number.
///
/// Checks only the eleven digits and the check digits, ignoring dots, dashes
/// and spaces. BIS numbers are accepted.
bool isValidBelgianNationalNumber(String number) {
  final digits = number.replaceAll(_separators, '');
  if (!_elevenDigits.hasMatch(digits)) return false;
  final base = int.parse(digits.substring(0, 9));
  final check = int.parse(digits.substring(9));
  return check == 97 - base % 97 || check == 97 - (2000000000 + base) % 97;
}

/// Writes [number] as the card prints it: `85.07.30-033.28`.
///
/// [masked] hides the sequence and check digits: `85.07.30-***.**`.
/// Separators are ignored; anything not eleven digits comes back unchanged.
String formatBelgianNationalNumber(String number, {bool masked = false}) {
  final digits = number.replaceAll(_separators, '');
  if (!_elevenDigits.hasMatch(digits)) return number;
  final sequence = masked ? '***' : digits.substring(6, 9);
  final check = masked ? '**' : digits.substring(9);
  return '${digits.substring(0, 2)}.${digits.substring(2, 4)}.'
      '${digits.substring(4, 6)}-$sequence.$check';
}
