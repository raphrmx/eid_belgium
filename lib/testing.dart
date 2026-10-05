/// A Belgian eID in memory, to test an application without a card reader.
///
/// ```dart
/// import 'package:eid_belgium/eid_belgium.dart';
/// import 'package:eid_belgium/testing.dart';
///
/// final eid = await BelgianEidReader(SimulatedBelgianCard()).read();
/// ```
library;

export 'src/testing/simulated_belgian_card.dart';
export 'src/testing/specimen_photo.dart';
