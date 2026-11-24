/// Tablas de frecuencia del SDK (FrequencyUtils.indexGetFre / createFrequency).
///
/// El índice 3 es FCC 902.750–927.250 MHz, paso 0,5 MHz
/// ([EnumG.FrequencyRange_FCC902_928]). Colombia usa esa banda pero
/// solo los canales entre 915 y 928 MHz.
abstract final class FrequencyTables {
  static const int fccRangeIndex = 3;
  static const double colombiaMinMhz = 915;
  static const double colombiaMaxMhz = 928;

  static const double fccStartMhz = 902.75;
  static const double fccEndMhz = 927.25;
  static const double fccStepMhz = 0.5;

  /// Replica `FrequencyUtils.createFrequency` del reader.jar.
  static List<String> createFrequency(double start, double end, double step) {
    if (step <= 0) {
      throw ArgumentError.value(step, 'step');
    }
    final list = <String>[formatMhz(start)];
    var temp = start;
    var current = start;
    while (temp < end) {
      current += step;
      list.add(formatMhz(current));
      temp += step;
    }
    return list;
  }

  /// Replica `FrequencyUtils.indexGetFre`. Devuelve null si el índice no existe.
  static List<String>? indexGetFre(int index) {
    switch (index) {
      case 0:
        return createFrequency(920.625, 924.375, 0.25);
      case 1:
        return createFrequency(840.625, 844.375, 0.25);
      case 2:
        return [
          ...createFrequency(840.625, 844.375, 0.25),
          ...createFrequency(920.625, 924.375, 0.25),
        ];
      case 3:
        return createFrequency(fccStartMhz, fccEndMhz, fccStepMhz);
      case 4:
        return createFrequency(865.7, 868.1, 0.6);
      case 5:
        return createFrequency(916.8, 920.4, 1.2);
      case 6:
        return createFrequency(922.25, 927.75, 0.5);
      case 7:
        return createFrequency(923.125, 925.125, 0.25);
      case 8:
        return createFrequency(866.6, 867.4, 0.2);
      case 9:
        return createFrequency(802.75, 998.75, 1.0);
      default:
        return null;
    }
  }

  static List<String> get fccChannels =>
      List<String>.unmodifiable(indexGetFre(fccRangeIndex)!);

  /// Canales FCC dentro de 915–928 MHz (banda Colombia).
  static List<String> get colombiaChannels {
    return List<String>.unmodifiable(
      fccChannels.where((mhz) {
        final value = double.parse(mhz);
        return value >= colombiaMinMhz && value <= colombiaMaxMhz;
      }),
    );
  }

  /// Cursores (índices) de [colombiaChannels] dentro de la tabla FCC completa.
  /// Se envían en MsgBaseSetFrequency.listFreqCursor / freqIndexArray.
  static List<int> get colombiaFreqCursors {
    final all = fccChannels;
    return [
      for (final ch in colombiaChannels) all.indexOf(ch),
    ];
  }

  static String formatMhz(double mhz) => mhz.toStringAsFixed(3);
}
