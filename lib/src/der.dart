import 'dart:typed_data';

/// The DER value at the start of [file] without its zero padding, or null
/// when the file is only padding (a certificate never issued). Throws a
/// [FormatException] if the value runs past the end of [file].
Uint8List? trimDer(Uint8List file) =>
    file.isEmpty || file[0] == 0 ? null : DerElement.parse(file).encoded;

/// The size of the DER value whose first bytes are [start], header included.
/// Throws a [FormatException] if [start] does not begin one.
int derSize(List<int> start) {
  if (start.length < 2) throw const FormatException('Truncated DER header');
  final first = start[1];
  if (first < 0x80) return 2 + first;
  final count = first & 0x7F;
  if (count == 0 || count > 3 || start.length < 2 + count) {
    throw const FormatException('Unsupported DER length');
  }
  var length = 0;
  for (var i = 0; i < count; i++) {
    length = length << 8 | start[2 + i];
  }
  return 2 + count + length;
}

/// One DER encoded element: its tag, and where its content lies.
final class DerElement {
  DerElement._(this._bytes, this.tag, this._start, this._content, this._end);

  /// Reads the element at [offset]. Throws a [FormatException] if invalid.
  factory DerElement.parse(Uint8List bytes, [int offset = 0]) {
    if (offset + 2 > bytes.length) {
      throw FormatException('Truncated DER element', bytes, offset);
    }
    final tag = bytes[offset];
    final first = bytes[offset + 1];
    var content = offset + 2;
    var length = first;
    if (first >= 0x80) {
      final count = first & 0x7F;
      if (count == 0 || count > 3 || content + count > bytes.length) {
        throw FormatException('Unsupported DER length', bytes, offset + 1);
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = length << 8 | bytes[content + i];
      }
      content += count;
    }
    final end = content + length;
    if (end > bytes.length) {
      throw FormatException('DER element runs past the end', bytes, offset);
    }
    return DerElement._(bytes, tag, offset, content, end);
  }

  final Uint8List _bytes;
  final int _start;
  final int _content;
  final int _end;

  /// The tag byte, such as `0x30` for a SEQUENCE.
  final int tag;

  /// The element as encoded, header included.
  Uint8List get encoded => Uint8List.sublistView(_bytes, _start, _end);

  /// The content, header excluded.
  Uint8List get content => Uint8List.sublistView(_bytes, _content, _end);

  /// The elements a constructed element such as a SEQUENCE holds.
  List<DerElement> get children {
    final children = <DerElement>[];
    var offset = _content;
    while (offset < _end) {
      final child =
          DerElement.parse(Uint8List.sublistView(_bytes, 0, _end), offset);
      children.add(child);
      offset = child._end;
    }
    return children;
  }

  /// The content of an INTEGER, as a non-negative number.
  BigInt get integer {
    _expect(0x02, 'INTEGER');
    var value = BigInt.zero;
    for (final byte in content) {
      value = value << 8 | BigInt.from(byte);
    }
    return value;
  }

  /// The content of an OBJECT IDENTIFIER, dotted: `1.3.132.0.34`.
  String get objectIdentifier {
    _expect(0x06, 'OBJECT IDENTIFIER');
    final bytes = content;
    if (bytes.isEmpty) throw const FormatException('Empty OBJECT IDENTIFIER');
    final parts = <int>[bytes[0] ~/ 40, bytes[0] % 40];
    var value = 0;
    for (final byte in bytes.skip(1)) {
      value = value << 7 | byte & 0x7F;
      if (byte < 0x80) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  /// The bits of a BIT STRING that has no unused bits.
  Uint8List get bitString {
    _expect(0x03, 'BIT STRING');
    final bytes = content;
    if (bytes.isEmpty || bytes[0] != 0) {
      throw const FormatException('Unsupported BIT STRING');
    }
    return Uint8List.sublistView(bytes, 1);
  }

  void _expect(int expected, String name) {
    if (tag != expected) throw FormatException('Expected an $name', tag);
  }
}

/// Encodes an element of [tag] holding [content].
Uint8List derEncode(int tag, List<int> content) {
  final length = content.length;
  final List<int> header;
  if (length < 0x80) {
    header = [tag, length];
  } else if (length < 0x100) {
    header = [tag, 0x81, length];
  } else {
    header = [tag, 0x82, length >> 8, length & 0xFF];
  }
  return Uint8List.fromList([...header, ...content]);
}

/// Encodes a SEQUENCE of already encoded [elements].
Uint8List derSequence(List<List<int>> elements) =>
    derEncode(0x30, [for (final element in elements) ...element]);

/// Encodes a non-negative INTEGER.
Uint8List derInteger(BigInt value) {
  final bytes = <int>[];
  var rest = value;
  do {
    bytes.insert(0, (rest & BigInt.from(0xFF)).toInt());
    rest >>= 8;
  } while (rest > BigInt.zero);
  // A leading bit set would make the number negative.
  if (bytes.first >= 0x80) bytes.insert(0, 0);
  return derEncode(0x02, bytes);
}

/// Encodes a dotted OBJECT IDENTIFIER.
Uint8List derObjectIdentifier(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final bytes = [parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final groups = <int>[part & 0x7F];
    var rest = part >> 7;
    while (rest > 0) {
      groups.insert(0, rest & 0x7F | 0x80);
      rest >>= 7;
    }
    bytes.addAll(groups);
  }
  return derEncode(0x06, bytes);
}

/// Encodes a BIT STRING with no unused bits.
Uint8List derBitString(List<int> bits) => derEncode(0x03, [0, ...bits]);
