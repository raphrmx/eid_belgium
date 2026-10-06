import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_address.dart';
import 'package:eid_belgium/src/belgian_card_authenticity.dart';
import 'package:eid_belgium/src/belgian_card_info.dart';
import 'package:eid_belgium/src/belgian_card_rejected.dart';
import 'package:eid_belgium/src/belgian_certificates.dart';
import 'package:eid_belgium/src/belgian_document_type.dart';
import 'package:eid_belgium/src/belgian_eid_file.dart';
import 'package:eid_belgium/src/belgian_eid_part.dart';
import 'package:eid_belgium/src/belgian_identity.dart';
import 'package:eid_belgium/src/belgian_photo_cache.dart';
import 'package:eid_belgium/src/belgian_signature_verifier.dart';
import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';
import 'package:eid_belgium/src/ecdsa.dart';
import 'package:eid_belgium/src/pin.dart';
import 'package:eid_belgium/src/simulated_transport.dart';

/// Reports the share of a read done so far, from 0 to 1.
typedef BelgianReadProgress = void Function(double fraction);

/// Reads a Belgian eID, Kids ID or residence card through its contact chip.
///
/// Reading needs no PIN. Overlapping calls are run one at a time.
final class BelgianEidReader {
  /// A reader over [transport], reporting each command and answer to
  /// [onApdu]. The PIN is never reported, nor the national number when a
  /// read leaves it out.
  BelgianEidReader(CardTransport transport, {ApduListener? onApdu})
      : _listener = onApdu {
    channel = CardChannel(transport, onApdu: onApdu == null ? null : _report);
  }

  /// A reader over an existing [channel].
  BelgianEidReader.overChannel(this.channel) : _listener = null;

  /// The AID of the Belpic applet.
  static const appletAid = [
    0xA0, 0x00, 0x00, 0x00, 0x30, 0x29, 0x05, 0x70, //
    0x00, 0xAD, 0x13, 0x10, 0x01, 0x01, 0xFF,
  ];

  /// The channel the commands go through.
  late final CardChannel channel;

  final ApduListener? _listener;

  // While true, answers reach the listener with their data zeroed.
  bool _hideData = false;

  Future<void> _last = Future.value();

  void _report(ApduExchange exchange) {
    final response = exchange.response;
    if (!_hideData || response == null || response.length <= 2) {
      _listener?.call(exchange);
      return;
    }
    _listener?.call(
      ApduExchange(
        command: exchange.command,
        response: Uint8List(response.length)
          ..setRange(response.length - 2, response.length,
              response.sublist(response.length - 2)),
        time: exchange.time,
        duration: exchange.duration,
      ),
    );
  }

