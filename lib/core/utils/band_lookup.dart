/// 3GPP channel-number lookup tables.
///
/// These are only used when Android does not report a band itself
/// (`CellIdentityLte.getBands()` is API 30+). The result is always flagged as
/// *derived* in the UI. A band is returned only when the channel number maps
/// to exactly one band; otherwise `null` is returned instead of a guess.
library;

class _LteBand {
  const _LteBand(this.band, this.fDlLowMhz, this.nOffsDl, this.nDlMax);
  final int band;
  final double fDlLowMhz;
  final int nOffsDl;
  final int nDlMax;
}

/// TS 36.101 table 5.7.3-1 (downlink).
const List<_LteBand> _lteBands = [
  _LteBand(1, 2110, 0, 599),
  _LteBand(2, 1930, 600, 1199),
  _LteBand(3, 1805, 1200, 1949),
  _LteBand(4, 2110, 1950, 2399),
  _LteBand(5, 869, 2400, 2649),
  _LteBand(7, 2620, 2750, 3449),
  _LteBand(8, 925, 3450, 3799),
  _LteBand(9, 1844.9, 3800, 4149),
  _LteBand(10, 2110, 4150, 4749),
  _LteBand(11, 1475.9, 4750, 4949),
  _LteBand(12, 729, 5010, 5179),
  _LteBand(13, 746, 5180, 5279),
  _LteBand(14, 758, 5280, 5379),
  _LteBand(17, 734, 5730, 5849),
  _LteBand(18, 860, 5850, 5999),
  _LteBand(19, 875, 6000, 6149),
  _LteBand(20, 791, 6150, 6449),
  _LteBand(21, 1495.9, 6450, 6599),
  _LteBand(22, 3510, 6600, 7399),
  _LteBand(23, 2180, 7500, 7699),
  _LteBand(24, 1525, 7700, 8039),
  _LteBand(25, 1930, 8040, 8689),
  _LteBand(26, 859, 8690, 9039),
  _LteBand(27, 852, 9040, 9209),
  _LteBand(28, 758, 9210, 9659),
  _LteBand(29, 717, 9660, 9769),
  _LteBand(30, 2350, 9770, 9869),
  _LteBand(31, 462.5, 9870, 9919),
  _LteBand(32, 1452, 9920, 10359),
  _LteBand(33, 1900, 36000, 36199),
  _LteBand(34, 2010, 36200, 36349),
  _LteBand(35, 1850, 36350, 36949),
  _LteBand(36, 1930, 36950, 37549),
  _LteBand(37, 1910, 37550, 37749),
  _LteBand(38, 2570, 37750, 38249),
  _LteBand(39, 1880, 38250, 38649),
  _LteBand(40, 2300, 38650, 39649),
  _LteBand(41, 2496, 39650, 41589),
  _LteBand(42, 3400, 41590, 43589),
  _LteBand(43, 3600, 43590, 45589),
  _LteBand(44, 703, 45590, 46589),
  _LteBand(45, 1447, 46590, 46789),
  _LteBand(46, 5150, 46790, 54539),
  _LteBand(47, 5855, 54540, 55239),
  _LteBand(48, 3550, 55240, 56739),
  _LteBand(49, 3550, 56740, 58239),
  _LteBand(50, 1432, 58240, 59089),
  _LteBand(51, 1427, 59090, 59139),
  _LteBand(52, 3300, 59140, 60139),
  _LteBand(53, 2483.5, 60140, 60254),
  _LteBand(65, 2110, 65536, 66435),
  _LteBand(66, 2110, 66436, 67335),
  _LteBand(67, 738, 67336, 67535),
  _LteBand(68, 753, 67536, 67835),
  _LteBand(69, 2570, 67836, 68335),
  _LteBand(70, 1995, 68336, 68585),
  _LteBand(71, 617, 68586, 68935),
  _LteBand(72, 461, 68936, 68985),
  _LteBand(73, 460, 68986, 69035),
  _LteBand(74, 1475, 69036, 69465),
  _LteBand(75, 1432, 69466, 70315),
  _LteBand(76, 1427, 70316, 70365),
  _LteBand(85, 728, 70366, 70545),
  _LteBand(87, 420, 70546, 70595),
  _LteBand(88, 422, 70596, 70645),
];

