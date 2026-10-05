import 'dart:typed_data';

/// Implemented by the simulated card and its connections only: the root
/// that signs them is trusted for them alone, never for a real card.
abstract interface class SimulatedTransport {
  /// The root certificate of the made-up register that signs the card.
  Uint8List get simulatedRoot;
}
