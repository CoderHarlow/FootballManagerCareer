import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/database_validator.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';

void main() {
  group('Phase 3 Database-Only Competition Extension Tests', () {
    late Database worldDb;
    late Database saveDb;
    late CareerManager careerManager;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      careerManager = CareerManager();

      // Initial state: World with 1 regular domestic league (4 teams)
      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('league_base', 'BASE', 'Base League', 'Base', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_base_league', 'league_base', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'stage_base_league', 4, 2, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": false, "penalties": false}'
        );

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

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_base_league', 't1', 1),
          ('stage_base_league', 't2', 2),
          ('stage_base_league', 't3', 3),
          ('stage_base_league', 't4', 4);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
    });

    test('Seamlessly adds both a Two-Legged Cup AND a Group-Stage Tournament via SQL alone', () {
      // PURELY DATABASE INSERT: Add 4 more teams (total 8 teams) and 2 new distinct tournaments
      worldDb.execute('''
        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c5', 'Club Epsilon', 'EPS', 'ENG'),
          ('c6', 'Club Zeta', 'ZET', 'ENG'),
          ('c7', 'Club Eta', 'ETA', 'ENG'),
          ('c8', 'Club Theta', 'THE', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t5', 'c5', 'Epsilon Team', 'EPS', 'SENIOR', 60),
          ('t6', 'c6', 'Zeta Team', 'ZET', 'SENIOR', 58),
          ('t7', 'c7', 'Eta Team', 'ETA', 'SENIOR', 55),
          ('t8', 'c8', 'Theta Team', 'THE', 'SENIOR', 52);

        -- Tournament 1: Two-Legged Cup (4 teams)
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('two_leg_cup', 'TLC', 'Two Legged Cup', 'TLC', 'CONTINENTAL', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_tlc', 'two_leg_cup', 1, 'TWO_LEGGED_TIE');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'stage_tlc', 4, 2, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true, "away_goals": true, "subs_max": 5}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_tlc', 't1', 1),
          ('stage_tlc', 't2', 2),
          ('stage_tlc', 't3', 3),
          ('stage_tlc', 't4', 4);

        -- Tournament 2: Group Stage to Knockout (8 teams: 2 groups of 4)
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('champions_cup', 'CCUP', 'Champions Cup', 'CCup', 'CONTINENTAL', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_ccup', 'champions_cup', 1, 'GROUP_STAGE_TO_KNOCKOUT');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, qualification_rules_json
        ) VALUES (
          'stage_ccup', 8, 1, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": true, "penalties": true, "subs_max": 5}',
          '{"qualify_per_group": 2}'
        );

        -- Group 0
        INSERT INTO default_participants (stage_id, team_id, group_index, seed) VALUES
          ('stage_ccup', 't1', 0, 1),
          ('stage_ccup', 't2', 0, 2),
          ('stage_ccup', 't3', 0, 3),
          ('stage_ccup', 't4', 0, 4);

        -- Group 1
        INSERT INTO default_participants (stage_id, team_id, group_index, seed) VALUES
          ('stage_ccup', 't5', 1, 1),
          ('stage_ccup', 't6', 1, 2),
          ('stage_ccup', 't7', 1, 3),
          ('stage_ccup', 't8', 1, 4);
      ''');

      // 1. Validate the database
      final validation = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(validation.isValid, isTrue, reason: 'Validation failed: ${validation.errors}');

      // 2. Start a new career
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_multi_tourney',
        saveName: 'Multi Tourney Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify all 3 competitions were registered in the save
      final activeComps = saveDb.select(
        "SELECT competition_id FROM season_competitions WHERE season_id = 'save_multi_tourney_season_2026';",
      );
      final compIds = activeComps.map((r) => r['competition_id'] as String).toSet();
      expect(compIds, containsAll(['league_base', 'two_leg_cup', 'champions_cup']));

      // 3. Simulate the entire season
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_multi_tourney_season_2026',
      );

      // Verify all 3 competitions reached COMPLETED status and crowned champions
      final compRecords = saveDb.select(
        "SELECT competition_id, status, winner_team_id FROM season_competitions WHERE season_id = 'save_multi_tourney_season_2026';",
      );
      expect(compRecords.length, equals(3));

      for (final comp in compRecords) {
        expect(comp['status'], equals('COMPLETED'), reason: '${comp['competition_id']} should be completed');
        expect(comp['winner_team_id'], isNotNull, reason: '${comp['competition_id']} must have a winner');
      }

      // Verify League had 12 matches
      final leagueFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'league_base';
        ''',
      );
      expect(leagueFixtures.length, equals(12));

      // Verify Two-Legged Cup had 6 matches (4 SF + 2 Final)
      final tlcFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'two_leg_cup';
        ''',
      );
      expect(tlcFixtures.length, equals(6));

      // Verify Champions Cup (Group Stage to Knockout) had 15 matches (12 groups + 2 SF + 1 Final)
      final ccupFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'champions_cup';
        ''',
      );
      expect(ccupFixtures.length, equals(15));
    });
  });
}