  /// Reads the identity file, then the [parts] asked for (all by default).
  ///
  /// Every check is on by default. Throws a [BelgianCardRejectedException]
  /// when the card is expired and not [acceptExpired], when its type is not
  /// in [acceptedTypes], when [verifySignatures] fails against the Belgian
  /// roots or [trustedRoots], or when [verifyCard] finds it not genuine.
  ///
  /// [verifyCard] needs [verifySignatures]: without it, it is skipped. Cards
  /// too old for it are read, [BelgianEid.authenticity] saying so. Each
  /// proof uses one of the 5000 the chip allows before it wants the PIN.
  ///
  /// The national register number needs both
  /// [BelgianEidPart.nationalNumber] in [parts] and [showPrivateData], which
  /// is off by default so that it never comes back unless asked for twice:
  /// Belgian law restricts its use to those it authorises, and most uses do
  /// not need it. Without it, it is removed from the identity file once
  /// read, the signatures are checked but not returned, since they would
  /// give it away, and `onApdu` gets the answers that hold it with their
  /// data zeroed.
  ///
  /// [photoCache] spares reading a photo already read. [onProgress] is an
  /// estimate that only grows and ends on 1.
  ///
  /// ```dart
  /// // A valid eID: its identity and address, nothing else.
  /// final eid = await reader.read(
  ///   parts: {BelgianEidPart.address},
  ///   acceptedTypes: {BelgianDocumentType.eid},
  /// );
  /// ```
  Future<BelgianEid> read({
    Set<BelgianEidPart> parts = BelgianEidPart.all,
    bool acceptExpired = false,
    Set<BelgianDocumentType>? acceptedTypes,
    BelgianPhotoCache? photoCache,
    bool verifySignatures = true,
    List<Uint8List>? trustedRoots,
    bool verifyCard = true,
    bool showPrivateData = false,
    BelgianReadProgress? onProgress,
  }) =>
      _exclusive(() async {
        final withNationalNumber =
            showPrivateData && parts.contains(BelgianEidPart.nationalNumber);
        final signatures =
            verifySignatures || parts.contains(BelgianEidPart.signatures);
        final withAddress = parts.contains(BelgianEidPart.address);
        final proveGenuine = verifyCard && verifySignatures;
        final progress = _Progress(onProgress, [
          BelgianEidFile.identity,
          if (signatures) BelgianEidFile.identitySignature,
          if (withAddress) BelgianEidFile.address,
          if (signatures && withAddress) BelgianEidFile.addressSignature,
          if (parts.contains(BelgianEidPart.photo)) BelgianEidFile.photo,
          if (signatures) BelgianEidFile.nationalRegisterCertificate,
          if (proveGenuine) BelgianEidFile.basicPublicKey,
        ]);
        // Without the national number, onApdu gets neither the identity file
        // nor the signatures that would give the number away.
        Future<Uint8List> read(BelgianEidFile file) async {
          _hideData = !withNationalNumber && _givesNumberAway.contains(file);
          try {
            return await _readFile(file, progress: progress);
          } finally {
            _hideData = false;
          }
        }

        final identityFile = await read(BelgianEidFile.identity);
        try {
          final identity = BelgianIdentity.parse(
            identityFile,
            withNationalNumber: withNationalNumber,
          );

          final type = identity.documentType;
          if (acceptedTypes != null &&
              (type == null || !acceptedTypes.contains(type))) {
            throw BelgianCardRejectedException(
              BelgianCardRejection.documentType,
              identity,
            );
          }
          if (!acceptExpired && identity.isExpired) {
            throw BelgianCardRejectedException(
              BelgianCardRejection.expired,
              identity,
            );
          }

          final identitySignature =
              signatures ? await read(BelgianEidFile.identitySignature) : null;
          final address = withAddress
              ? BelgianAddress.parse(await read(BelgianEidFile.address))
              : null;
          final addressSignature = signatures && address != null
              ? await read(BelgianEidFile.addressSignature)
              : null;
          Uint8List? photo;
          if (parts.contains(BelgianEidPart.photo)) {
            photo = photoCache?.lookup(identity);
            if (photo == null) {
              photo = await read(BelgianEidFile.photo);
              photoCache?.store(identity, photo);
            } else {
              progress.skip(BelgianEidFile.photo);
            }
          }
          final certificate = signatures
              ? await _readDer(
                  BelgianEidFile.nationalRegisterCertificate,
                  progress: progress,
                )
              : null;

          if (verifySignatures) {
            try {
              await _verify(
                BelgianSignatureVerifier(
                  trustedRoots: trustedRoots ??
                      switch (channel.transport) {
                        final SimulatedTransport simulated => [
                            simulated.simulatedRoot,
                          ],
                        _ => null,
                      },
                ),
                identityFile: identityFile,
                identity: identity,
                identitySignature: identitySignature!,
                address: address,
                addressSignature: addressSignature,
                photo: photo,
                certificate: certificate,
              );
            } on BelgianSignatureException catch (error) {
              throw BelgianCardRejectedException(
                BelgianCardRejection.signature,
                identity,
                cause: error,
              );
            }
          }

          final authenticity = proveGenuine
              ? await _proveGenuine(identity, progress: progress)
              : null;
          if (authenticity == BelgianCardAuthenticity.notGenuine) {
            throw BelgianCardRejectedException(
              BelgianCardRejection.notGenuine,
              identity,
            );
          }

          progress.finish();
          return BelgianEid(
            identity: identity,
            identitySignature: withNationalNumber ? identitySignature : null,
            address: address,
            addressSignature: withNationalNumber ? addressSignature : null,
            photo: photo,
            nationalRegisterCertificate: certificate,
            signaturesVerified: verifySignatures,
            authenticity: authenticity,
          );
        } finally {
          // The raw bytes still hold the national number.
          if (!withNationalNumber) {
            identityFile.fillRange(0, identityFile.length, 0);
          }
        }
      });

