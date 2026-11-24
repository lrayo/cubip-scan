import 'package:cubip_scan/rfid/frequency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el índice 3 es FCC 902.750–927.250 con paso 0.5', () {
    final fcc = FrequencyTables.indexGetFre(3)!;
    expect(FrequencyTables.fccRangeIndex, 3);
    expect(fcc.first, '902.750');
    expect(fcc.last, '927.250');
    expect(fcc.length, 50);
    expect(fcc[1], '903.250');
  });

  test('Colombia limita la tabla FCC a 915–928 MHz', () {
    final colombia = FrequencyTables.colombiaChannels;
    expect(double.parse(colombia.first), greaterThanOrEqualTo(915));
    expect(double.parse(colombia.last), lessThanOrEqualTo(928));
    expect(colombia, contains('915.250'));
    expect(colombia, contains('927.250'));
    expect(colombia, isNot(contains('914.750')));
    expect(colombia, isNot(contains('902.750')));
    expect(FrequencyTables.colombiaFreqCursors.first, 25);
    expect(FrequencyTables.colombiaFreqCursors.last, 49);
    expect(FrequencyTables.colombiaFreqCursors.length, colombia.length);
    expect(colombia.length, 25);
  });

  test('createFrequency coincide con el bucle del SDK', () {
    expect(
      FrequencyTables.createFrequency(865.7, 868.1, 0.6),
      ['865.700', '866.300', '866.900', '867.500', '868.100'],
    );
  });
}
