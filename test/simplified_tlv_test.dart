import 'dart:typed_data';

import 'package:eid_belgium/src/simplified_tlv.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('splits fields by tag', () {
    final fields = parseSimplifiedTlv(tlv({
      0x00: [0, 2],
      0x01: 'ab',
      0x02: ''
    }));
    expect(fields.keys, [0x00, 0x01, 0x02]);
    expect(fields[0x01], 'ab'.codeUnits);
    expect(fields[0x02], isEmpty);
  });

  test('reads lengths of 255 and more as a run of FF', () {
    for (final length in [254, 255, 256, 509, 510, 600]) {
      final fields = parseSimplifiedTlv(tlv({0x01: List.filled(length, 7)}));
      expect(fields[0x01], hasLength(length), reason: 'length $length');
    }
    // FF 00 is 255, not a one byte 255.
    expect(tlv({0x01: List.filled(255, 7)}).sublist(0, 3), [0x01, 0xFF, 0x00]);
  });

  test('stops at the zero padding after the data', () {
    final fields = parseSimplifiedTlv(tlv({
      0x00: [0, 2],
      0x01: 'ab'
    }, padding: 20));
    expect(fields.keys, [0x00, 0x01]);
  });

  test('refuses a field that runs past the end', () {
    expect(
      () => parseSimplifiedTlv(Uint8List.fromList([0x01, 0x05, 0x61])),
      throwsFormatException,
    );
    expect(
      () => parseSimplifiedTlv(Uint8List.fromList([0x01, 0xFF])),
      throwsFormatException,
    );
  });
}
