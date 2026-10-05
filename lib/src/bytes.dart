import 'dart:typed_data';

/// Whether [a] and [b] hold the same bytes.
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// [bytes] read as an unsigned big-endian number.
BigInt unsignedBigInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, byte) => value << 8 | BigInt.from(byte));

final _byte = BigInt.from(0xFF);

/// [value] as [length] unsigned big-endian bytes.
Uint8List bigIntBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var rest = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (rest & _byte).toInt();
    rest >>= 8;
  }
  return bytes;
}