class _NrBand {
  const _NrBand(this.band, this.lowMhz, this.highMhz);
  final int band;
  final double lowMhz;
  final double highMhz;
}

/// TS 38.101-1 / 38.101-2 downlink ranges (frequency ranges overlap between
/// several bands, which is why NR bands are only derived when unique).
const List<_NrBand> _nrBands = [
  _NrBand(1, 2110, 2170),
  _NrBand(2, 1930, 1990),
  _NrBand(3, 1805, 1880),
  _NrBand(5, 869, 894),
  _NrBand(7, 2620, 2690),
  _NrBand(8, 925, 960),
  _NrBand(12, 729, 746),
  _NrBand(14, 758, 768),
  _NrBand(18, 860, 875),
  _NrBand(20, 791, 821),
  _NrBand(25, 1930, 1995),
  _NrBand(26, 859, 894),
  _NrBand(28, 758, 803),
  _NrBand(29, 717, 728),
  _NrBand(30, 2350, 2360),
  _NrBand(34, 2010, 2025),
  _NrBand(38, 2570, 2620),
  _NrBand(39, 1880, 1920),
  _NrBand(40, 2300, 2400),
  _NrBand(41, 2496, 2690),
  _NrBand(48, 3550, 3700),
  _NrBand(50, 1432, 1517),
  _NrBand(51, 1427, 1432),
  _NrBand(53, 2483.5, 2495),
  _NrBand(65, 2110, 2200),
  _NrBand(66, 2110, 2200),
  _NrBand(70, 1995, 2020),
  _NrBand(71, 617, 652),
  _NrBand(74, 1475, 1518),
  _NrBand(75, 1432, 1517),
  _NrBand(76, 1427, 1432),
  _NrBand(77, 3300, 4200),
  _NrBand(78, 3300, 3800),
  _NrBand(79, 4400, 5000),
  _NrBand(90, 2496, 2690),
  _NrBand(96, 5925, 7125),
  _NrBand(102, 5925, 6425),
  _NrBand(257, 26500, 29500),
  _NrBand(258, 24250, 27500),
  _NrBand(259, 39500, 43500),
  _NrBand(260, 37000, 40000),
  _NrBand(261, 27500, 28350),
];

class BandLookup {
  BandLookup._();

  /// Unique LTE band for a downlink EARFCN, or `null`.
  static int? lteBandFromEarfcn(int? earfcn) {
    if (earfcn == null) return null;
    int? found;
    for (final b in _lteBands) {
      final low = b.nOffsDl;
      if (earfcn >= low && earfcn <= b.nDlMax) {
        if (found != null) return null;
        found = b.band;
      }
    }
    return found;
  }

  /// Downlink centre frequency in MHz derived from an EARFCN
  /// (`F = F_DL_low + 0.1 * (N - N_offs)`), or `null` if the EARFCN is unknown.
  static double? lteDlFrequencyMhz(int? earfcn) {
    if (earfcn == null) return null;
    for (final b in _lteBands) {
      if (earfcn >= b.nOffsDl && earfcn <= b.nDlMax) {
        return b.fDlLowMhz + 0.1 * (earfcn - b.nOffsDl);
      }
    }
    return null;
  }

  /// NR-ARFCN to RF reference frequency in MHz (TS 38.104 table 5.4.2.1-1).
  static double? nrFrequencyMhz(int? nrarfcn) {
    if (nrarfcn == null || nrarfcn < 0) return null;
    if (nrarfcn <= 599999) return 0.005 * nrarfcn;
    if (nrarfcn <= 2016666) return 3000 + 0.015 * (nrarfcn - 600000);
    if (nrarfcn <= 3279165) return 24250.08 + 0.06 * (nrarfcn - 2016667);
    return null;
  }

  /// All NR bands whose downlink range contains the NR-ARFCN frequency.
  static List<int> nrBandCandidates(int? nrarfcn) {
    final f = nrFrequencyMhz(nrarfcn);
    if (f == null) return const [];
    return [
      for (final b in _nrBands)
        if (f >= b.lowMhz && f <= b.highMhz) b.band,
    ];
  }

  /// NR band only when exactly one band matches; `null` when ambiguous.
  static int? nrBandFromNrarfcn(int? nrarfcn) {
    final c = nrBandCandidates(nrarfcn);
    return c.length == 1 ? c.first : null;
  }
}
