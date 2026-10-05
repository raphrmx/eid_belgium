import 'dart:typed_data';

/// The card refused the PIN.
final class PinException implements Exception {
  /// A refusal leaving [triesLeft] attempts before the PIN blocks.
  const PinException(this.triesLeft);

  /// How many attempts remain before the PIN blocks; 0 once it has.
  final int triesLeft;

  /// Whether the PIN is blocked, which only the municipality can undo.
  bool get isBlocked => triesLeft == 0;

  @override
  String toString() => isBlocked
      ? 'PinException: the PIN is blocked'
      : 'PinException: wrong PIN, $triesLeft tries left';
}

/// The PIN was asked for and not given.
final class PinCancelledException implements Exception {
  /// The holder gave up.
  const PinCancelledException();

  @override
  String toString() => 'PinCancelledException: no PIN was given';
}

final _pinDigits = RegExp(r'^\d{4,12}$');

/// Whether [pin] is 4 to 12 digits, the only PINs a card takes.
bool isWellFormedPin(String pin) => _pinDigits.hasMatch(pin);

/// The 8 byte PIN block the card expects for [pin].
/// Throws an [ArgumentError] unless [pin] is 4 to 12 digits.
Uint8List pinBlock(String pin) {
  if (!_pinDigits.hasMatch(pin)) {
    throw ArgumentError.value('****', 'pin', 'A PIN is 4 to 12 digits');
  }
  final nibbles = [
    2,
    pin.length,
    for (final unit in pin.codeUnits) unit - 0x30,
    ...List.filled(14 - pin.length, 0xF),
  ];
  return Uint8List.fromList([
    for (var i = 0; i < 16; i += 2) nibbles[i] << 4 | nibbles[i + 1],
  ]);
}
