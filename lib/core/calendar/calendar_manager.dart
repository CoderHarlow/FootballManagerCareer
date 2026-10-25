import 'package:sqlite3/sqlite3.dart';
import '../engine/competition_engine.dart';
import '../engine/models/competition.dart';
import 'calendar_models.dart';
import 'fixture_scheduler.dart';

class CalendarManager {
  final CompetitionEngine engine;
  final FixtureScheduler scheduler;

  CalendarManager({CompetitionEngine? engine, FixtureScheduler? scheduler})
      : engine = engine ?? CompetitionEngine(),
        scheduler = scheduler ?? FixtureScheduler();

  /// Reads current in-game calendar date from the active career save.
  DateTime getCurrentDate(Database saveDb) {
    final row = saveDb.select('SELECT current_calendar_date FROM career_saves LIMIT 1;').first;
    return DateTime.parse(row['current_calendar_date'] as String);
  }

  /// Returns the ID of the current active season in progress.
  String getActiveSeasonId(Database saveDb) {
    final rows = saveDb.select(
      "SELECT id FROM career_seasons WHERE status = 'IN_PROGRESS' ORDER BY season_year DESC LIMIT 1;",
    );
    if (rows.isNotEmpty) return rows.first['id'] as String;
    return saveDb.select('SELECT id FROM career_seasons ORDER BY season_year DESC LIMIT 1;').first['id'] as String;
  }

  /// Retrieves fixtures scheduled for today in the active season.
  List<Fixture> getTodaysFixtures(Database saveDb) {
    final date = getCurrentDate(saveDb);
    final seasonId = getActiveSeasonId(saveDb);
    return scheduler.getFixturesForDate(saveDb, seasonId, date);
  }

  /// Retrieves fixtures scheduled for any given date in the active season.
  List<Fixture> getFixturesForDate(Database saveDb, DateTime date) {
    final seasonId = getActiveSeasonId(saveDb);
    return scheduler.getFixturesForDate(saveDb, seasonId, date);
  }

  /// Retrieves full summary of total, completed, and upcoming fixtures for a season.
  SeasonSummary getSeasonSummary(Database saveDb, [String? seasonId]) {
    final targetSeasonId = seasonId ?? getActiveSeasonId(saveDb);
    return scheduler.getSeasonSummary(saveDb, targetSeasonId);
  }

