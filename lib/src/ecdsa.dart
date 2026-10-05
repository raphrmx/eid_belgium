// ECDSA on P-384: the browser's WebCrypto on the web, Dart code elsewhere.
export 'package:eid_belgium/src/ecdsa_native.dart'
    if (dart.library.js_interop) 'package:eid_belgium/src/ecdsa_web.dart';
