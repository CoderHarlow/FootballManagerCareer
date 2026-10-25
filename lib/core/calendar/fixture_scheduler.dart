import 'package:sqlite3/sqlite3.dart';
import '../engine/models/competition.dart';
import 'calendar_models.dart';

class FixtureScheduler {
  /// Scans all scheduled fixtures for the season, detects team fixture clashes
  /// (same club playing on the same date or without minimum rest days), and
  /// reschedules conflicting fixtures to the earliest available valid date.
  /// Never deletes any fixture.
  List<SchedulingConflict> resolveConflicts(
    Database saveDb,
    String seasonId, {
    int defaultMinRestDays = 2,
  }) {
    final List<SchedulingConflict> conflicts = [];

    // Query all scheduled fixtures ordered chronologically
    final rows = saveDb.select(
      '''
      SELECT f.*
      FROM fixtures f
      JOIN season_competitions sc ON f.season_competition_id = sc.id
      WHERE sc.season_id = ? AND f.status = 'SCHEDULED'
      ORDER BY f.match_date ASC, f.round_number ASC, f.leg_number ASC;
      ''',
      [seasonId],
    );

    final List<Fixture> allFixtures = rows.map((r) => Fixture.fromMap(r)).toList();

    // Map of teamId -> sorted list of assigned match dates
    final Map<String, List<DateTime>> teamMatchDates = {};

    for (final fixture in allFixtures) {
      DateTime matchDate = DateTime.parse(fixture.matchDate);
      final homeId = fixture.homeTeamId;
      final awayId = fixture.awayTeamId;

      bool hasConflict = false;
      String conflictReason = '';
      String conflictingId = '';

      // Check conflict for Home Team
      final homeConflict = _findDateConflict(teamMatchDates[homeId], matchDate, defaultMinRestDays);
      if (homeConflict != null) {
        hasConflict = true;
        conflictingId = homeId;
        conflictReason = 'Home team $homeId has match near ${homeConflict.toIso8601String().split('T').first}';
      }

      // Check conflict for Away Team
      if (!hasConflict) {
        final awayConflict = _findDateConflict(teamMatchDates[awayId], matchDate, defaultMinRestDays);
        if (awayConflict != null) {
          hasConflict = true;
          conflictingId = awayId;
          conflictReason = 'Away team $awayId has match near ${awayConflict.toIso8601String().split('T').first}';
        }
      }

      // If fixture is Leg 2 of a two-legged tie, ensure it is after Leg 1
      if (fixture.isLeg2) {
        final leg1Rows = saveDb.select(
          '''
          SELECT match_date FROM fixtures
          WHERE season_competition_id = ? AND stage_id = ? AND round_number = ?
            AND home_team_id = ? AND away_team_id = ? AND leg_number = 1;
          ''',
          [
            fixture.seasonCompetitionId,
            fixture.stageId,
            fixture.roundNumber,
            fixture.awayTeamId,
            fixture.homeTeamId,
          ],
        );
        if (leg1Rows.isNotEmpty) {
          final leg1Date = DateTime.parse(leg1Rows.first['match_date'] as String);
          final minLeg2Date = leg1Date.add(Duration(days: defaultMinRestDays));
          if (matchDate.isBefore(minLeg2Date)) {
            hasConflict = true;
            conflictingId = homeId;
            conflictReason = 'Leg 2 cannot be played before or within $defaultMinRestDays days of Leg 1 (${leg1Date.toIso8601String().split('T').first})';
            matchDate = minLeg2Date;
          }
        }
      }

      if (hasConflict) {
        final originalDateStr = fixture.matchDate;

        // Find the earliest new date with >= defaultMinRestDays for both teams
        DateTime candidateDate = matchDate;
        if (candidateDate.toIso8601String().split('T').first == originalDateStr) {
          candidateDate = candidateDate.add(const Duration(days: 1));
        }
        while (_findDateConflict(teamMatchDates[homeId], candidateDate, defaultMinRestDays) != null ||
            _findDateConflict(teamMatchDates[awayId], candidateDate, defaultMinRestDays) != null) {
          candidateDate = candidateDate.add(const Duration(days: 1));
        }

        final newDateStr = candidateDate.toIso8601String().split('T').first;

        // Update database with the rescheduled date
        saveDb.execute(
          'UPDATE fixtures SET match_date = ? WHERE id = ?;',
          [newDateStr, fixture.id],
        );

        conflicts.add(SchedulingConflict(
          teamId: conflictingId,
          fixtureId: fixture.id,
          conflictingFixtureId: conflictingId,
          originalDate: originalDateStr,
          newDate: newDateStr,
          reason: conflictReason,
        ));

        matchDate = candidateDate;
      }

      // Record assigned match dates
      teamMatchDates.putIfAbsent(homeId, () => []).add(matchDate);
      teamMatchDates.putIfAbsent(awayId, () => []).add(matchDate);
    }

    return conflicts;
  }

  DateTime? _findDateConflict(List<DateTime>? assignedDates, DateTime date, int minRestDays) {
    if (assignedDates == null || assignedDates.isEmpty) return null;
    for (final d in assignedDates) {
      final diff = (d.difference(date).inDays).abs();
      if (diff < minRestDays) {
        return d;
      }
    }
    return null;
  }

  /// Retrieves all fixtures scheduled for a specific calendar date in the save.
  List<Fixture> getFixturesForDate(Database saveDb, String seasonId, DateTime date) {
    final dateStr = date.toIso8601String().split('T').first;
    final rows = saveDb.select(
      '''
      SELECT f.*
      FROM fixtures f
      JOIN season_competitions sc ON f.season_competition_id = sc.id
      WHERE sc.season_id = ? AND f.match_date = ?
      ORDER BY f.round_number ASC, f.leg_number ASC;
      ''',
      [seasonId, dateStr],
    );
    return rows.map((r) => Fixture.fromMap(r)).toList();
  }

  /// Calculates a full statistical summary of fixtures for the active season.
  SeasonSummary getSeasonSummary(Database saveDb, String seasonId) {
    final seasonRow = saveDb.select(
      'SELECT season_year, start_date, end_date, status FROM career_seasons WHERE id = ?;',
      [seasonId],
    ).first;

    final rows = saveDb.select(
      '''
      SELECT f.status, COUNT(*) as count
      FROM fixtures f
      JOIN season_competitions sc ON f.season_competition_id = sc.id
      WHERE sc.season_id = ?
      GROUP BY f.status;
      ''',
      [seasonId],
    );

    int total = 0;
    int completed = 0;
    int upcoming = 0;
    int postponed = 0;

    for (final r in rows) {
      final status = r['status'] as String;
      final count = r['count'] as int;
      total += count;
      if (status == 'PLAYED') {
        completed += count;
      } else if (status == 'SCHEDULED') {
        upcoming += count;
      } else if (status == 'POSTPONED') {
        postponed += count;
      }
    }

    return SeasonSummary(
      seasonId: seasonId,
      seasonYear: seasonRow['season_year'] as int,
      status: seasonRow['status'] as String,
      startDate: seasonRow['start_date'] as String?,
      endDate: seasonRow['end_date'] as String?,
      totalFixtures: total,
      completedFixtures: completed,
      upcomingFixtures: upcoming,
      postponedFixtures: postponed,
    );
  }
}
