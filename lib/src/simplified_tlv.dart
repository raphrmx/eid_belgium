import 'dart:typed_data';

/// Splits a file in the card's simplified TLV format into its fields, by tag.
/// Throws a [FormatException] when a length runs past the end of the file.
Map<int, Uint8List> parseSimplifiedTlv(Uint8List file) {
  final fields = <int, Uint8List>{};
  var index = 0;
  while (index < file.length) {
    final tag = file[index++];
    // Tag 0 only ever comes first; a later zero byte is padding.
    if (tag == 0 && fields.isNotEmpty) break;

    var length = 0;
    int byte;
    do {
      if (index == file.length) {
        throw FormatException('Field $tag has no length', file, index);
      }
      byte = file[index++];
      length += byte;
    } while (byte == 0xFF);

    if (index + length > file.length) {
      throw FormatException(
        'Field $tag runs past the end of the file',
        file,
        index,
      );
    }
    fields[tag] = Uint8List.sublistView(file, index, index + length);
    index += length;
  }
  return Map.unmodifiable(fields);
}
