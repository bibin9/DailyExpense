import 'dart:math';

import 'local_date.dart';

/// Source of "now". The app uses the device clock; tests inject fixed times.
/// Device clock accuracy is not guaranteed — the app records what the phone
/// says at the moment Save is tapped.
abstract interface class Clock {
  DateTime now();
}

class DeviceClock implements Clock {
  const DeviceClock();
  @override
  DateTime now() => DateTime.now();
}

/// The moment an expense was captured, frozen at Save.
///
/// The local date/time is computed once, from the device's offset at that
/// moment, and stored. Reports use [localDate], so travelling to another
/// timezone later never moves an old entry to a different day.
class CaptureStamp {
  const CaptureStamp({
    required this.instantUtcMs,
    required this.offsetMinutes,
    required this.timeZoneName,
    required this.localDate,
    required this.localTime,
  });

  /// Builds a stamp from a device-local [DateTime] (e.g. `DateTime.now()`).
  factory CaptureStamp.fromLocal(DateTime local) {
    final utc = local.toUtc();
    final offset = local.isUtc ? 0 : local.timeZoneOffset.inMinutes;
    return CaptureStamp.fromUtcAndOffset(
      utc.millisecondsSinceEpoch,
      offset,
      local.isUtc ? 'UTC' : local.timeZoneName,
    );
  }

  /// Builds a stamp from an instant and an explicit offset (used by tests to
  /// simulate devices in other timezones).
  factory CaptureStamp.fromUtcAndOffset(
    int instantUtcMs,
    int offsetMinutes,
    String timeZoneName,
  ) {
    final wall = DateTime.fromMillisecondsSinceEpoch(
      instantUtcMs,
      isUtc: true,
    ).add(Duration(minutes: offsetMinutes));
    String two(int v) => v.toString().padLeft(2, '0');
    return CaptureStamp(
      instantUtcMs: instantUtcMs,
      offsetMinutes: offsetMinutes,
      timeZoneName: timeZoneName,
      localDate: LocalDate(wall.year, wall.month, wall.day),
      localTime: '${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}',
    );
  }

  final int instantUtcMs;
  final int offsetMinutes;
  final String timeZoneName;
  final LocalDate localDate;

  /// `HH:mm:ss` wall-clock time at capture.
  final String localTime;

  int get hour => int.parse(localTime.substring(0, 2));
  int get minute => int.parse(localTime.substring(3, 5));

  /// "GMT+4", "GMT+5:30", "GMT-3"
  String get offsetLabel {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    return 'GMT$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
  }
}

/// "2:05 PM" / "14:05"
String formatClock(int hour, int minute, {required bool use24h}) {
  final mm = minute.toString().padLeft(2, '0');
  if (use24h) return '${hour.toString().padLeft(2, '0')}:$mm';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:$mm ${hour < 12 ? 'AM' : 'PM'}';
}

final Random _secureRandom = Random.secure();

/// Random (version 4) UUID from a cryptographically secure source.
String newUuid() {
  final b = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final h = List.generate(16, hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
