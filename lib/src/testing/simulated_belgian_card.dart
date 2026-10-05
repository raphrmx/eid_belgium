import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_document_type.dart';
import 'package:eid_belgium/src/belgian_eid_reader.dart';
import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/pin.dart';
import 'package:eid_belgium/src/simulated_transport.dart';
import 'package:eid_belgium/src/testing/simulated_pki.dart';
import 'package:eid_belgium/src/testing/specimen_photo.dart';

/// A Belgian eID in memory that answers the commands of a real card, to test
/// without a card reader. Pass it wherever a [CardTransport] goes:
///
/// ```dart
/// final card = SimulatedBelgianCard(lastName: 'Peeters', pin: '4321');
/// final eid = await BelgianEidReader(card).read();
/// ```
///
/// Its signatures check only against [rootCertificate], not the Belgian
/// roots.
final class SimulatedBelgianCard
    implements CardTransport, CardTerminal, SimulatedTransport {
  /// A card holding the given data, by default that of a fictional citizen.
  ///
  /// [birthDate] is written as on the card, such as `15 MAI 1990`, and [sex]
  /// as `M` or `F`. [extraIdentityFields] adds or replaces identity fields by
  /// tag. An [appletVersion] below `0x18` gives an older card. [latency]
  /// delays every answer.
  ///
  /// [tamperedLastName] is written after signing, so the signature fails. A
  /// [cloned] card fails `BelgianEidReader.proveGenuine`. [holderCertificates]
  /// false leaves out the holder's certificates, as on a Kids ID.
  SimulatedBelgianCard({
    String cardNumber = '591000000106',
    DateTime? validFrom,
    DateTime? validUntil,
    String issuingMunicipality = 'Bruxelles',
    String nationalNumber = '90051512391',
    String lastName = 'Specimen',
    String firstNames = 'Alice Marie',
    String? thirdGivenNameInitial = 'J',
    String nationality = 'Belge',
    String birthPlace = 'Namur',
    String birthDate = '15 MAI 1990',
    String sex = 'F',
    BelgianDocumentType documentType = BelgianDocumentType.eid,
    String streetAndNumber = 'Rue de la Loi 16',
    String postalCode = '1000',
    String municipality = 'Bruxelles',
    Uint8List? photo,
    Map<int, Object> extraIdentityFields = const {},
    String pin = '1234',
    this.appletVersion = 0x18,
    this.latency = Duration.zero,
    String? tamperedLastName,
    bool cloned = false,
    bool holderCertificates = true,
  })  : _pinBlock = pinBlock(pin),
        _basicKey = cloned
            ? SimulatedPki.instance.cloneKey
            : SimulatedPki.instance.basicKey {
    final cardPhoto = photo ?? specimenPhoto;
    final basicPublicKey = SimulatedPki.instance.basicPublicKeyFile;
    final pki = SimulatedPki.instance;
    Uint8List identityWith(String lastName) => _tlv({
          0x00: const [0x00, 0x02],
          0x01: cardNumber,
          0x02: serialNumber,
          0x03: _dotted(validFrom ?? DateTime.utc(2024, 3, 14)),
          0x04: _dotted(validUntil ?? DateTime.utc(2034, 3, 13)),
          0x05: issuingMunicipality,
          0x06: nationalNumber,
          0x07: lastName,
          0x08: firstNames,
          0x09: thirdGivenNameInitial ?? '',
          0x0A: nationality,
          0x0B: birthPlace,
          0x0C: birthDate,
          0x0D: sex,
          0x0E: '',
          0x0F: '${documentType.code}',
          0x10: '0',
          0x11: _photoHash(cardPhoto),
          if (appletVersion >= 0x18) 0x1A: sha384.convert(basicPublicKey).bytes,
          ...extraIdentityFields,
        });
    final address = _tlv({
      0x00: const [0x00, 0x02],
      0x01: streetAndNumber,
      0x02: postalCode,
      0x03: municipality,
    });
    // Signing is asynchronous on the web: the first command waits for it.
    _files = _sign(
      identity: identityWith(tamperedLastName ?? lastName),
      signedIdentity: identityWith(lastName),
      address: address,
      photo: cardPhoto,
      basicPublicKey: basicPublicKey,
      holderCertificates: holderCertificates
          ? pki.holderCertificates(
              lastName: lastName,
              firstNames: firstNames,
              nationalNumber: nationalNumber,
            )
          : null,
    );
    // A failure surfaces on the first command, not as an unhandled error.
    _files.ignore();
  }

  static Future<Map<int, Uint8List>> _sign({
    required Uint8List identity,
    required Uint8List signedIdentity,
    required Uint8List address,
    required Uint8List photo,
    required Uint8List basicPublicKey,
    required Future<(Uint8List, Uint8List)>? holderCertificates,
  }) async {
    final pki = SimulatedPki.instance;
    // The file is signed as the card holds it, padding included.
    Uint8List padded(Uint8List content, int padding) =>
        Uint8List.fromList([...content, ...List.filled(padding, 0)]);
    final identitySignature = _fixedLength(
      await pki.sign(padded(signedIdentity, 48)),
      256,
    );
    // Signed: the address without padding, then the identity signature file.
    final addressSignature = _fixedLength(
      await pki.sign([...address, ...identitySignature]),
      256,
    );
    final holders = await holderCertificates;

    return {
      _key(0xDF01, 0x4031): padded(identity, 48),
      _key(0xDF01, 0x4032): identitySignature,
      _key(0xDF01, 0x4033): padded(address, 40),
      _key(0xDF01, 0x4034): addressSignature,
      _key(0xDF01, 0x4035): photo,
      _key(0xDF01, 0x4040): basicPublicKey,
      if (holders != null) ...{
        _key(0xDF00, 0x5038): padded(holders.$1, 1100),
        _key(0xDF00, 0x5039): padded(holders.$2, 1100),
        _key(0xDF00, 0x503A): padded(pki.caCertificate, 1100),
      } else
        for (final fileId in [0x5038, 0x5039, 0x503A])
          _key(0xDF00, fileId): Uint8List(2500),
      _key(0xDF00, 0x503B): padded(pki.rootCertificate, 1100),
      _key(0xDF00, 0x503C): padded(pki.registerCertificate, 1100),
    };
  }

  /// The chip serial number GET CARD DATA and the identity file carry.
  static final serialNumber = Uint8List.fromList([
    0x53, 0x4C, 0x49, 0x4E, 0x33, 0x66, 0x00, 0x29, //
    0x6C, 0xFF, 0x26, 0x23, 0x66, 0x0B, 0x08, 0x26,
  ]);

  /// The DER root that signs every simulated card. A reader trusts it for
  /// the simulated card alone, never for a real one.
  static Uint8List get rootCertificate => SimulatedPki.instance.rootCertificate;

  /// The same as [rootCertificate]: a reader trusts it for this card alone.
  @override
  Uint8List get simulatedRoot => rootCertificate;

  /// The applet version GET CARD DATA reports.
  final int appletVersion;

  /// How long each answer takes.
  final Duration latency;

  Uint8List _pinBlock;
  final BigInt _basicKey;
  late final Future<Map<int, Uint8List>> _files;
  Map<int, Uint8List> _loaded = const {};

  bool _inserted = true;
  int _insertions = 0;
  int _directory = 0x3F00;
  Uint8List? _selected;
  int _pinTries = 3;
  bool _pinVerified = false;

  /// Whether the card is in the reader. If not, [transmit] throws a
  /// [CardTransportException].
  bool get isInserted => _inserted;

  /// The PIN tries left before the card blocks.
  int get pinTriesLeft => _pinTries;

  /// Whether the PIN was verified since the card was inserted.
  bool get isPinVerified => _pinVerified;

  /// The simulated reader's name.
  @override
  String get name => 'Simulated Belgian eID';

  /// Connects to the card, for a `CardWatcher` or a `BelgianEidWatcher`.
  @override
  Future<CardConnection> connect() async {
    if (!_inserted) {
      throw const CardTransportException('No card in the simulated reader');
    }
    return _SimulatedConnection(this, _insertions);
  }

  /// Pulls the card out of the reader.
  void remove() => _inserted = false;

  /// Puts the card back, which resets it but keeps the PIN tries counter.
  void insert() {
    _inserted = true;
    _insertions++;
    _directory = 0x3F00;
    _selected = null;
    _pinVerified = false;
  }

  @override
  Future<Uint8List> transmit(Uint8List command) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (!_inserted) {
      throw const CardTransportException('No card in the simulated reader');
    }
    if (command.length < 4) return _status(0x6700);
    _loaded = await _files;
    if (!_inserted) {
      throw const CardTransportException('No card in the simulated reader');
    }

    final cla = command[0];
    final ins = command[1];
    final p2 = command[3];
    final data = command.length > 5
        ? Uint8List.sublistView(command, 5, 5 + command[4])
        : Uint8List(0);

    if (cla == 0x80 && ins == 0xE4) return _cardData(command, p2);
    if (cla != 0x00) return _status(0x6E00);
    return switch (ins) {
      0xA4 => _select(command[2], data),
      0xB0 => _readBinary(command),
      0x20 => _verify(data),
      0x24 => _changePin(command[2], command[3], data),
      0x88 => _internalAuthenticate(command[2], command[3], data),
      _ => _status(0x6D00),
    };
  }

  Uint8List _select(int p1, Uint8List data) {
    switch (p1) {
      case 0x04:
        if (!sameBytes(data, BelgianEidReader.appletAid)) {
          return _status(0x6A82);
        }
        _directory = 0x3F00;
        _selected = null;
        return _status(0x9000);
      case 0x02 when data.length == 2:
        return _selectFileId(data[0] << 8 | data[1]);
      case 0x08 when data.length.isEven && data.isNotEmpty:
        _directory = 0x3F00;
        for (var i = 0; i < data.length; i += 2) {
          final response = _selectFileId(data[i] << 8 | data[i + 1]);
          if (response[0] != 0x90) return response;
        }
        return _status(0x9000);
      default:
        return _status(0x6A86);
    }
  }

  Uint8List _selectFileId(int fileId) {
    if (fileId == 0x3F00 || fileId == 0xDF00 || fileId == 0xDF01) {
      _directory = fileId;
      _selected = null;
      return _status(0x9000);
    }
    final file = _loaded[_key(_directory, fileId)];
    if (file == null) return _status(0x6A82);
    _selected = file;
    return _status(0x9000);
  }

  Uint8List _readBinary(Uint8List command) {
    final file = _selected;
    if (file == null) return _status(0x6986);
    final offset = command[2] << 8 | command[3];
    final length = command.length < 5 || command[4] == 0 ? 256 : command[4];
    if (offset >= file.length) return _status(0x6B00);
    final left = file.length - offset;
    if (length > left) return _status(0x6C00 | (left & 0xFF));
    return Uint8List.fromList([
      ...file.sublist(offset, offset + length),
      0x90,
      0x00,
    ]);
  }

  Uint8List _verify(Uint8List block) {
    if (_pinTries == 0) return _status(0x6983);
    // An empty VERIFY asks for the state without spending a try.
    if (block.isEmpty) {
      return _status(_pinVerified ? 0x9000 : 0x63C0 | _pinTries);
    }
    if (sameBytes(block, _pinBlock)) {
      _pinTries = 3;
      _pinVerified = true;
      return _status(0x9000);
    }
    _pinTries--;
    _pinVerified = false;
    return _status(0x63C0 | _pinTries);
  }

  Uint8List _changePin(int p1, int p2, Uint8List data) {
    if (p1 != 0x00 || p2 != 0x01) return _status(0x6A86);
    if (data.length != 16) return _status(0x6700);
    if (_pinTries == 0) return _status(0x6983);
    final replacement = Uint8List.fromList(data.sublist(8));
    if (replacement[0] >> 4 != 2) return _status(0x6A80);
    if (!sameBytes(data.sublist(0, 8), _pinBlock)) {
      _pinTries--;
      _pinVerified = false;
      return _status(0x63C0 | _pinTries);
    }
    _pinBlock = replacement;
    _pinTries = 3;
    return _status(0x9000);
  }

  // Applet 1.8 and later only; signs the 48 bytes as given, unhashed.
  Uint8List _internalAuthenticate(int p1, int p2, Uint8List data) {
    if (appletVersion < 0x18 || p1 != 0x02 || p2 != 0x81) {
      return _status(0x6A86);
    }
    if (data.length != 50 || data[0] != 0x94 || data[1] != 0x30) {
      return _status(0x6A80);
    }
    final signature = SimulatedPki.instance.signDigest(
      _basicKey,
      data.sublist(2),
    );
    return Uint8List.fromList([...signature, 0x90, 0x00]);
  }

  Uint8List _cardData(Uint8List command, int p2) {
    final data = [
      ...serialNumber,
      0x01, 0x02, 0x03, 0x04, 0x05, appletVersion, 0x00, 0x01, //
      0x01, 0x00, 0x02, 0x0F,
      if (p2 == 0x01) ...[_pinTries, 0xFF, 0xFF],
    ];
    final expected = command.length < 5 || command[4] == 0 ? 256 : command[4];
    if (expected != data.length) return _status(0x6C00 | data.length);
    return Uint8List.fromList([...data, 0x90, 0x00]);
  }

  List<int> _photoHash(Uint8List photo) => appletVersion >= 0x18
      ? sha384.convert(photo).bytes
      : sha1.convert(photo).bytes;

  static Uint8List _fixedLength(Uint8List signature, int length) =>
      Uint8List(length)..setRange(0, signature.length, signature);

  static Uint8List _tlv(Map<int, Object> fields) {
    final out = BytesBuilder(copy: false);
    fields.forEach((tag, value) {
      final bytes = value is String ? utf8.encode(value) : value as List<int>;
      out.addByte(tag);
      var length = bytes.length;
      while (length >= 0xFF) {
        out.addByte(0xFF);
        length -= 0xFF;
      }
      out
        ..addByte(length)
        ..add(bytes);
    });
    return out.takeBytes();
  }

  static String _dotted(DateTime date) =>
      '${_two(date.day)}.${_two(date.month)}.${date.year}';

  static String _two(int value) => value.toString().padLeft(2, '0');

  static int _key(int directory, int fileId) => directory << 16 | fileId;

  static Uint8List _status(int statusWord) =>
      Uint8List.fromList([statusWord >> 8, statusWord & 0xFF]);
}

final class _SimulatedConnection implements CardConnection, SimulatedTransport {
  _SimulatedConnection(this.card, this._insertion);

  final SimulatedBelgianCard card;

  // The insertion this connection reaches; it dies with it, as on a reader.
  final int _insertion;
  bool _released = false;

  @override
  Uint8List get simulatedRoot => card.simulatedRoot;

  @override
  Future<Uint8List> transmit(Uint8List command) {
    if (_released || card._insertions != _insertion) {
      return Future.error(
        const CardTransportException('The card was removed'),
      );
    }
    return card.transmit(command);
  }

  @override
  Future<void> disconnect() async => _released = true;
}
