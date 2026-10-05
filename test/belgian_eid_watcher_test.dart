import 'package:eid_belgium/eid_belgium.dart';
import 'package:eid_belgium/testing.dart';
import 'package:test/test.dart';

void main() {
  const tick = Duration(milliseconds: 5);

  late SimulatedBelgianCard card;
  late BelgianEidWatcher watcher;
  late List<BelgianEidEvent> events;

  // Waits for the watcher to notice the card, and for a read under way to
  // end, however busy the machine.
  Future<void> settle() async {
    await Future<void>.delayed(tick * 8);
    for (var i = 0; i < 200; i++) {
      final reading = events.isNotEmpty &&
          (events.last is BelgianCardInserted ||
              events.last is BelgianPinVerified) &&
          watcher.autoRead;
      if (!reading) return;
      await Future<void>.delayed(tick);
    }
  }

  setUp(() {
    card = SimulatedBelgianCard()..remove();
    events = [];
  });

  tearDown(() => watcher.dispose());

  BelgianEidWatcher watch({
    bool autoRead = true,
    Set<BelgianEidPart> parts = BelgianEidPart.all,
    bool acceptExpired = true,
    BelgianPinPrompt? pinPrompt,
  }) {
    watcher = BelgianEidWatcher(
      card,
      autoRead: autoRead,
      parts: parts,
      acceptExpired: acceptExpired,
      pinPrompt: pinPrompt,
      interval: tick,
    );
    watcher.events.listen(events.add);
    return watcher..start();
  }

  test('reads a card as it goes in, and forgets it when it leaves', () async {
    watch();
    await settle();
    expect(events, isEmpty);

    card.insert();
    await settle();
    expect(events[0], isA<BelgianCardInserted>());
    final read = events[1] as BelgianCardRead;
    expect(read.eid.identity.lastName, 'Specimen');
    expect(read.eid.photoMatches, isTrue);
    expect(watcher.eid, same(read.eid));

    card.remove();
    await settle();
    expect(events.last, isA<BelgianCardRemoved>());
    expect(watcher.hasCard, isFalse);
    expect(watcher.eid, isNull);
  });

  test('leaves the reading to the application when autoRead is off', () async {
    watch(autoRead: false);
    card.insert();
    await settle();
    expect(events.single, isA<BelgianCardInserted>());

    final eid = await watcher.read();
    expect(eid.identity.lastName, 'Specimen');
    // Events reach listeners on the next turn of the event loop.
    await Future<void>.delayed(Duration.zero);
    expect(events.last, isA<BelgianCardRead>());
  });

  test('leaves the photo out on request', () async {
    watch(parts: {BelgianEidPart.address});
    card.insert();
    await settle();
    expect((events.last as BelgianCardRead).eid.photo, isNull);
  });

  test('reports a card pulled out halfway through the read', () async {
    card = SimulatedBelgianCard(latency: const Duration(milliseconds: 2))
      ..remove();
    // Pulled out a few commands into the read, however busy the machine.
    var commands = 0;
    watch().onApdu = (_) {
      if (++commands == 5) card.remove();
    };
    card.insert();
    for (var i = 0; i < 400; i++) {
      if (events.isNotEmpty && events.last is BelgianCardRemoved) break;
      await Future<void>.delayed(tick);
    }

    // The failure is reported unless the removal was noticed first.
    expect(events.whereType<BelgianCardReadFailed>().length, lessThan(2));
    expect(events.whereType<BelgianCardRead>(), isEmpty);
    expect(events.last, isA<BelgianCardRemoved>());
    expect(watcher.eid, isNull);
  });

  test('refuses a manual read with no card', () async {
    watch(autoRead: false);
    await expectLater(watcher.read(), throwsA(isA<CardTransportException>()));
  });

  test('turns down an expired card', () async {
    card = SimulatedBelgianCard(validUntil: DateTime.utc(2020, 1, 31))
      ..remove();
    watch(acceptExpired: false);
    card.insert();
    await settle();
    final failed = events.last as BelgianCardReadFailed;
    expect(
      failed.error,
      isA<BelgianCardRejectedException>()
          .having((e) => e.reason, 'reason', BelgianCardRejection.expired),
    );
    expect(watcher.eid, isNull);
  });

  group('pinPrompt', () {
    test('asks for the PIN before reading, again after a wrong one', () async {
      final asked = <int?>[];
      final answers = ['0000', '12', '1234'];
      List<Type>? seenAtFirstPrompt;
      watch(
        pinPrompt: (triesLeft) async {
          seenAtFirstPrompt ??= [for (final e in events) e.runtimeType];
          asked.add(triesLeft);
          return answers.removeAt(0);
        },
      );
      card.insert();
      await settle();

      // A malformed PIN is asked again without spending a try.
      expect(asked, [null, 2, 2]);
      expect(seenAtFirstPrompt, [BelgianCardInserted]);
      expect(card.pinTriesLeft, 3);
      expect(events.map((e) => e.runtimeType), [
        BelgianCardInserted,
        BelgianPinVerified,
        BelgianCardRead,
      ]);
      expect(watcher.pinVerified, isTrue);

      // Not asked again for the same card.
      await watcher.read();
      expect(asked, hasLength(3));
    });

    test('reads nothing when the holder gives up', () async {
      watch(pinPrompt: (_) async => null);
      card.insert();
      await settle();
      expect(
        (events.last as BelgianCardReadFailed).error,
        isA<PinCancelledException>(),
      );
      expect(watcher.eid, isNull);
    });

    test('stops once the card blocks the PIN', () async {
      var asked = 0;
      watch(
        pinPrompt: (_) async {
          asked++;
          return '0000';
        },
      );
      card.insert();
      await settle();
      expect(asked, 3);
      expect(
        (events.last as BelgianCardReadFailed).error,
        isA<PinException>().having((e) => e.isBlocked, 'isBlocked', isTrue),
      );
    });

    test('asks again for the next card', () async {
      var asked = 0;
      watch(
        pinPrompt: (_) async {
          asked++;
          return '1234';
        },
      );
      card.insert();
      await settle();
      card.remove();
      await settle();
      expect(watcher.pinVerified, isFalse);
      card.insert();
      await settle();
      expect(asked, 2);
    });

    test('is skipped once verifyPin was called', () async {
      var asked = 0;
      watch(
        autoRead: false,
        pinPrompt: (_) async {
          asked++;
          return '1234';
        },
      );
      card.insert();
      await settle();
      await watcher.verifyPin('1234');
      await watcher.read();
      expect(asked, 0);
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<BelgianPinVerified>(), hasLength(1));
    });
  });

  test('reports the exchanges of a read, not its presence checks', () async {
    final exchanges = <ApduExchange>[];
    watch().onApdu = exchanges.add;
    card.insert();
    await settle();
    await Future<void>.delayed(tick * 10);
    expect(events.last, isA<BelgianCardRead>());
    expect(exchanges, isNotEmpty);
    expect(
      exchanges.where((e) => e.command.length == 5 && e.command[1] == 0xCA),
      isEmpty,
    );
  });

  test('remembers photos by default, and forgets them when told not to',
      () async {
    final exchanges = <ApduExchange>[];
    watch().onApdu = exchanges.add;
    bool selectsPhoto(ApduExchange e) => hexString(e.command).endsWith('4035');

    card.insert();
    await settle();
    card.remove();
    await settle();
    card.insert();
    await settle();
    expect(exchanges.where(selectsPhoto), hasLength(1));
    expect(watcher.photoCache.length, 1);

    watcher.rememberPhotos = false;
    expect(watcher.photoCache.length, 0);
    card.remove();
    await settle();
    card.insert();
    await settle();
    expect(exchanges.where(selectsPhoto), hasLength(2));
  });
}
