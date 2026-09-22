import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/media_importer.dart';
import 'package:gaming_memories/sources/playstation_media.dart';

void main() {
  final cases = <({String name, String? date, bool duplicate})>[
    (
      name: 'Ghost of Tsushima_20260831083523',
      date: '2026-08-31_08-35-23',
      duplicate: false,
    ),
    (
      name: 'Ghost of Tsushima_20260831083523_1',
      date: '2026-08-31_08-35-23',
      duplicate: true,
    ),
    (
      name: 'Ghost of Tsushima_20260831083523_12',
      date: '2026-08-31_08-35-23',
      duplicate: true,
    ),
    (
      name: 'Clair Obscur_ Expedition 33_20250603200610_1',
      date: '2025-06-03_20-06-10',
      duplicate: true,
    ),
    (
      name: 'SPACE RUN_2024081217012400',
      date: '2024-08-12_17-01-24',
      duplicate: false,
    ),
    (
      name: 'SPACE RUN_2024081217012400_1',
      date: '2024-08-12_17-01-24',
      duplicate: true,
    ),
    (
      name: 'Diablo 4_20260831083523',
      date: '2026-08-31_08-35-23',
      duplicate: false,
    ),
    (name: '20260831083523', date: '2026-08-31_08-35-23', duplicate: false),
    (name: '20260831083523_1', date: '2026-08-31_08-35-23', duplicate: true),
    (name: 'Main Menu', date: null, duplicate: false),
    (name: 'Game_2026083108', date: null, duplicate: false),
    (name: 'Game_99999999999999', date: null, duplicate: false),
    (name: 'Main Menu_1', date: null, duplicate: false),
  ];

  for (final testCase in cases) {
    test('parses ${testCase.name}', () {
      final result = parsePlayStationTimestamp(testCase.name);

      if (testCase.date == null) {
        expect(result, isNull);
      } else {
        expect(result, isNotNull);
        expect(formatDate(result!.capturedAt), testCase.date);
        expect(result.duplicate, testCase.duplicate);
      }
    });
  }
}