  /// Advances the career calendar by exactly one day.
  /// If [simulateMatches] is true, any matches scheduled for today are simulated,
  /// standings are recalculated, knockout progressions advanced, and any date conflicts resolved.
  CalendarDayResult advanceOneDay({
    required Database saveDb,
    required Database worldDb,
    bool simulateMatches = true,
  }) {
    final currentDate = getCurrentDate(saveDb);
    final seasonId = getActiveSeasonId(saveDb);

    final todaysFixtures = scheduler.getFixturesForDate(saveDb, seasonId, currentDate);
    final playedFixtures = <Fixture>[];

    if (simulateMatches && todaysFixtures.isNotEmpty) {
      final stages = _loadStages(worldDb);
      final rules = _loadRules(worldDb);
      final reputations = _loadTeamReputations(worldDb);

      for (final fixture in todaysFixtures) {
        if (fixture.status != FixtureStatus.scheduled) continue;

        final stage = stages[fixture.stageId]!;
        final rule = rules[fixture.stageId]!;
        final homeRep = reputations[fixture.homeTeamId] ?? 50;
        final awayRep = reputations[fixture.awayTeamId] ?? 50;

        if (fixture.isLeg2) {
          final leg1Rows = saveDb.select(
            '''
            SELECT * FROM fixtures
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
            final leg1 = Fixture.fromMap(leg1Rows.first);
            engine.matchSimulator.simulateSecondLeg(
              fixture,
              leg1,
              homeReputation: homeRep,
              awayReputation: awayRep,
              rules: rule.matchRules,
            );
          } else {
            engine.matchSimulator.simulateMatch(
              fixture,
              homeReputation: homeRep,
              awayReputation: awayRep,
              rules: rule.matchRules,
            );
          }
        } else if (stage.formatType == FormatType.twoLeggedTie) {
          engine.matchSimulator.simulateMatch(
            fixture,
            homeReputation: homeRep,
            awayReputation: awayRep,
            rules: rule.matchRules.copyWith(extraTime: false, penalties: false),
          );
        } else {
          engine.matchSimulator.simulateMatch(
            fixture,
            homeReputation: homeRep,
            awayReputation: awayRep,
            rules: rule.matchRules,
          );
        }

        saveDb.execute(
          '''
          UPDATE fixtures
          SET home_score = ?, away_score = ?, home_extra_score = ?, away_extra_score = ?,
              home_pk_score = ?, away_pk_score = ?, status = ?
          WHERE id = ?;
          ''',
          [
            fixture.homeScore,
            fixture.awayScore,
            fixture.homeExtraScore,
            fixture.awayExtraScore,
            fixture.homePkScore,
            fixture.awayPkScore,
            fixture.status.toDbString(),
            fixture.id,
          ],
        );

        playedFixtures.add(fixture);
      }

      // Update standings and trigger stage progressions
      engine.updateStandingsAndProgression(
        saveDb: saveDb,
        seasonId: seasonId,
        stages: stages,
        rules: rules,
      );
    }

    // Advance calendar by 1 day
    final nextDate = currentDate.add(const Duration(days: 1));
    saveDb.execute(
      'UPDATE career_saves SET current_calendar_date = ?;',
      [nextDate.toIso8601String().split('T').first],
    );

    // Resolve any newly scheduled conflicts
    final resolvedConflicts = scheduler.resolveConflicts(saveDb, seasonId);

    // Check if season is complete
    final summary = scheduler.getSeasonSummary(saveDb, seasonId);

    return CalendarDayResult(
      date: currentDate,
      nextDate: nextDate,
      playedFixtures: playedFixtures,
      conflictsResolved: resolvedConflicts,
      seasonCompleted: summary.isFullyCompleted,
    );
  }

  /// Advances the calendar by a specified number of days sequentially.
  List<CalendarDayResult> advanceDays({
    required Database saveDb,
    required Database worldDb,
    required int days,
    bool simulateMatches = true,
  }) {
    final results = <CalendarDayResult>[];
    for (int i = 0; i < days; i++) {
      final res = advanceOneDay(
        saveDb: saveDb,
        worldDb: worldDb,
        simulateMatches: simulateMatches,
      );
      results.add(res);
      if (res.seasonCompleted) break;
    }
    return results;
  }

  /// Closes the current season and starts the next season cleanly,
  /// preserving previous season records and scheduling the new year.
  void startNextSeason({
    required Database saveDb,
    required Database worldDb,
    required int nextSeasonYear,
    DateTime? nextSeasonStartDate,
  }) {
    final currentSeasonId = getActiveSeasonId(saveDb);
    final currentDateStr = getCurrentDate(saveDb).toIso8601String().split('T').first;

    // 1. Mark current season completed
    saveDb.execute(
      "UPDATE career_seasons SET status = 'COMPLETED', end_date = ? WHERE id = ?;",
      [currentDateStr, currentSeasonId],
    );

    // 2. Determine saveId
    final saveRow = saveDb.select('SELECT id FROM career_saves LIMIT 1;').first;
    final saveId = saveRow['id'] as String;

    // 3. Create next season record
    final newSeasonId = '${saveId}_season_$nextSeasonYear';
    final seasonStart = nextSeasonStartDate ?? DateTime(nextSeasonYear, 8, 15);
    final seasonStartStr = seasonStart.toIso8601String().split('T').first;
    final seasonEndStr = DateTime(nextSeasonYear + 1, 5, 31).toIso8601String().split('T').first;

    saveDb.execute(
      '''
      INSERT INTO career_seasons (id, save_id, season_year, start_date, end_date, status)
      VALUES (?, ?, ?, ?, ?, 'IN_PROGRESS');
      ''',
      [newSeasonId, saveId, nextSeasonYear, seasonStartStr, seasonEndStr],
    );

    // 4. Register competitions for the new season
    final compRows = worldDb.select('SELECT id FROM competitions;');
    for (final c in compRows) {
      final compId = c['id'] as String;
      final seasonCompId = '${newSeasonId}_$compId';

      final stageRows = worldDb.select(
        'SELECT id FROM competition_stages WHERE competition_id = ? ORDER BY stage_order ASC LIMIT 1;',
        [compId],
      );
      if (stageRows.isEmpty) continue;
      final firstStageId = stageRows.first['id'] as String;

      saveDb.execute(
        '''
        INSERT INTO season_competitions (id, season_id, competition_id, current_stage_id, status)
        VALUES (?, ?, ?, ?, 'ACTIVE');
        ''',
        [seasonCompId, newSeasonId, compId, firstStageId],
      );

      // Copy default participants as frozen snapshot
      final partRows = worldDb.select(
        'SELECT team_id, seed, group_index FROM default_participants WHERE stage_id = ?;',
        [firstStageId],
      );
      for (final p in partRows) {
        saveDb.execute(
          '''
          INSERT INTO season_participants (season_competition_id, stage_id, team_id, group_index, seed)
          VALUES (?, ?, ?, ?, ?);
          ''',
          [seasonCompId, firstStageId, p['team_id'], p['group_index'], p['seed']],
        );
      }
    }

    // 5. Generate initial fixtures in Save DB
    final stages = _loadStages(worldDb);
    final rules = _loadRules(worldDb);
    final stageParticipants = _loadParticipants(saveDb, newSeasonId);

    engine.initializeSeasonFixtures(
      saveDb: saveDb,
      seasonId: newSeasonId,
      seasonStartDate: seasonStart,
      stageParticipants: stageParticipants,
      stages: stages,
      rules: rules,
    );

    // 6. Resolve any initial date clashes across competitions
    scheduler.resolveConflicts(saveDb, newSeasonId);

    // 7. Update current calendar date to new season start
    saveDb.execute(
      'UPDATE career_saves SET current_calendar_date = ?;',
      [seasonStartStr],
    );
  }

  Map<String, CompetitionStage> _loadStages(Database db) {
    final rows = db.select('SELECT * FROM competition_stages;');
    return {for (final r in rows) r['id'] as String: CompetitionStage.fromMap(r)};
  }

  Map<String, CompetitionRules> _loadRules(Database db) {
    final rows = db.select('SELECT * FROM competition_rules;');
    return {for (final r in rows) r['stage_id'] as String: CompetitionRules.fromMap(r)};
  }

  Map<String, int> _loadTeamReputations(Database db) {
    final rows = db.select('SELECT id, reputation FROM teams;');
    return {for (final r in rows) r['id'] as String: r['reputation'] as int? ?? 50};
  }

  Map<String, List<String>> _loadParticipants(Database saveDb, String seasonId) {
    final rows = saveDb.select(
      '''
      SELECT sp.stage_id, sp.team_id
      FROM season_participants sp
      JOIN season_competitions sc ON sp.season_competition_id = sc.id
      WHERE sc.season_id = ?;
      ''',
      [seasonId],
    );

    final Map<String, List<String>> map = {};
    for (final r in rows) {
      final stageId = r['stage_id'] as String;
      final teamId = r['team_id'] as String;
      map.putIfAbsent(stageId, () => []).add(teamId);
    }
    return map;
  }
}
