final _twelveDigits = RegExp(r'^\d{12}$');

/// Writes an eID or Kids ID card number as printed: `591-0000001-06`.
/// Anything that is not twelve digits comes back unchanged.
String formatBelgianCardNumber(String number) => _twelveDigits.hasMatch(number)
    ? '${number.substring(0, 3)}-${number.substring(3, 10)}-'
        '${number.substring(10)}'
    : number;
