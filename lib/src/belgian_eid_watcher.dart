import 'dart:async';
import 'dart:typed_data';

import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_document_type.dart';
import 'package:eid_belgium/src/belgian_eid_part.dart';
import 'package:eid_belgium/src/belgian_eid_reader.dart';
import 'package:eid_belgium/src/belgian_photo_cache.dart';
import 'package:eid_belgium/src/pin.dart';
import 'package:eid_belgium/src/simulated_transport.dart';

/// Asks the holder for their PIN, or returns null when they give up.
///
/// [triesLeft] is null on the first ask, then the tries left after a wrong
/// PIN.
typedef BelgianPinPrompt = Future<String?> Function(int? triesLeft);

/// Something that happened to a card in a watched terminal.
sealed class BelgianEidEvent {
  const BelgianEidEvent();
}

/// A card went in.
final class BelgianCardInserted extends BelgianEidEvent {
  /// A card [reader] reads went in.
  const BelgianCardInserted(this.reader);

  /// The reader of the card, valid while it stays in.
  final BelgianEidReader reader;
}

/// The card accepted the holder's PIN.
final class BelgianPinVerified extends BelgianEidEvent {
  /// The card [reader] reads accepted the PIN.
  const BelgianPinVerified(this.reader);

  /// The reader of the card that accepted the PIN.
  final BelgianEidReader reader;
}

/// A card was read.
final class BelgianCardRead extends BelgianEidEvent {
  /// [reader] read [eid].
  const BelgianCardRead(this.eid, this.reader);

  /// What was read.
  final BelgianEid eid;

  /// The reader of the card, to check its PIN or read more.
  final BelgianEidReader reader;
}

/// A read failed.
///
/// A card pulled out mid-read is reported here first, with a
/// `CardTransportException`, then by [BelgianCardRemoved].
final class BelgianCardReadFailed extends BelgianEidEvent {
  /// A read that failed with [error].
  const BelgianCardReadFailed(this.error);

  /// A `BelgianCardRejectedException`, a `PinCancelledException`, a
  /// `PinException`, a `CardException`, a `CardTransportException` or a
  /// `FormatException`.
  final Exception error;
}

/// The card left the terminal and what was read from it is forgotten.
final class BelgianCardRemoved extends BelgianEidEvent {
  /// The card left.
  const BelgianCardRemoved();
}

/// Watches a terminal for Belgian cards and, when [autoRead] is on, reads
/// each one as it goes in.
///
/// ```dart
/// final watcher = BelgianEidWatcher(terminal)..start();
/// watcher.events.listen((event) {
///   switch (event) {
///     case BelgianCardRead read:
///       print(read.eid.identity.lastName);
///     case BelgianCardRemoved _:
///       print('Card removed');
///     default:
///   }
/// });
/// ```
///
/// Options can be changed at any time and apply to the next read.
final class BelgianEidWatcher {
  /// A watcher of [terminal], polled every [interval] once [start]ed.
  BelgianEidWatcher(
    CardTerminal terminal, {
    this.autoRead = true,
    Set<BelgianEidPart> parts = BelgianEidPart.all,
    this.acceptExpired = false,
    this.acceptedTypes,
    this.pinPrompt,
    bool rememberPhotos = true,
    this.verifySignatures = true,
    this.trustedRoots,
    this.verifyCard = true,
    this.onApdu,
    this.onProgress,
    Duration interval = const Duration(milliseconds: 400),
  })  : parts = {...parts},
        _rememberPhotos = rememberPhotos,
        _cards = CardWatcher(terminal, interval: interval);

  /// Whether a card is read as soon as it goes in.
  bool autoRead;

  /// What reads bring back besides the identity file.
  Set<BelgianEidPart> parts;

  /// Whether an expired card is read rather than rejected.
  bool acceptExpired;

  /// The document types read, or null for all; others are rejected.
  Set<BelgianDocumentType>? acceptedTypes;

  /// When set, asks for the PIN before each read until the card accepts it,
  /// the holder gives up or the card blocks.
  ///
  /// Close a prompt still open on [BelgianCardRemoved]; its answer is lost.
  BelgianPinPrompt? pinPrompt;

  /// The photos of the cards read lately, used while [rememberPhotos] is on.
  final photoCache = BelgianPhotoCache();

  /// Whether a card read again takes its photo from [photoCache] rather
  /// than from the card. Turning it off empties the cache.
  bool get rememberPhotos => _rememberPhotos;

  set rememberPhotos(bool value) {
    _rememberPhotos = value;
    if (!value) photoCache.clear();
  }

  bool _rememberPhotos;

  /// Whether the national register's signatures are checked.
  bool verifySignatures;

  /// The DER root certificates to trust, or null for the Belgian roots (and
  /// for a `SimulatedBelgianCard`, its own root).
  List<Uint8List>? trustedRoots;

  /// Whether the chip must prove it is genuine.
  bool verifyCard;

  /// Called with each command and answer, except presence checks. The PIN
  /// is never reported.
  ApduListener? onApdu;

  /// Follows each read, from 0 to 1.
  BelgianReadProgress? onProgress;

  final CardWatcher _cards;
  final _events = StreamController<BelgianEidEvent>.broadcast();
  StreamSubscription<CardEvent>? _subscription;
  BelgianEidReader? _reader;
  BelgianEid? _eid;
  bool _pinVerified = false;

  /// The terminal watched.
  CardTerminal get terminal => _cards.terminal;

  /// What happens to cards. A failure to reach the terminal is an error.
  Stream<BelgianEidEvent> get events => _events.stream;

