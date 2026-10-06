/// What a read may leave out. The identity file is always read.
enum BelgianEidPart {
  /// The address file.
  address,

  /// The photo, the largest file and most of the reading time.
  photo,

  /// The national register's signatures of the identity and address files.
  /// Always read to verify them, but never returned without the national
  /// number, which they would give away.
  signatures,

  /// The national register number, whose use Belgian law restricts. It is
  /// read only with `showPrivateData` too; otherwise it is removed from the
  /// identity file once read.
  nationalNumber;

  /// Every part: the whole card, the national number only with
  /// `showPrivateData`.
  static const all = {address, photo, signatures, nationalNumber};
}
