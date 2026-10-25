import '../engine/models/competition.dart';

class SchedulingConflict {
  final String teamId;
  final String fixtureId;
  final String conflictingFixtureId;
  final String originalDate;
  final String newDate;
  final String reason;

  const SchedulingConflict({
    required this.teamId,
    required this.fixtureId,
    required this.conflictingFixtureId,
    required this.originalDate,
    required this.newDate,
    required this.reason,
  });

  @override
  String toString() {
    return 'Conflict for team $teamId: fixture $fixtureId clashes on $originalDate. Rescheduled to $newDate ($reason)';
  }
}

class CalendarDayResult {
  final DateTime date;
  final DateTime nextDate;
  final List<Fixture> playedFixtures;
  final List<SchedulingConflict> conflictsResolved;
  final bool seasonCompleted;

  const CalendarDayResult({
    required this.date,
    required this.nextDate,
    required this.playedFixtures,
    this.conflictsResolved = const [],
    this.seasonCompleted = false,
  });
}

class SeasonSummary {
  final String seasonId;
  final int seasonYear;
  final String status;
  final String? startDate;
  final String? endDate;
  final int totalFixtures;
  final int completedFixtures;
  final int upcomingFixtures;
  final int postponedFixtures;

  const SeasonSummary({
    required this.seasonId,
    required this.seasonYear,
    required this.status,
    this.startDate,
    this.endDate,
    required this.totalFixtures,
    required this.completedFixtures,
    required this.upcomingFixtures,
    required this.postponedFixtures,
  });

  bool get isFullyCompleted => upcomingFixtures == 0 && totalFixtures > 0;
}
