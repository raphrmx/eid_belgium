// ignore_for_file: avoid_print

import 'package:eid_belgium/eid_belgium.dart';

/// Reads a card and prints who it belongs to.
///
/// The transport comes from an adapter package. In a Flutter application
/// with a USB reader, that is `eid_ccid`:
///
/// ```dart
/// final readers = await CcidTransport.listReaders();
/// final transport = await CcidTransport.connect(readers.first);
/// await printCard(transport);
/// await transport.disconnect();
/// ```
Future<void> printCard(CardTransport transport) async {
  final reader = BelgianEidReader(transport);
  final eid = await reader.read();
  final identity = eid.identity;

  print('${identity.firstNames} ${identity.lastName}');
  print('Born ${identity.birthDate} in ${identity.birthPlace}');
  print('Lives at ${eid.address}');
  print('Card ${identity.cardNumber}, valid until ${identity.validUntil}');
  print('Photo ${eid.photoMatches ? 'matches' : 'does not match'} the card');
}
