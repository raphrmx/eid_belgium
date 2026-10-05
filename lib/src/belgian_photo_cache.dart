import 'dart:typed_data';

import 'package:eid/eid.dart';
import 'package:eid_belgium/src/belgian_identity.dart';

/// An in-memory cache of recently read photos, keyed by the identity file's
/// photo hash, so that a card read again skips its slowest file.
///
/// Keeps at most [capacity] photos, dropping the least recently used.
final class BelgianPhotoCache {
  /// A cache of [capacity] photos at most.
  BelgianPhotoCache({this.capacity = 16}) {
    RangeError.checkNotNegative(capacity, 'capacity');
  }

  /// How many photos are kept at most.
  final int capacity;

  // Insertion ordered: the first key is the least recently used.
  final _photos = <String, Uint8List>{};

  /// How many photos are kept.
  int get length => _photos.length;

  /// The photo of the card [identity] was read from, or null.
  Uint8List? lookup(BelgianIdentity identity) {
    final key = _key(identity);
    if (key == null) return null;
    final photo = _photos.remove(key);
    if (photo != null) _photos[key] = photo;
    return photo;
  }

  /// Keeps [photo] for [identity], unless it does not match its photo hash.
  void store(BelgianIdentity identity, Uint8List photo) {
    final key = _key(identity);
    if (key == null || capacity == 0 || !identity.matchesPhoto(photo)) return;
    _photos
      ..remove(key)
      ..[key] = photo;
    while (_photos.length > capacity) {
      _photos.remove(_photos.keys.first);
    }
  }

  /// Forgets every photo.
  void clear() => _photos.clear();

  static String? _key(BelgianIdentity identity) =>
      identity.photoHash.isEmpty ? null : hexString(identity.photoHash);
}