  static Future<void> _verify(
    BelgianSignatureVerifier verifier, {
    required Uint8List identityFile,
    required BelgianIdentity identity,
    required Uint8List identitySignature,
    required BelgianAddress? address,
    required Uint8List? addressSignature,
    required Uint8List? photo,
    required Uint8List? certificate,
  }) async {
    if (certificate == null) {
      throw const BelgianSignatureException(
        'The card holds no national register certificate',
      );
    }
    await verifier.verifyIdentity(
      identityFile: identityFile,
      identitySignature: identitySignature,
      certificate: certificate,
    );
    if (address != null) {
      await verifier.verifyAddress(
        addressFile: address.file,
        addressSignature: addressSignature!,
        identitySignature: identitySignature,
        certificate: certificate,
      );
    }
    if (photo != null && !identity.matchesPhoto(photo)) {
      throw const BelgianSignatureException(
        'The photo does not match the hash the identity file carries',
      );
    }
  }

  static const _givesNumberAway = {
    BelgianEidFile.identity,
    BelgianEidFile.identitySignature,
    BelgianEidFile.addressSignature,
  };

  /// Reads the identity file, leaving the national number out unless both
  /// [withNationalNumber] and [showPrivateData], as [read] does.
  Future<BelgianIdentity> readIdentity({
    bool withNationalNumber = true,
    bool showPrivateData = false,
  }) =>
      _exclusive(() async {
        final withNumber = withNationalNumber && showPrivateData;
        _hideData = !withNumber;
        Uint8List? file;
        try {
          file = await _readFile(BelgianEidFile.identity);
          return BelgianIdentity.parse(
            file,
            withNationalNumber: withNumber,
          );
        } finally {
          _hideData = false;
          // The raw bytes, also held by a parse error, carry the number.
          if (!withNumber) file?.fillRange(0, file.length, 0);
        }
      });

  /// Reads the address file.
  Future<BelgianAddress> readAddress() async =>
      BelgianAddress.parse(await readFile(BelgianEidFile.address));

  /// Reads the photo, a JPEG.
  Future<Uint8List> readPhoto() => readFile(BelgianEidFile.photo);

  /// Reads the DER certificate in [file], or null when the card has none
  /// there (a young child's Kids ID, for instance).
  Future<Uint8List?> readCertificate(BelgianEidFile file) {
    if (!file.isCertificate) {
      throw ArgumentError.value(file, 'file', 'Not a certificate file');
    }
    return _exclusive(() => _readDer(file));
  }

  /// Reads every certificate on the card.
  ///
  /// The holder's certificates include the national number. Throws a
  /// [FormatException] when a certificate cannot be parsed.
  Future<BelgianCertificates> readCertificates() => _exclusive(() async {
        Future<BelgianCertificate?> certificate(BelgianEidFile file) async {
          final der = await _readDer(file);
          return der == null ? null : BelgianCertificate.parse(der);
        }

        return BelgianCertificates(
          authentication:
              await certificate(BelgianEidFile.authenticationCertificate),
          signing: await certificate(BelgianEidFile.signingCertificate),
          ca: await certificate(BelgianEidFile.caCertificate),
          root: await certificate(BelgianEidFile.rootCertificate),
          nationalRegister:
              await certificate(BelgianEidFile.nationalRegisterCertificate),
        );
      });

