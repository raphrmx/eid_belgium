import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid/eid.dart';

/// Writes [fields] in the card's simplified TLV format, followed by
/// [padding] zero bytes.
Uint8List tlv(Map<int, Object> fields, {int padding = 0}) {
  final out = BytesBuilder();
  fields.forEach((tag, value) {
    final bytes = value is String ? utf8.encode(value) : value as List<int>;
    out.addByte(tag);
    var length = bytes.length;
    while (length >= 255) {
      out.addByte(0xFF);
      length -= 255;
    }
    out
      ..addByte(length)
      ..add(bytes);
  });
  out.add(Uint8List(padding));
  return out.takeBytes();
}

/// A stand-in for a photo: the card holds a JPEG, but only its hash matters
/// to the tests.
final photo = Uint8List.fromList(List.generate(3000, (i) => (i * 7) & 0xFF));

/// The identity file of an imaginary Belgian citizen on an applet 1.8 card.
Uint8List identityFile({
  String birthDate = '30 JUIL 1985',
  List<int>? photoHash,
  Map<int, Object> extra = const {},
}) =>
    tlv({
      0x00: [0x00, 0x02],
      0x01: '592123456789',
      0x02: List.generate(16, (i) => i),
      0x03: '14.03.2022',
      0x04: '14.03.2032',
      0x05: 'Bruxelles',
      0x06: '85073003328',
      0x07: 'Dupont',
      0x08: 'Marie Élise',
      0x09: 'J',
      0x0A: 'Belge',
      0x0B: 'Namur',
      0x0C: birthDate,
      0x0D: 'F',
      0x0E: '',
      0x0F: '1',
      0x10: '0',
      0x11: photoHash ?? sha384.convert(photo).bytes,
      0x12: '',
      0x1A: List.filled(48, 0xAB),
      ...extra,
    }, padding: 6);

/// The address file matching [identityFile].
Uint8List addressFile() => tlv({
      0x00: [0x00, 0x02],
      0x01: 'Rue de la Loi 16',
      0x02: '1000',
      0x03: 'Bruxelles',
    }, padding: 40);

/// A DER certificate stand-in of [length] content bytes, padded with zeros
/// the way the card pads its certificate files.
Uint8List certificateFile(int length) => Uint8List.fromList([
      0x30,
      0x82,
      length >> 8,
      length & 0xFF,
      ...List.filled(length, 0x5A),
      ...List.filled(1100, 0),
    ]);

/// A Belpic card behind a USB reader: a file system answering SELECT FILE by
/// identifier and READ BINARY the way a T=0 card does.
final class FakeBelpicCard implements CardTransport {
  FakeBelpicCard(this.files, {this.otherAppletSelected = false});

  /// The files by path, such as `3F00DF014031`.
  final Map<String, Uint8List> files;

  /// Whether some other software left another application selected, so that
  /// the file system only answers once the Belpic applet is selected again.
  bool otherAppletSelected;

  final List<String> sent = [];
  String _path = '';
  Uint8List? _selected;

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    sent.add(hexString(command));
    final ins = command[1];
    if (ins == 0xA4 && command[2] == 0x04) {
      otherAppletSelected = false;
      _path = '';
      return _sw(0x9000);
    }
    if (otherAppletSelected) return _sw(0x6A82);
    if (ins == 0xA4) return _select(hexString(command.sublist(5, 7)));
    if (ins == 0xB0) return _read(command);
    if (ins == 0x20) return _verify(command.sublist(5));
    if (ins == 0xE4) {
      return Uint8List.fromList([
        ...List.generate(16, (i) => 0x50 + i),
        0x01, 0x02, 0x03, 0x04, 0x05, 0x18, 0x00, 0x01, //
        0x01, 0x00, 0x02, 0x0F, 0x90, 0x00,
      ]);
    }
    return _sw(0x6D00);
  }

  Uint8List _select(String fileId) {
    if (fileId == '3F00') {
      _path = '3F00';
      _selected = null;
      return _sw(0x9000);
    }
    final candidate = '$_path$fileId';
    final file = files[candidate];
    final isDirectory = files.keys.any((path) => path.startsWith(candidate));
    if (file == null && !isDirectory) return _sw(0x6A82);
    _path = file == null ? candidate : _path;
    _selected = file;
    return _sw(0x9000);
  }

  /// The PIN block of 1234.
  static const pin = '241234FFFFFFFFFF';
  int pinTries = 3;

  Uint8List _verify(Uint8List block) {
    if (pinTries == 0) return _sw(0x6983);
    if (hexString(block) == pin) {
      pinTries = 3;
      return _sw(0x9000);
    }
    pinTries--;
    return _sw(0x63C0 | pinTries);
  }

  Uint8List _read(Uint8List command) {
    final file = _selected;
    if (file == null) return _sw(0x6986);
    final offset = command[2] << 8 | command[3];
    final le = command[4] == 0 ? 256 : command[4];
    if (offset >= file.length) return _sw(0x6B00);
    final left = file.length - offset;
    if (le > left) return Uint8List.fromList([0x6C, left]);
    return Uint8List.fromList([...file.sublist(offset, offset + le), 0x90, 0]);
  }

  static Uint8List _sw(int statusWord) =>
      Uint8List.fromList([statusWord >> 8, statusWord & 0xFF]);
}

/// A card holding [identityFile], [addressFile], [photo] and a few
/// certificates.
FakeBelpicCard fakeCard({bool otherAppletSelected = false}) => FakeBelpicCard(
      {
        '3F00DF014031': identityFile(),
        '3F00DF014032': Uint8List.fromList([0x30, 0x02, 0x01, 0x02]),
        '3F00DF014033': addressFile(),
        '3F00DF014034': Uint8List.fromList([0x30, 0x02, 0x03, 0x04, 0, 0]),
        '3F00DF014035': photo,
        '3F00DF00503C': certificateFile(900),
        '3F00DF005038': Uint8List(2500),
      },
      otherAppletSelected: otherAppletSelected,
    );