  /// The reader of the card in the terminal, or null when there is none.
  BelgianEidReader? get reader => _reader;

  /// What was last read from the card in the terminal, or null.
  BelgianEid? get eid => _eid;

  /// Whether a card is in the terminal.
  bool get hasCard => _reader != null;

  /// Whether the card in the terminal accepted the holder's PIN.
  bool get pinVerified => _pinVerified;

  /// Starts watching. A card already in the terminal is reported.
  void start() {
    _subscription ??= _cards.events.listen(
      _onCard,
      onError: _events.addError,
    );
    _cards.start();
  }

  /// Stops watching and releases the card.
  Future<void> stop() async {
    _autoReading?.cancel();
    final reader = _reader;
    await _cards.stop();
    // A start() meanwhile may already have reported a new card.
    if (identical(_reader, reader)) _release();
  }

  /// Stops watching for good and closes [events].
  Timer? _autoReading;

  Future<void> dispose() async {
    _autoReading?.cancel();
    final stopping = _cards.dispose();
    // Not awaited: its future would never complete under a fake clock.
    unawaited(_subscription?.cancel());
    _subscription = null;
    await stopping;
    _release();
    photoCache.clear();
    await _events.close();
  }

  /// Reads the card in the terminal and reports the outcome on [events].
  ///
  /// Throws a [CardTransportException] when there is no card, and whatever
  /// [BelgianCardReadFailed] carries when the read fails.
  Future<BelgianEid> read() {
    final reader = _reader;
    if (reader == null) {
      return Future.error(
        const CardTransportException('No card in the terminal'),
      );
    }
    // A read under way for this card is shared, PIN prompt included.
    final current = _reading;
    if (current != null && identical(_readingReader, reader)) return current;
    final reading = _reading = _read(reader);
    _readingReader = reader;
    void done() {
      if (identical(_reading, reading)) _reading = _readingReader = null;
    }

    reading.then((_) => done(), onError: (Object _) => done());
    return reading;
  }

  Future<BelgianEid>? _reading;
  BelgianEidReader? _readingReader;

  Future<BelgianEid> _read(BelgianEidReader reader) async {
    try {
      final prompt = pinPrompt;
      if (prompt != null && !_pinVerified) await _askPin(reader, prompt);
      final eid = await reader.read(
        parts: parts,
        acceptExpired: acceptExpired,
        acceptedTypes: acceptedTypes,
        photoCache: _rememberPhotos ? photoCache : null,
        verifySignatures: verifySignatures,
        trustedRoots: trustedRoots ??
            switch (terminal) {
              // The simulated card's root, for the simulated card alone.
              final SimulatedTransport simulated => [simulated.simulatedRoot],
              _ => null,
            },
        verifyCard: verifyCard,
        onProgress: onProgress,
      );
      // The card may have been swapped while it was being read.
      if (identical(reader, _reader)) {
        _eid = eid;
        _events.add(BelgianCardRead(eid, reader));
      }
      return eid;
    } on Exception catch (error) {
      if (identical(reader, _reader)) {
        _events.add(BelgianCardReadFailed(error));
      }
      rethrow;
    }
  }

  /// Checks [pin] as [BelgianEidReader.verifyPin] does and reports success
  /// on [events]. Throws a [CardTransportException] when there is no card.
  Future<void> verifyPin(String pin) async {
    final reader = _currentReader();
    await reader.verifyPin(pin);
    _verified(reader);
  }

  Future<void> _askPin(BelgianEidReader reader, BelgianPinPrompt prompt) async {
    int? triesLeft;
    while (true) {
      final pin = await prompt(triesLeft);
      if (pin == null) throw const PinCancelledException();
      if (!identical(reader, _reader)) {
        throw const CardTransportException('The card was removed');
      }
      // Asked again without spending a try.
      if (!isWellFormedPin(pin)) continue;
      try {
        await reader.verifyPin(pin);
        _verified(reader);
        return;
      } on PinException catch (error) {
        if (error.isBlocked) rethrow;
        triesLeft = error.triesLeft;
      }
    }
  }

  void _verified(BelgianEidReader reader) {
    if (!identical(reader, _reader)) return;
    _pinVerified = true;
    _events.add(BelgianPinVerified(reader));
  }

  BelgianEidReader _currentReader() =>
      _reader ??
      (throw const CardTransportException('No card in the terminal'));

  void _onCard(CardEvent event) {
    switch (event) {
      case CardInserted(:final connection):
        final reader = _reader = BelgianEidReader(
          connection,
          onApdu: (exchange) => onApdu?.call(exchange),
        );
        _eid = null;
        _pinVerified = false;
        _events.add(BelgianCardInserted(reader));
        // Deferred so that listeners hear of the insertion first.
        if (autoRead) _autoReading = Timer(Duration.zero, _autoRead);
      case CardRemoved():
        _forget();
        _events.add(const BelgianCardRemoved());
    }
  }

  Future<void> _autoRead() async {
    try {
      await read();
    } on Exception {
      // Already reported on the stream.
    } on Object catch (error, stackTrace) {
      if (!_events.isClosed) _events.addError(error, stackTrace);
    }
  }

  // Stopping lets go of the card: listeners hear it as a removal.
  void _release() {
    final hadCard = _reader != null;
    _forget();
    if (hadCard && !_events.isClosed) _events.add(const BelgianCardRemoved());
  }

  void _forget() {
    _reader = null;
    _eid = null;
    _pinVerified = false;
  }
}
