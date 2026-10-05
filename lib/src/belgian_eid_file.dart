/// The files of a Belgian card that can be read without a PIN.
enum BelgianEidFile {
  /// EF(ID#RN), the identity file.
  identity(0xDF01, 0x4031),

  /// EF(SGN#ID), the national register's signature of [identity].
  identitySignature(0xDF01, 0x4032),

  /// EF(ID#Address), the address file.
  address(0xDF01, 0x4033),

  /// EF(SGN#Address), the signature of [address] then [identitySignature].
  addressSignature(0xDF01, 0x4034),

  /// EF(ID#Photo), the holder's photo as a JPEG.
  photo(0xDF01, 0x4035),

  /// EF(PuK#1 Basic), the card's basic public key.
  basicPublicKey(0xDF01, 0x4040),

  /// EF(Cert#2), the holder's authentication certificate.
  authenticationCertificate(0xDF00, 0x5038),

  /// EF(Cert#3), the holder's qualified signature certificate.
  signingCertificate(0xDF00, 0x5039),

  /// EF(Cert#4), the CA that issued the holder's certificates.
  caCertificate(0xDF00, 0x503A),

  /// EF(Cert#6), the Belgian root CA.
  rootCertificate(0xDF00, 0x503B),

  /// EF(Cert#8), the national register's certificate.
  nationalRegisterCertificate(0xDF00, 0x503C);

  const BelgianEidFile(this.directory, this.fileId);

  /// The directory the file sits in: DF(ID) or DF(BELPIC).
  final int directory;

  /// The file identifier within [directory].
  final int fileId;

  /// The path from the master file.
  List<int> get path => [0x3F00, directory, fileId];

  /// Whether the file holds an X.509 certificate.
  bool get isCertificate => directory == 0xDF00;
}
