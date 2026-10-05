import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eid_belgium/src/bytes.dart';

// ECDSA on P-384 in Jacobian coordinates, much faster than pointycastle.
// Signing serves the simulated cards, whose keys are public; it is not
// constant time.

final _p = _hex(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe'
  'ffffffff0000000000000000ffffffff',
);
final _n = _hex(
  'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf'
  '581a0db248b0a77aecec196accc52973',
);
final _b = _hex(
  'b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875a'
  'c656398d8a2ed19d2a85c8edd3ec2aef',
);
final _gx = _hex(
  'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
  '5502f25dbf55296c3a545e3872760ab7',
);
final _gy = _hex(
  '3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c0'
  '0a60b1ce1d7e819d7a431d7c90ea0e5f',
);

BigInt _hex(String hex) => BigInt.parse(hex, radix: 16);

/// The public point of [d], uncompressed: 04, x and y on 48 bytes each.
Uint8List p384PublicPoint(BigInt d) {
  final (x, y) = _affine(_multiply(d, _generator));
  return Uint8List.fromList([4, ..._bytes(x), ..._bytes(y)]);
}

/// The deterministic (RFC 6979) ECDSA signature of a 48 byte [digest] by
/// [d], as r and s.
(BigInt, BigInt) p384Sign(BigInt d, List<int> digest) {
  final e = _int(digest) % _n;
  for (final k in _nonces(d, e)) {
    final (x, _) = _affine(_multiply(k, _generator));
    final r = x % _n;
    if (r == BigInt.zero) continue;
    final s = k.modInverse(_n) * (e + r * d) % _n;
    if (s != BigInt.zero) return (r, s);
  }
  throw StateError('unreachable');
}

/// Whether ([r], [s]) is the signature of [hash] by the public point
/// ([x], [y]). A hash longer than 384 bits is cut to its leftmost 384.
bool p384Verify(BigInt x, BigInt y, List<int> hash, BigInt r, BigInt s) {
  if (r <= BigInt.zero || r >= _n || s <= BigInt.zero || s >= _n) {
    return false;
  }
  if (!_onCurve(x, y)) return false;
  final digest = hash.length > 48 ? hash.sublist(0, 48) : hash;
  final e = _int(digest) % _n;
  final w = s.modInverse(_n);
  final point = _add(
    _multiply(e * w % _n, _generator),
    _multiply(r * w % _n, _multiples(x, y)),
  );
  if (point.$3 == BigInt.zero) return false;
  return _affine(point).$1 % _n == r;
}

/// Whether ([x], [y]) is a point of P-384.
bool p384OnCurve(BigInt x, BigInt y) => _onCurve(x, y);

bool _onCurve(BigInt x, BigInt y) {
  if (x < BigInt.zero || x >= _p || y < BigInt.zero || y >= _p) return false;
  return (y * y - (x * x * x - _three * x + _b)) % _p == BigInt.zero;
}

// 1 to 15 times (x, y), in affine coordinates, for [_multiply].
List<(BigInt, BigInt)> _multiples(BigInt x, BigInt y) {
  final points = <_Point>[];
  final base = (x, y, BigInt.one);
  var multiple = base;
  for (var j = 1; j <= 15; j++) {
    points.add(multiple);
    multiple = _add(multiple, base);
  }
  return _batchAffine(points);
}

final _generator = _multiples(_gx, _gy);

// k times the point whose [_multiples] are [table], four bits at a time.
_Point _multiply(BigInt k, List<(BigInt, BigInt)> table) {
  final digits = _bytes(k);
  var result = _infinity;
  for (final byte in digits) {
    for (final digit in [byte >> 4, byte & 15]) {
      for (var d = 0; d < 4; d++) {
        result = _double(result);
      }
      if (digit != 0) {
        final (px, py) = table[digit - 1];
        result = _addAffine(result, px, py);
      }
    }
  }
  return result;
}

// RFC 6979, section 3.2, with HMAC-SHA-384: q and the hash are both 384 bits.
Iterable<BigInt> _nonces(BigInt d, BigInt e) sync* {
  final x = _bytes(d);
  final h = _bytes(e);
  var v = List.filled(48, 1);
  var k = List.filled(48, 0);
  List<int> mac(List<int> key, List<int> data) =>
      Hmac(sha384, key).convert(data).bytes;
  k = mac(k, [...v, 0, ...x, ...h]);
  v = mac(k, v);
  k = mac(k, [...v, 1, ...x, ...h]);
  v = mac(k, v);
  while (true) {
    v = mac(k, v);
    final candidate = _int(v);
    if (candidate > BigInt.zero && candidate < _n) yield candidate;
    k = mac(k, [...v, 0]);
    v = mac(k, v);
  }
}

