import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:eid_belgium/src/bytes.dart';
import 'package:eid_belgium/src/der.dart';

/// The hashes an ECDSA signature on a card is computed over.
enum EcHash {
  /// SHA-256.
  sha256,

  /// SHA-384.
  sha384,

  /// SHA-512.
  sha512,
}

extension type _Global._(JSObject _) implements JSObject {
  external _Crypto get crypto;
}

extension type _Crypto._(JSObject _) implements JSObject {
  external _Subtle get subtle;
}

// The getters need the real global object as their receiver.
@JS('globalThis')
external _Global get _global;

_Subtle get _subtle => _global.crypto.subtle;

extension type _Subtle._(JSObject _) implements JSObject {
  external JSPromise<JSObject> importKey(
    String format,
    JSAny keyData,
    JSObject algorithm,
    bool extractable,
    JSArray<JSString> usages,
  );

  external JSPromise<JSBoolean> verify(
    JSObject algorithm,
    JSObject key,
    JSUint8Array signature,
    JSUint8Array data,
  );

  external JSPromise<JSArrayBuffer> sign(
    JSObject algorithm,
    JSObject key,
    JSUint8Array data,
  );
}

JSObject _object(Map<String, Object> fields) => fields.jsify()! as JSObject;

final _curve = _object({'name': 'ECDSA', 'namedCurve': 'P-384'});

String _hashName(EcHash hash) => switch (hash) {
      EcHash.sha256 => 'SHA-256',
      EcHash.sha384 => 'SHA-384',
      EcHash.sha512 => 'SHA-512',
    };

/// Whether ([r], [s]) is the ECDSA signature of [data], hashed with [hash],
/// by the P-384 key in [publicKeyInfo], a DER SubjectPublicKeyInfo.
Future<bool> verifyP384({
  required Uint8List publicKeyInfo,
  required Uint8List data,
  required EcHash hash,
  required BigInt r,
  required BigInt s,
}) async {
  if (r.bitLength > 384 || s.bitLength > 384) return false;
  try {
    final key = await _subtle
        .importKey(
          'spki',
          publicKeyInfo.toJS,
          _curve,
          false,
          ['verify'.toJS].toJS,
        )
        .toDart;
    final signature = Uint8List.fromList([
      ...bigIntBytes(r, 48),
      ...bigIntBytes(s, 48),
    ]);
    final valid = await _subtle
        .verify(
          _object({'name': 'ECDSA', 'hash': _hashName(hash)}),
          key,
          signature.toJS,
          data.toJS,
        )
        .toDart;
    return valid.toDart;
  } on Object {
    // WebCrypto rejects a malformed key or signature.
    return false;
  }
}

/// The DER ECDSA signature of [data] with SHA-384 by [d], whose public point
/// is [point]. For the simulated cards only.
Future<Uint8List> signP384(BigInt d, Uint8List point, Uint8List data) async {
  String base64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
  final key = await _subtle
      .importKey(
        'jwk',
        _object({
          'kty': 'EC',
          'crv': 'P-384',
          'd': base64Url(bigIntBytes(d, 48)),
          'x': base64Url(point.sublist(1, 49)),
          'y': base64Url(point.sublist(49)),
        }),
        _curve,
        false,
        ['sign'.toJS].toJS,
      )
      .toDart;
  final raw = (await _subtle
          .sign(
            _object({'name': 'ECDSA', 'hash': 'SHA-384'}),
            key,
            data.toJS,
          )
          .toDart)
      .toDart
      .asUint8List();
  return derSequence([
    derInteger(unsignedBigInt(raw.sublist(0, 48))),
    derInteger(unsignedBigInt(raw.sublist(48))),
  ]);
}
