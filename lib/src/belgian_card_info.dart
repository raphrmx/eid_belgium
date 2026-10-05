import 'dart:typed_data';

import 'package:eid/eid.dart';

/// The chip and applet details the card returns to GET CARD DATA.
final class BelgianCardInfo {
  /// Splits the card's answer. Throws a [FormatException] if too short.
  factory BelgianCardInfo.parse(Uint8List data) {
    if (data.length < length) {
      throw FormatException(
        'GET CARD DATA returns $length bytes, not ${data.length}',
        hexString(data),
      );
    }
    return BelgianCardInfo._(data);
  }

  BelgianCardInfo._(this.data);

  /// The number of bytes GET CARD DATA returns.
  static const length = 28;

  /// The bytes as returned.
  final Uint8List data;

  /// The chip's 16 byte serial number.
  Uint8List get serialNumber => Uint8List.sublistView(data, 0, 16);

  /// The component code.
  int get componentCode => data[16];

  /// The operating system number.
  int get osNumber => data[17];

  /// The operating system version.
  int get osVersion => data[18];

  /// The softmask number.
  int get softmaskNumber => data[19];

  /// The softmask version.
  int get softmaskVersion => data[20];

  /// The Belpic applet version, such as `0x17` or `0x18`.
  int get appletVersion => data[21];

  /// The global operating system version.
  int get globalOsVersion => data[22] << 8 | data[23];

  /// The applet interface version.
  int get appletInterfaceVersion => data[24];

  /// The PKCS#1 support byte.
  int get pkcs1Support => data[25];

  /// The key exchange version.
  int get keyExchangeVersion => data[26];

  /// The applet life cycle: `0x0F` once the card is personalised.
  int get appletLifeCycle => data[27];

  /// Whether the card carries applet 1.8 or later.
  bool get isApplet18OrLater => appletVersion >= 0x18;

  @override
  String toString() =>
      'BelgianCardInfo(applet ${appletVersion.toRadixString(16)}, '
      'serial ${hexString(serialNumber)})';
}