  /// Reads [file] as the card holds it, padding included.
  Future<Uint8List> readFile(BelgianEidFile file) =>
      _exclusive(() => _readFile(file));

  /// Checks [pin] against the card. It stays verified until removed or reset.
  ///
  /// Throws a [PinException] with the tries left when the card refuses it,
  /// or an [ArgumentError], spending no try, unless [pin] is 4 to 12 digits.
  /// Three wrong PINs in a row block the card.
  Future<void> verifyPin(String pin) {
    final block = pinBlock(pin);
    return _exclusive(() async {
      try {
        final response = await channel
            .send(CommandApdu(0x00, 0x20, 0x00, 0x01, data: block));
        _checkPin(response.statusWord, 'VERIFY');
      } finally {
        block.fillRange(0, block.length, 0);
      }
    });
  }

  /// The PIN tries left before the card blocks, 0 once blocked, without
  /// spending one.
  Future<int> pinTriesLeft() => _exclusive(() async {
        final response =
            await channel.send(CommandApdu(0x00, 0x20, 0x00, 0x01));
        try {
          _checkPin(response.statusWord, 'VERIFY');
          return 3;
        } on PinException catch (refusal) {
          return refusal.triesLeft;
        }
      });

  /// Replaces the PIN [current] with [replacement].
  ///
  /// Throws as [verifyPin] does, and an [ArgumentError] unless both PINs
  /// are 4 to 12 digits.
  Future<void> changePin(String current, String replacement) {
    final currentBlock = pinBlock(current);
    final Uint8List data;
    try {
      final replacementBlock = pinBlock(replacement);
      data = Uint8List.fromList([...currentBlock, ...replacementBlock]);
      replacementBlock.fillRange(0, replacementBlock.length, 0);
    } finally {
      currentBlock.fillRange(0, currentBlock.length, 0);
    }
    return _exclusive(() async {
      try {
        final response =
            await channel.send(CommandApdu(0x00, 0x24, 0x00, 0x01, data: data));
        _checkPin(response.statusWord, 'CHANGE REFERENCE DATA');
      } finally {
        data.fillRange(0, data.length, 0);
      }
    });
  }

  // 9000 is accepted; 63Cx and 6983 are a refused or blocked PIN.
  static void _checkPin(int status, String command) {
    if (status == 0x9000) return;
    if (status & 0xFFF0 == 0x63C0) throw PinException(status & 0x0F);
    if (status == 0x6983) throw const PinException(0);
    throw CardException(command, status);
  }

  /// Asks the chip to prove it is the card issued, not a copy of its files.
  ///
  /// The chip's key is checked against [identity], which only the national
  /// register's signature vouches for: pass one from a [read] that verified
  /// it. Cards before applet 1.8 give [BelgianCardAuthenticity.notSupported].
  /// Throws a [CardException] when the chip refuses, which it does after
  /// 5000 proofs until the PIN is verified.
  Future<BelgianCardAuthenticity> proveGenuine(BelgianIdentity identity) =>
      _exclusive(() => _proveGenuine(identity));

