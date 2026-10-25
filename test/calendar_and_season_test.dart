import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/calendar/calendar_manager.dart';
import 'package:football_manager_career/core/calendar/fixture_scheduler.dart';
import 'package:football_manager_career/core/database/database_validator.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';
import 'package:football_manager_career/core/engine/models/competition.dart';

void main() {
  group('Phase 4 — Football Calendar & Season System Tests', () {
    late Database worldDb;
    late Database saveDb;
    late CareerManager careerManager;
    late CalendarManager calendarManager;
    late FixtureScheduler fixtureScheduler;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      careerManager = CareerManager();
      calendarManager = CalendarManager();
      fixtureScheduler = FixtureScheduler();

      // Setup 4 clubs & teams
      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Club Alpha', 'ALP', 'ENG'),
          ('c2', 'Club Beta', 'BET', 'ENG'),
          ('c3', 'Club Gamma', 'GAM', 'ENG'),
          ('c4', 'Club Delta', 'DEL', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Alpha Team', 'ALP', 'SENIOR', 80),
          ('t2', 'c2', 'Beta Team', 'BET', 'SENIOR', 75),
          ('t3', 'c3', 'Gamma Team', 'GAM', 'SENIOR', 70),
          ('t4', 'c4', 'Delta Team', 'DEL', 'SENIOR', 65);

        -- Competition 1: Domestic League (4 teams, round robin, 2 legs = 6 matchdays)
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('league_base', 'BASE', 'Base League', 'Base', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_league', 'league_base', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, scheduling_rules_json
        ) VALUES (
          'stage_league', 4, 2, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": false, "penalties": false}',
          '{"match_interval_days": 7, "min_rest_days": 2, "preferred_match_day": 6}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_league', 't1', 1),
          ('stage_league', 't2', 2),
          ('stage_league', 't3', 3),
          ('stage_league', 't4', 4);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
    });

    test('1. Advancing the career date by one day', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_advance',
        saveName: 'Advance Test',
        userTeamId: 't1',
        startYear: 2026,
      );

      final initialDate = calendarManager.getCurrentDate(saveDb);
      expect(initialDate, equals(DateTime(2026, 8, 1)));

      // Advance 1 day
      final result1 = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(result1.date, equals(DateTime(2026, 8, 1)));
      expect(result1.nextDate, equals(DateTime(2026, 8, 2)));
      expect(calendarManager.getCurrentDate(saveDb), equals(DateTime(2026, 8, 2)));

      // Advance another day
      final result2 = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(result2.date, equals(DateTime(2026, 8, 2)));
      expect(result2.nextDate, equals(DateTime(2026, 8, 3)));
      expect(calendarManager.getCurrentDate(saveDb), equals(DateTime(2026, 8, 3)));
    });

    test('2. Finding fixtures scheduled for the current date', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_fixtures_date',
        saveName: 'Date Fixtures Test',
        userTeamId: 't1',
        startYear: 2026,
      );

      // On 2026-08-01, there should be no matches scheduled
      final fixturesEarly = calendarManager.getTodaysFixtures(saveDb);
      expect(fixturesEarly, isEmpty);

      // Set career date to season start date (2026-08-15) where Round 1 matches are scheduled
      saveDb.execute("UPDATE career_saves SET current_calendar_date = '2026-08-15';");

      final todayFixtures = calendarManager.getTodaysFixtures(saveDb);
      expect(todayFixtures.length, equals(2)); // 4 teams = 2 matches per round
      for (final f in todayFixtures) {
        expect(f.matchDate, equals('2026-08-15'));
        expect(f.status, equals(FixtureStatus.scheduled));
      }

      // Check a date with no matches
      final emptyFixtures = calendarManager.getFixturesForDate(saveDb, DateTime(2026, 8, 16));
      expect(emptyFixtures, isEmpty);
    });

    test('3. Scheduling multiple competitions in one season', () {
      // Add a second competition: Knockout Cup
      worldDb.execute('''
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('cup_domestic', 'CUP', 'Domestic Cup', 'Cup', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_cup', 'cup_domestic', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, scheduling_rules_json
        ) VALUES (
          'stage_cup', 4, 1, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true}',
          '{"match_interval_days": 14, "min_rest_days": 2}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_cup', 't1', 1),
          ('stage_cup', 't2', 2),
          ('stage_cup', 't3', 3),
          ('stage_cup', 't4', 4);
      ''');

      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_multi_comp',
        saveName: 'Multi Comp Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      final seasonId = 'save_multi_comp_season_2026';
      final activeComps = saveDb.select(
        'SELECT competition_id FROM season_competitions WHERE season_id = ?;',
        [seasonId],
      );
      final compIds = activeComps.map((r) => r['competition_id'] as String).toSet();
      expect(compIds, containsAll(['league_base', 'cup_domestic']));

      // League has 12 fixtures (4 teams, double round-robin = 12 matches)
      final leagueFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'league_base';
        ''',
      );
      expect(leagueFixtures.length, equals(12));

      // Cup initial round has 2 fixtures (4 teams single elimination SF)
      final cupFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'cup_domestic';
        ''',
      );
      expect(cupFixtures.length, equals(2));

      // Save database validation must detect 0 duplicate fixtures
      final validation = DatabaseValidator.validateSaveDatabase(saveDb);
      expect(validation.isValid, isTrue, reason: validation.errors.toString());
    });

    test('4. Preventing same-club, same-date fixture clashes without deleting fixtures', () {
      // Setup both league and cup with the exact same initial match date for t1
      worldDb.execute('''
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('cup_clash', 'CUP2', 'Clash Cup', 'Cup2', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_cup_clash', 'cup_clash', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, scheduling_rules_json
        ) VALUES (
          'stage_cup_clash', 4, 1, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true}',
          '{"match_interval_days": 7, "min_rest_days": 2}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_cup_clash', 't1', 1),
          ('stage_cup_clash', 't2', 2),
          ('stage_cup_clash', 't3', 3),
          ('stage_cup_clash', 't4', 4);
      ''');

      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_clash',
        saveName: 'Clash Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      final seasonId = 'save_clash_season_2026';
      final totalFixturesBefore = saveDb.select('SELECT COUNT(*) as count FROM fixtures;').first['count'] as int;

      // Forcefully inject a clash by setting a cup fixture to the exact same date as a league fixture
      final leagueDate = saveDb.select(
        '''
        SELECT f.match_date FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'league_base' AND (f.home_team_id = 't1' OR f.away_team_id = 't1')
        LIMIT 1;
        ''',
      ).first['match_date'] as String;

      final cupFixtureId = saveDb.select(
        '''
        SELECT f.id FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'cup_clash' AND (f.home_team_id = 't1' OR f.away_team_id = 't1')
        LIMIT 1;
        ''',
      ).first['id'] as String;

      saveDb.execute('UPDATE fixtures SET match_date = ? WHERE id = ?;', [leagueDate, cupFixtureId]);

      // Verify that validator detects this deliberate clash
      final preCheck = DatabaseValidator.validateSaveDatabase(saveDb);
      expect(preCheck.isValid, isFalse);
      expect(preCheck.errors.any((e) => e.code == 'SAME_DATE_FIXTURE_CLASH'), isTrue);

      // Run conflict resolver
      final conflicts = fixtureScheduler.resolveConflicts(saveDb, seasonId, defaultMinRestDays: 2);
      expect(conflicts.isNotEmpty, isTrue);

      // Verify NO fixtures were silently deleted
      final totalFixturesAfter = saveDb.select('SELECT COUNT(*) as count FROM fixtures;').first['count'] as int;
      expect(totalFixturesAfter, equals(totalFixturesBefore));

      // Verify that after resolution, save DB is completely clean of clashes
      final postCheck = DatabaseValidator.validateSaveDatabase(saveDb);
      expect(postCheck.isValid, isTrue, reason: postCheck.errors.toString());

      // Verify t1 has at least minRestDays between matches
      final t1Rows = saveDb.select(
        '''
        SELECT match_date FROM fixtures
        WHERE home_team_id = 't1' OR away_team_id = 't1'
        ORDER BY match_date ASC;
        ''',
      );
      final t1Dates = t1Rows.map((r) => DateTime.parse(r['match_date'] as String)).toList();
      for (int i = 0; i < t1Dates.length - 1; i++) {
        final diff = t1Dates[i + 1].difference(t1Dates[i]).inDays;
        expect(diff, greaterThanOrEqualTo(2), reason: 'Matches on ${t1Dates[i]} and ${t1Dates[i + 1]} violate min rest days');
      }
    });

    test('5. Scheduling both legs of two-legged ties with correct sequence and interval', () {
      worldDb.execute('''
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('cup_two_leg', 'TLG', 'Two Legged Tie Cup', 'TLG', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_two_leg', 'cup_two_leg', 1, 'TWO_LEGGED_TIE');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, scheduling_rules_json
        ) VALUES (
          'stage_two_leg', 4, 2, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true, "away_goals": true}',
          '{"match_interval_days": 7, "min_rest_days": 3}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_two_leg', 't1', 1),
          ('stage_two_leg', 't2', 2),
          ('stage_two_leg', 't3', 3),
          ('stage_two_leg', 't4', 4);
      ''');

      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_two_leg',
        saveName: 'Two Leg Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      final fixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'cup_two_leg'
        ORDER BY f.round_number ASC, f.leg_number ASC;
        ''',
      );

      // 4 teams, 2 SF matchups = 4 fixtures (2 legs each)
      expect(fixtures.length, equals(4));

      final leg1Fixtures = fixtures.where((f) => f['leg_number'] == 1).toList();
      final leg2Fixtures = fixtures.where((f) => f['leg_number'] == 2).toList();
      expect(leg1Fixtures.length, equals(2));
      expect(leg2Fixtures.length, equals(2));

      for (final l1 in leg1Fixtures) {
        // Find matching leg 2
        final l2 = leg2Fixtures.firstWhere(
          (f) => f['round_number'] == l1['round_number'] &&
                 f['home_team_id'] == l1['away_team_id'] &&
                 f['away_team_id'] == l1['home_team_id'],
        );

        final d1 = DateTime.parse(l1['match_date'] as String);
        final d2 = DateTime.parse(l2['match_date'] as String);

        // Leg 2 must be strictly scheduled AFTER Leg 1
        expect(d2.isAfter(d1), isTrue);
        expect(d2.difference(d1).inDays, greaterThanOrEqualTo(3));
      }
    });

    test('6. Completing competitions and advancing seasons', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_season_adv',
        saveName: 'Season Advance Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify season 2026 starts IN_PROGRESS with start_date
      final season2026 = saveDb.select("SELECT * FROM career_seasons WHERE season_year = 2026;").first;
      expect(season2026['status'], equals('IN_PROGRESS'));
      expect(season2026['start_date'], equals('2026-08-15'));

      // Simulate full season 2026
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_season_adv_season_2026',
      );

      // Verify league reached COMPLETED status and crowned champion
      final comp2026 = saveDb.select(
        "SELECT * FROM season_competitions WHERE season_id = 'save_season_adv_season_2026';",
      ).first;
      expect(comp2026['status'], equals('COMPLETED'));
      expect(comp2026['winner_team_id'], isNotNull);

      final summary2026 = calendarManager.getSeasonSummary(saveDb, 'save_season_adv_season_2026');
      expect(summary2026.isFullyCompleted, isTrue);
      expect(summary2026.upcomingFixtures, equals(0));
      expect(summary2026.completedFixtures, equals(12));

      // Advance to next season: 2027
      calendarManager.startNextSeason(
        saveDb: saveDb,
        worldDb: worldDb,
        nextSeasonYear: 2027,
      );

      // Verify season 2026 is marked COMPLETED with end_date
      final season2026After = saveDb.select("SELECT * FROM career_seasons WHERE season_year = 2026;").first;
      expect(season2026After['status'], equals('COMPLETED'));
      expect(season2026After['end_date'], isNotNull);

      // Verify season 2027 is created and active
      final season2027 = saveDb.select("SELECT * FROM career_seasons WHERE season_year = 2027;").first;
      expect(season2027['status'], equals('IN_PROGRESS'));
      expect(season2027['start_date'], equals('2027-08-15'));
      expect(calendarManager.getActiveSeasonId(saveDb), equals('save_season_adv_season_2027'));
      expect(calendarManager.getCurrentDate(saveDb), equals(DateTime(2027, 8, 15)));

      // Verify season 2027 has freshly scheduled fixtures
      final summary2027 = calendarManager.getSeasonSummary(saveDb, 'save_season_adv_season_2027');
      expect(summary2027.totalFixtures, equals(12));
      expect(summary2027.completedFixtures, equals(0));
      expect(summary2027.upcomingFixtures, equals(12));
    });

    test('7. Preserving existing career saves across season advancement and world DB modification', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_preservation',
        saveName: 'Preservation Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Play season 2026
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_preservation_season_2026',
      );

      // Standings for 2026
      final standings2026 = saveDb.select(
        "SELECT * FROM standings WHERE season_competition_id = 'save_preservation_season_2026_league_base';",
      );
      expect(standings2026.length, equals(4));

      // Advance to 2027
      calendarManager.startNextSeason(
        saveDb: saveDb,
        worldDb: worldDb,
        nextSeasonYear: 2027,
      );

      // 2026 standings and match records are completely preserved!
      final standings2026After = saveDb.select(
        "SELECT * FROM standings WHERE season_competition_id = 'save_preservation_season_2026_league_base';",
      );
      expect(standings2026After.length, equals(4));

      // Now wipe worldDb completely
      worldDb.execute('''
        DELETE FROM default_participants;
        DELETE FROM competition_rules;
        DELETE FROM competition_stages;
        DELETE FROM competitions;
        DELETE FROM teams;
        DELETE FROM clubs;
      ''');

      // The save database remains completely intact and readable
      final seasonsInSave = saveDb.select('SELECT season_year, status FROM career_seasons ORDER BY season_year ASC;');
      expect(seasonsInSave.length, equals(2));
      expect(seasonsInSave[0]['season_year'], equals(2026));
      expect(seasonsInSave[0]['status'], equals('COMPLETED'));
      expect(seasonsInSave[1]['season_year'], equals(2027));
      expect(seasonsInSave[1]['status'], equals('IN_PROGRESS'));
    });

    test('8. Adding a supported competition through database configuration alone', () {
      // Add a 4-team Single Elimination Cup entirely via SQL, including scheduling_rules_json
      worldDb.execute('''
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('sql_added_cup', 'SAC', 'SQL Added Cup', 'SACup', 'DOMESTIC', 2);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_sac', 'sql_added_cup', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, scheduling_rules_json
        ) VALUES (
          'stage_sac', 4, 1, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true}',
          '{"match_interval_days": 10, "min_rest_days": 2, "start_date": "2026-09-01"}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_sac', 't1', 1),
          ('stage_sac', 't2', 2),
          ('stage_sac', 't3', 3),
          ('stage_sac', 't4', 4);
      ''');

      // Validate world database
      final validation = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(validation.isValid, isTrue, reason: validation.errors.toString());

      // Start career
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_sql_cup',
        saveName: 'SQL Cup Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      final seasonId = 'save_sql_cup_season_2026';

      // Verify the tournament was automatically integrated into the season
      final compRows = saveDb.select(
        'SELECT competition_id, status FROM season_competitions WHERE season_id = ? AND competition_id = ?;',
        [seasonId, 'sql_added_cup'],
      );
      expect(compRows.isNotEmpty, isTrue);
      expect(compRows.first['status'], equals('ACTIVE'));

      // Verify fixtures were created
      final fixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'sql_added_cup';
        ''',
      );
      expect(fixtures.length, equals(2)); // Semi-finals
    });

    test('CalendarManager day-by-day simulation plays matches and advances standings', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_day_by_day',
        saveName: 'Day By Day Save',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Fast-forward to 2026-08-14 (one day before first round)
      saveDb.execute("UPDATE career_saves SET current_calendar_date = '2026-08-14';");

      // Advance from Aug 14 to Aug 15
      final day14Result = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(day14Result.date, equals(DateTime(2026, 8, 14)));
      expect(day14Result.playedFixtures, isEmpty);

      // Current date is now Aug 15. Advance to Aug 16: this must simulate Aug 15 matches!
      final day15Result = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(day15Result.date, equals(DateTime(2026, 8, 15)));
      expect(day15Result.playedFixtures.length, equals(2));

      for (final f in day15Result.playedFixtures) {
        expect(f.status, equals(FixtureStatus.played));
        expect(f.homeScore, isNotNull);
        expect(f.awayScore, isNotNull);
      }

      // Check standings table was updated
      final standings = saveDb.select("SELECT * FROM standings WHERE played > 0;");
      expect(standings.length, equals(4)); // All 4 teams have played 1 match
    });
  });
}
