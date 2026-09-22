import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/capture_date.dart';

void main() {
  /// Every shape below was taken from a real library, and each expectation was
  /// checked against what the file system says about that file: the parse and
  /// the modification time agree to the minute, except where the capture was
  /// plainly copied in later.
  group('shapes a real library holds', () {
    test('the PC sources: dashes throughout', () {
      expect(
        capturedAtFromName('2026-09-19_17-54-32.jpg'),
        DateTime(2026, 9, 19, 17, 54, 32),
      );
    });

    test('a Nintendo Switch album: nothing between anything', () {
      expect(
        capturedAtFromName('2025061323152800_s.jpg'),
        DateTime(2025, 6, 13, 23, 15, 28),
      );
    });

    test('Android and emulators: one underscore', () {
      expect(
        capturedAtFromName('20231231_082312.png'),
        DateTime(2023, 12, 31, 8, 23, 12),
      );
    });

    test('World of Warcraft: a prefix before the date', () {
      expect(
        capturedAtFromName('WoWScrnShot_20180721_102457.jpg'),
        DateTime(2018, 7, 21, 10, 24, 57),
      );
    });

    test('Hytale: a prefix with no separator after it', () {
      expect(
        capturedAtFromName('Hytale2026-01-21_16-20-12.png'),
        DateTime(2026, 1, 21, 16, 20, 12),
      );
    });

    test('dots for the time', () {
      expect(
        capturedAtFromName('2020-11-12_23.48.21.png'),
        DateTime(2020, 11, 12, 23, 48, 21),
      );
    });

    test('underscores for the time, then microseconds', () {
      expect(
        capturedAtFromName('Screenshot_2020-12-18_13_49_30_756489.jpg'),
        DateTime(2020, 12, 18, 13, 49, 30),
      );
      expect(
        capturedAtFromName('2015-12-20_20_22_45.jpg'),
        DateTime(2015, 12, 20, 20, 22, 45),
      );
    });

    test('a space, and the word at', () {
      expect(
        capturedAtFromName('CleanShot 2025-09-30 at 17.51.10.png'),
        DateTime(2025, 9, 30, 17, 51, 10),
      );
      expect(
        capturedAtFromName('Screenshot2020-02-10 22_55_35.jpg'),
        DateTime(2020, 2, 10, 22, 55, 35),
      );
    });

    test('muOS: hours and minutes, then a counter', () {
      expect(
        capturedAtFromName('muOS_20241114_1857_0.png'),
        DateTime(2024, 11, 14, 18, 57),
      );
    });

    test('an emulator: a two-digit year at the end of the name', () {
      expect(
        capturedAtFromName('Chrono Trigger (U) [!]-250131-192902.png'),
        DateTime(2025, 1, 31, 19, 29, 2),
      );
    });

    test('a two-digit year with dashes, then milliseconds', () {
      expect(
        capturedAtFromName('ScreenShot_19-11-06_21-56-36-000.jpg'),
        DateTime(2019, 11, 6, 21, 56, 36),
      );
    });

    test('a date with a counter rather than a time', () {
      expect(
        capturedAtFromName('20230913_0001.png'),
        DateTime(2023, 9, 13, 0, 1),
      );
    });

    test('Warcraft III puts the month first', () {
      // The digits alone cannot say which order this is. The file sits in a
      // Reforged folder and was written on 9 February 2020, so month first it
      // is, rather than 20 September 2002.
      expect(
        capturedAtFromName('WC3ScrnShot_020920_201603_001.png'),
        DateTime(2020, 2, 9, 20, 16, 3),
      );
    });

    test('a time that lost a digit still dates the capture', () {
      // World of Warcraft writes a few of these. The day is certain even
      // where the seconds are not.
      final parsed = capturedAtFromName('WoWScrnShot_20180507_09349.jpg');

      expect(parsed?.year, 2018);
      expect(parsed?.month, 5);
      expect(parsed?.day, 7);
    });
  });

  group('names that carry no date', () {
    test('a counter is not a date', () {
      // All three sit in a real library and none of them says when.
      expect(capturedAtFromName('chicory_screen_004.png'), isNull);
      expect(capturedAtFromName('Screenshot_9.png'), isNull);
      expect(capturedAtFromName('Undated_Main Menu.jpg'), isNull);
    });

    test('nothing to read', () {
      expect(capturedAtFromName('cover.png'), isNull);
      expect(capturedAtFromName(''), isNull);
    });

    test('a date needs a day as well as a month', () {
      expect(capturedAtFromName('2026-09.png'), isNull);
    });
  });

  group('digits that are not a moment', () {
    test('a long number is not a date', () {
      expect(capturedAtFromName('12345678_901234.png'), isNull);
    });

    test('an impossible month, day or hour is refused', () {
      expect(capturedAtFromName('20261301_000000.png'), isNull);
      expect(capturedAtFromName('20260132_000000.png'), isNull);
      expect(capturedAtFromName('20260229_000000.png'), isNull);
    });

    test('an impossible time leaves the date behind', () {
      // The day is still known even when what follows it is not a time.
      expect(capturedAtFromName('20260101_250000.png'), DateTime(2026, 1, 1));
    });

    test('a leap day is a real day', () {
      expect(
        capturedAtFromName('20240229_120000.png'),
        DateTime(2024, 2, 29, 12),
      );
    });

    test('one separator has to be used throughout', () {
      // 2025-0613 is not a date anybody writes, and reading it as one would
      // make a date out of any two numbers that happen to sit together.
      expect(capturedAtFromName('2025-0613_120000.png'), isNull);
    });
  });
}
