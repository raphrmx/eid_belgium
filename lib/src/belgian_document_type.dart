import 'package:eid_belgium/src/belgian_language.dart';

/// The kind of card, as the identity file codes it.
///
/// Uniform format cards follow the EU residence permit format.
enum BelgianDocumentType {
  /// The eID of a Belgian citizen.
  eid(1),

  /// The Kids ID, for Belgian children under 12.
  kidsId(6),

  /// A bootstrap card.
  bootstrap(7),

  /// An authorisation card ("habilitation", "machtiging").
  habilitation(8),

  /// A-card.
  aCard(11),

  /// B-card.
  bCard(12),

  /// C-card.
  cCard(13),

  /// D-card.
  dCard(14),

  /// E-card.
  eCard(15),

  /// E+ card.
  ePlusCard(16),

  /// F-card.
  fCard(17),

  /// F+ card.
  fPlusCard(18),

  /// H-card, the European Blue Card.
  hCard(19),

  /// I-card, for intra-corporate transferees.
  iCard(20),

  /// J-card, for long-term mobility of intra-corporate transferees.
  jCard(21),

  /// M-card, for beneficiaries of the Brexit withdrawal agreement.
  mCard(22),

  /// N-card, for frontier workers under the Brexit withdrawal agreement.
  nCard(23),

  /// K-card, in the uniform format.
  kCard(27),

  /// L-card, in the uniform format.
  lCard(28),

  /// EU card, the registration certificate of an EU citizen.
  euCard(31),

  /// EU+ card, the permanent residence document of an EU citizen.
  euPlusCard(32),

  /// A-card, in the uniform format.
  aCardUniformFormat(33),

  /// B-card, in the uniform format.
  bCardUniformFormat(34),

  /// F-card, in the uniform format.
  fCardUniformFormat(35),

  /// F+ card, in the uniform format.
  fPlusCardUniformFormat(36),

  /// EU card, for a child under 12.
  kidsEuCard(61),

  /// EU+ card, for a child under 12.
  kidsEuPlusCard(62),

  /// A-card, for a child under 12.
  kidsACard(63),

  /// B-card, for a child under 12.
  kidsBCard(64),

  /// K-card, for a child under 12.
  kidsKCard(65),

  /// L-card, for a child under 12.
  kidsLCard(66),

  /// F-card, for a child under 12.
  kidsFCard(67),

  /// F+ card, for a child under 12.
  kidsFPlusCard(68),

  /// M-card, for a child under 12.
  kidsMCard(69);

  const BelgianDocumentType(this.code);

  /// The code the identity file carries.
  final int code;

  /// The name of the type in [language], such as `B-kaart`.
  String label(BelgianLanguage language) {
    final own = switch (this) {
      eid => const [
          "Carte d'identité",
          'Identiteitskaart',
          'Personalausweis',
          'Identity card',
        ],
      kidsId => const ['Kids-ID', 'Kids-ID', 'Kids-ID', 'Kids ID'],
      bootstrap => const [
          'Carte bootstrap',
          'Bootstrapkaart',
          'Bootstrap-Karte',
          'Bootstrap card',
        ],
      habilitation => const [
          "Carte d'habilitation",
          'Machtigingskaart',
          'Berechtigungskarte',
          'Authorisation card',
        ],
      _ => null,
    };
    if (own != null) return own[language.index];

    final letter = _residenceLetter;
    final card = switch (language) {
      BelgianLanguage.fr => 'Carte $letter',
      BelgianLanguage.nl => '$letter-kaart',
      BelgianLanguage.de => '$letter-Karte',
      BelgianLanguage.en => '$letter card',
    };
    if (code > 60) {
      return '$card ${const [
        "(enfant de moins de 12 ans)",
        '(kind jonger dan 12 jaar)',
        '(Kind unter 12 Jahren)',
        '(child under 12)',
      ][language.index]}';
    }
    if (code >= 27 && code != 31 && code != 32) {
      return '$card ${const [
        '(format uniforme)',
        '(uniform model)',
        '(einheitliches Format)',
        '(uniform format)',
      ][language.index]}';
    }
    return card;
  }

  String get _residenceLetter {
    final name = this
        .name
        .replaceFirst('kids', '')
        .replaceFirst('UniformFormat', '')
        .replaceFirst('Card', '')
        .replaceFirst('Plus', '+');
    return name.startsWith('eu')
        ? 'EU${name.substring(2)}'
        : name.toUpperCase();
  }

  /// The type coded [code], or null if unknown.
  static BelgianDocumentType? fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}