  Future<BelgianCardAuthenticity> _proveGenuine(
    BelgianIdentity identity, {
    _Progress? progress,
  }) async {
    final hash = identity.basicKeyHash;
    if (hash == null) {
      progress?.skip(BelgianEidFile.basicPublicKey);
      return BelgianCardAuthenticity.notSupported;
    }

    final keyFile = await _readFile(
      BelgianEidFile.basicPublicKey,
      progress: progress,
    );
    if (!sameBytes(crypto.sha384.convert(keyFile).bytes, hash)) {
      return BelgianCardAuthenticity.notGenuine;
    }

    // The chip signs the 48 bytes it gets as a SHA-384 digest: send the
    // digest of a random nonce and check the signature of the nonce.
    final random = Random.secure();
    final nonce =
        Uint8List.fromList(List.generate(48, (_) => random.nextInt(256)));
    final challenge = crypto.sha384.convert(nonce).bytes;
    final signature = await channel.expect(
      CommandApdu(0x00, 0x88, 0x02, 0x81, data: [0x94, 0x30, ...challenge]),
      'INTERNAL AUTHENTICATE',
    );
    if (signature.length != 96) return BelgianCardAuthenticity.notGenuine;
    try {
      final holds = await verifyP384(
        publicKeyInfo: trimDer(keyFile) ?? keyFile,
        data: nonce,
        hash: EcHash.sha384,
        r: unsignedBigInt(signature.sublist(0, 48)),
        s: unsignedBigInt(signature.sublist(48)),
      );
      return holds
          ? BelgianCardAuthenticity.genuine
          : BelgianCardAuthenticity.notGenuine;
    } on FormatException {
      return BelgianCardAuthenticity.notGenuine;
    }
  }

  /// Asks the card about its chip and applet.
  Future<BelgianCardInfo> readCardInfo() => _exclusive(() async {
        final data = await channel.expect(
          CommandApdu(0x80, 0xE4, 0x00, 0x00, le: BelgianCardInfo.length),
          'GET CARD DATA',
        );
        return BelgianCardInfo.parse(data);
      });

  Future<Uint8List> _readFile(
    BelgianEidFile file, {
    _Progress? progress,
  }) async {
    await _select(file);
    final content = await channel.readTransparentFile(
      onProgress:
          progress == null ? null : (bytes) => progress.reading(file, bytes),
    );
    progress?.done(file);
    return content;
  }

  static const _block = 248;

  // Reads the DER value at the start of [file], not the zero padding after
  // it. Null when the file is only padding.
  Future<Uint8List?> _readDer(
    BelgianEidFile file, {
    _Progress? progress,
  }) async {
    await _select(file);
    final first = await channel.readBinary(offset: 0, length: _block);
    if (first.isEmpty || first[0] == 0) {
      progress?.done(file);
      return null;
    }
    final size = derSize(first);
    // A certificate is a few kilobytes; READ BINARY stops at 32 KB.
    if (size > 0x2000) throw const FormatException('Certificate too large');
    final content = BytesBuilder(copy: false)
      ..add(first.length > size ? first.sublist(0, size) : first);
    while (content.length < size) {
      final offset = content.length;
      final chunk = await channel.readBinary(
        offset: offset,
        length: min(_block, size - offset),
      );
      if (chunk.isEmpty) {
        throw const FormatException('The certificate is cut short');
      }
      content.add(chunk);
      progress?.reading(file, content.length);
    }
    progress?.done(file);
    return content.takeBytes();
  }

