class PlayStationTimestamp {
  const PlayStationTimestamp({
    required this.capturedAt,
    required this.duplicate,
  });

  final DateTime capturedAt;
  final bool duplicate;
}

const playStationUndatedFolder = 'Other';
const playStationUndatedPrefix = 'Undated_';

PlayStationTimestamp? parsePlayStationTimestamp(String name) {
  final counter = RegExp(r'_(\d+)$').firstMatch(name);
  if (counter != null) {
    final capturedAt = _parseTrailingTimestamp(
      name.substring(0, counter.start),
    );
    if (capturedAt != null) {
      return PlayStationTimestamp(capturedAt: capturedAt, duplicate: true);
    }
  }

  final capturedAt = _parseTrailingTimestamp(name);
  return capturedAt == null
      ? null
      : PlayStationTimestamp(capturedAt: capturedAt, duplicate: false);
}

DateTime? _parseTrailingTimestamp(String name) {
  final match = RegExp(r'(\d+)$').firstMatch(name);
  if (match == null || match.group(1)!.length < 14) {
    return null;
  }

  final value = match.group(1)!.substring(0, 14);
  final parts = <int>[
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(4, 6)),
    int.parse(value.substring(6, 8)),
    int.parse(value.substring(8, 10)),
    int.parse(value.substring(10, 12)),
    int.parse(value.substring(12, 14)),
  ];
  final capturedAt = DateTime(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (capturedAt.year != parts[0] ||
      capturedAt.month != parts[1] ||
      capturedAt.day != parts[2] ||
      capturedAt.hour != parts[3] ||
      capturedAt.minute != parts[4] ||
      capturedAt.second != parts[5]) {
    return null;
  }
  return capturedAt;
}
