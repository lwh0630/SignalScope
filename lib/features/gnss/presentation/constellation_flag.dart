import '../../../data/models/gnss_info.dart';

/// The nation (or organisation) that operates a GNSS constellation, shown as
/// a flag emoji in front of the constellation name.
///
/// SBAS is not one system but several regional augmentation services (WAAS,
/// EGNOS, MSAS, GAGAN, ...), so it gets a neutral globe instead of a flag.
class ConstellationFlag {
  const ConstellationFlag(this.emoji, this.countryKey);

  final String emoji;

  /// i18n key of the operator's name.
  final String countryKey;

  /// Flag emoji from an ISO 3166-1 alpha-2 code: two regional indicator symbols.
  static String fromIso(String alpha2) {
    final up = alpha2.toUpperCase();
    assert(up.length == 2);
    return String.fromCharCodes(up.codeUnits.map((c) => 0x1F1E6 + (c - 0x41)));
  }

  static final ConstellationFlag gps = ConstellationFlag(
    fromIso('US'),
    'gnss.country.us',
  );
  static final ConstellationFlag glonass = ConstellationFlag(
    fromIso('RU'),
    'gnss.country.ru',
  );
  static final ConstellationFlag beidou = ConstellationFlag(
    fromIso('CN'),
    'gnss.country.cn',
  );
  // The European Union flag has its own regional code.
  static final ConstellationFlag galileo = ConstellationFlag(
    fromIso('EU'),
    'gnss.country.eu',
  );
  static final ConstellationFlag qzss = ConstellationFlag(
    fromIso('JP'),
    'gnss.country.jp',
  );
  static final ConstellationFlag irnss = ConstellationFlag(
    fromIso('IN'),
    'gnss.country.in',
  );
  static const ConstellationFlag sbas = ConstellationFlag(
    '\u{1F310}',
    'gnss.country.multi',
  );
  static const ConstellationFlag unknown = ConstellationFlag(
    '\u{1F6F0}',
    'gnss.country.unknown',
  );

  static ConstellationFlag of(Constellation c) {
    switch (c) {
      case Constellation.gps:
        return gps;
      case Constellation.glonass:
        return glonass;
      case Constellation.beidou:
        return beidou;
      case Constellation.galileo:
        return galileo;
      case Constellation.qzss:
        return qzss;
      case Constellation.irnss:
        return irnss;
      case Constellation.sbas:
        return sbas;
      case Constellation.unknown:
        return unknown;
    }
  }
}