  // The file itself first, as when its directory is already selected, then
  // the whole path. Not found there may mean another applet was left
  // selected: reselect the Belpic applet and retry.
  Future<void> _select(BelgianEidFile file) async {
    final response = await channel.send(
      CommandApdu(0x00, 0xA4, 0x02, 0x0C, data: [
        file.fileId >> 8,
        file.fileId & 0xFF,
      ]),
    );
    if (response.isSuccess) return;
    try {
      await channel.selectPath(file.path);
    } on CardException catch (error) {
      if (error.statusWord != 0x6A82 && error.statusWord != 0x6A86) rethrow;
      await channel.selectApplication(appletAid, returnFci: true);
      await channel.selectPath(file.path);
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// Everything a [BelgianEidReader.read] brings back from the card.
final class BelgianEid {
  /// The files read from one card.
  const BelgianEid({
    required this.identity,
    this.identitySignature,
    this.address,
    this.addressSignature,
    this.photo,
    this.nationalRegisterCertificate,
    this.signaturesVerified = false,
    this.authenticity,
  });

  /// The identity file.
  final BelgianIdentity identity;

  /// The national register's signature of the identity file, when read.
  final Uint8List? identitySignature;

  /// The address file, when it was read.
  final BelgianAddress? address;

  /// The register's signature of the address file, when read, as the card
  /// holds it: padded, and covering [identitySignature] too.
  final Uint8List? addressSignature;

  /// The photo, a JPEG, when it was read.
  final Uint8List? photo;

  /// The national register's DER certificate, when signatures were checked.
  final Uint8List? nationalRegisterCertificate;

  /// Whether the national register's signatures were checked and held.
  final bool signaturesVerified;

  /// What the chip proved about itself, when asked; never
  /// [BelgianCardAuthenticity.notGenuine], since such a read throws.
  final BelgianCardAuthenticity? authenticity;

  /// Everything read as JSON, bytes in base64, for [BelgianEid.fromJson]
  /// and a [BelgianSignatureVerifier] on a server.
  Map<String, Object?> toJson() => {
        'identity': identity.toJson(),
        if (identitySignature case final bytes?)
          'identitySignature': base64Encode(bytes),
        if (address case final address?) 'address': address.toJson(),
        if (addressSignature case final bytes?)
          'addressSignature': base64Encode(bytes),
        if (photo case final bytes?) 'photo': base64Encode(bytes),
        if (nationalRegisterCertificate case final bytes?)
          'nationalRegisterCertificate': base64Encode(bytes),
        'signaturesVerified': signaturesVerified,
        if (authenticity case final authenticity?)
          'authenticity': authenticity.name,
      };

  /// What [toJson] wrote.
  ///
  /// [signaturesVerified] is always false and [authenticity] null: check the
  /// signatures again. Throws a [FormatException] on malformed [json].
  factory BelgianEid.fromJson(Map<String, Object?> json) {
    Uint8List? bytes(String key) => switch (json[key]) {
          null => null,
          final String text => base64Decode(text),
          final other => throw FormatException('$key is not base64', other),
        };
    Map<String, Object?>? object(String key) => switch (json[key]) {
          null => null,
          final Map<String, Object?> map => map,
          final other => throw FormatException('$key is not an object', other),
        };
    return BelgianEid(
      identity: BelgianIdentity.fromJson(
        object('identity') ??
            (throw const FormatException('The JSON has no identity')),
      ),
      identitySignature: bytes('identitySignature'),
      address: switch (object('address')) {
        final address? => BelgianAddress.fromJson(address),
        null => null,
      },
      addressSignature: bytes('addressSignature'),
      photo: bytes('photo'),
      nationalRegisterCertificate: bytes('nationalRegisterCertificate'),
    );
  }

  /// Whether [photo] was read and matches the identity file's photo hash.
  bool get photoMatches => photo != null && identity.matchesPhoto(photo!);
}

/// Estimates read progress from the usual size of each file.
final class _Progress {
  _Progress(this._report, List<BelgianEidFile> files)
      : _total = files.fold(0, (sum, file) => sum + _usualSize(file));

  final BelgianReadProgress? _report;
  final int _total;
  int _done = 0;
  double _last = 0;

  void reading(BelgianEidFile file, int bytes) {
    final size = _usualSize(file);
    _emit((_done + (bytes < size ? bytes : size)) / _total);
  }

  void done(BelgianEidFile file) {
    _done += _usualSize(file);
    _emit(_done / _total);
  }

  void skip(BelgianEidFile file) => done(file);

  void finish() => _emit(1);

  void _emit(double fraction) {
    final report = _report;
    if (report == null || fraction <= _last) return;
    _last = fraction > 1 ? 1 : fraction;
    report(_last);
  }

  static int _usualSize(BelgianEidFile file) => switch (file) {
        BelgianEidFile.identity => 220,
        BelgianEidFile.address => 130,
        BelgianEidFile.photo => 3500,
        BelgianEidFile.identitySignature ||
        BelgianEidFile.addressSignature =>
          256,
        BelgianEidFile.basicPublicKey => 120,
        _ => 1200,
      };
}