// A point in Jacobian coordinates: (X / Z², Y / Z³). Z = 0 is infinity.
typedef _Point = (BigInt, BigInt, BigInt);

final _infinity = (BigInt.one, BigInt.one, BigInt.zero);

final _three = BigInt.from(3);
final _four = BigInt.from(4);
final _eight = BigInt.from(8);

// dbl-2001-b, for a = -3.
_Point _double(_Point point) {
  final (x, y, z) = point;
  if (z == BigInt.zero || y == BigInt.zero) return _infinity;
  final delta = z * z % _p;
  final gamma = y * y % _p;
  final beta = x * gamma % _p;
  final alpha = _three * ((x - delta) * (x + delta) % _p) % _p;
  final x3 = (alpha * alpha - _eight * beta) % _p;
  final z3 = ((y + z) * (y + z) - gamma - delta) % _p;
  final y3 = (alpha * (_four * beta - x3) - _eight * (gamma * gamma % _p)) % _p;
  return (x3, y3, z3);
}

// add-2007-bl, for two Jacobian points.
_Point _add(_Point a, _Point b) {
  final (x1, y1, z1) = a;
  final (x2, y2, z2) = b;
  if (z1 == BigInt.zero) return b;
  if (z2 == BigInt.zero) return a;
  final z1z1 = z1 * z1 % _p;
  final z2z2 = z2 * z2 % _p;
  final u1 = x1 * z2z2 % _p;
  final u2 = x2 * z1z1 % _p;
  final s1 = y1 * z2 % _p * z2z2 % _p;
  final s2 = y2 * z1 % _p * z1z1 % _p;
  final h = (u2 - u1) % _p;
  final r = BigInt.two * (s2 - s1) % _p;
  if (h == BigInt.zero) return r == BigInt.zero ? _double(a) : _infinity;
  final i = (BigInt.two * h) * (BigInt.two * h) % _p;
  final j = h * i % _p;
  final v = u1 * i % _p;
  final x3 = (r * r - j - BigInt.two * v) % _p;
  final y3 = (r * (v - x3) - BigInt.two * s1 * j) % _p;
  final z3 = (((z1 + z2) * (z1 + z2) - z1z1 - z2z2) % _p) * h % _p;
  return (x3, y3, z3);
}

// madd-2007-bl: adds the affine point (x2, y2).
_Point _addAffine(_Point point, BigInt x2, BigInt y2) {
  final (x1, y1, z1) = point;
  if (z1 == BigInt.zero) return (x2, y2, BigInt.one);
  final z1z1 = z1 * z1 % _p;
  final u2 = x2 * z1z1 % _p;
  final s2 = y2 * z1 % _p * z1z1 % _p;
  final h = (u2 - x1) % _p;
  final r = BigInt.two * (s2 - y1) % _p;
  if (h == BigInt.zero) {
    return r == BigInt.zero ? _double(point) : _infinity;
  }
  final hh = h * h % _p;
  final i = _four * hh % _p;
  final j = h * i % _p;
  final v = x1 * i % _p;
  final x3 = (r * r - j - BigInt.two * v) % _p;
  final y3 = (r * (v - x3) - BigInt.two * y1 * j) % _p;
  final z3 = ((z1 + h) * (z1 + h) - z1z1 - hh) % _p;
  return (x3, y3, z3);
}

// Many points to affine coordinates with one inversion (Montgomery's trick).
List<(BigInt, BigInt)> _batchAffine(List<_Point> points) {
  final prefix = <BigInt>[];
  var product = BigInt.one;
  for (final (_, _, z) in points) {
    prefix.add(product);
    product = product * z % _p;
  }
  var inverse = product.modInverse(_p);
  final result = List<(BigInt, BigInt)>.filled(
    points.length,
    (BigInt.zero, BigInt.zero),
  );
  for (var i = points.length - 1; i >= 0; i--) {
    final (x, y, z) = points[i];
    final zInverse = inverse * prefix[i] % _p;
    inverse = inverse * z % _p;
    final zz = zInverse * zInverse % _p;
    result[i] = (x * zz % _p, y * zz % _p * zInverse % _p);
  }
  return result;
}

(BigInt, BigInt) _affine(_Point point) {
  final (x, y, z) = point;
  final zInverse = z.modInverse(_p);
  final zz = zInverse * zInverse % _p;
  return (x * zz % _p, y * zz % _p * zInverse % _p);
}

BigInt _int(List<int> bytes) => unsignedBigInt(bytes);

List<int> _bytes(BigInt value) => bigIntBytes(value, 48);
