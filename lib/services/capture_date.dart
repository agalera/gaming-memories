/// Reads the moment a capture was taken from its file name.
///
/// Every source names its files its own way, so this recognises a date rather
/// than a format: a year, month and day run, optionally followed by a time,
/// anywhere in the name and separated by whatever that source felt like using.
/// The library and the published gallery both read dates through here, because
/// a capture showing one date in the app and another on the site would be the
/// same capture twice.
///
/// Shapes seen in a real library, all of which this reads:
///
/// - `2026-09-19_17-54-32.jpg` — the PC sources
/// - `2025061323152800_s.jpg` — a Nintendo Switch album
/// - `20231231_082312.png` — Android and several emulators
/// - `WoWScrnShot_20180721_102457.jpg` — World of Warcraft
/// - `Hytale2026-01-21_16-20-12.png` — Hytale
/// - `2020-11-12_23.48.21.png` — dots for the time
/// - `Screenshot_2020-12-18_13_49_30_756489.jpg` — underscores, then micros
/// - `CleanShot 2025-09-30 at 17.51.10.png` — spaces and the word `at`
/// - `muOS_20241114_1857_0.png` — hours and minutes, then a counter
/// - `Chrono Trigger (U) [!]-250131-192902.png` — a two-digit year
/// - `ScreenShot_19-11-06_21-56-36-000.jpg` — two-digit year with dashes
library;

/// Warcraft III writes month, day, year, which no amount of looking at the
/// digits can tell apart from the year-first form every other source uses.
/// `WC3ScrnShot_020920_195849_001.png` sits in a Reforged folder and was last
/// written on 9 February 2020, so it is `MMDDYY` rather than 20 September
/// 2002, and it needs naming before the general reading gets to it.
final _warcraftThree = RegExp(
  r'^WC3ScrnShot_(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})',
);

/// A year, month and day. The separator is captured so that the same one has
/// to appear twice: `2025-0613` is not a date anybody writes.
///
/// The lookbehind keeps a match from starting part way through a longer run of
/// digits, so `2025061323152800` reads as one date and time rather than as
/// several overlapping ones.
final _datePatterns = [
  RegExp(r'(?<![0-9])(\d{4})([-_.]?)(\d{2})\2(\d{2})'),
  RegExp(r'(?<![0-9])(\d{2})([-_.])(\d{2})\2(\d{2})(?=[-_. ])'),
  // A bare two-digit year only counts when something follows it, or every
  // six-digit number in a name would be a date. The empty group keeps the
  // year, month and day in the same places as the patterns above.
  RegExp(r'(?<![0-9])(\d{2})()(\d{2})(\d{2})(?=[-_. ])'),
];

/// The time after a date: hours and minutes, and seconds when they are there.
/// The leading separator is whatever came between them, including the `at`
/// that a screenshot tool writes out in words.
final _timePattern = RegExp(
  r'^(?:[ _T-]|\sat\s)?(\d{2})([-_.:]?)(\d{2})(?:\2(\d{2}))?',
);

/// The date and time [fileName] carries, or null when it carries none.
DateTime? capturedAtFromName(String fileName) {
  final named = _warcraftThree.firstMatch(fileName);
  if (named != null) {
    final date = _build(
      year: 2000 + int.parse(named.group(3)!),
      month: int.parse(named.group(1)!),
      day: int.parse(named.group(2)!),
      hour: int.parse(named.group(4)!),
      minute: int.parse(named.group(5)!),
      second: int.parse(named.group(6)!),
    );
    if (date != null) {
      return date;
    }
  }

  for (final pattern in _datePatterns) {
    for (final match in pattern.allMatches(fileName)) {
      final digits = match.group(1)!;
      final date = _read(
        fileName,
        year: digits.length == 4 ? int.parse(digits) : 2000 + int.parse(digits),
        month: int.parse(match.group(3)!),
        day: int.parse(match.group(4)!),
        after: match.end,
      );
      if (date != null) {
        return date;
      }
    }
  }
  return null;
}

/// Builds the moment from a date and whatever time follows it in the name. A
/// name that carries only a date is still worth reading: the day is right even
/// when the hour is unknown.
DateTime? _read(
  String fileName, {
  required int year,
  required int month,
  required int day,
  required int after,
}) {
  if (_build(year: year, month: month, day: day) == null) {
    return null;
  }

  final time = _timePattern.firstMatch(fileName.substring(after));
  if (time != null) {
    final withTime = _build(
      year: year,
      month: month,
      day: day,
      hour: int.parse(time.group(1)!),
      minute: int.parse(time.group(3)!),
      second: int.parse(time.group(4) ?? '0'),
    );
    if (withTime != null) {
      return withTime;
    }
  }

  return _build(year: year, month: month, day: day);
}

/// A moment, or null when those numbers are not one.
///
/// A name that merely holds digits is not a date, so the parts have to be
/// real: `12345678_901234.png` would otherwise roll over into a year of its
/// own, and so would 31 February.
DateTime? _build({
  required int year,
  required int month,
  required int day,
  int hour = 0,
  int minute = 0,
  int second = 0,
}) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }

  final date = DateTime(year, month, day, hour, minute, second);
  return date.month == month && date.day == day ? date : null;
}
