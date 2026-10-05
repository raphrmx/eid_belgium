/// The outcome of `BelgianEidReader.proveGenuine`.
enum BelgianCardAuthenticity {
  /// The chip proved it is the card issued, not a copy of its files.
  genuine,

  /// The chip failed the proof: likely a copy or a forgery.
  notGenuine,

  /// The card predates applet 1.8 and cannot prove it.
  notSupported,
}
