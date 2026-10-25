import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/database_validator.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';

void main() {
  group('Database-Only Tournament Extension Test', () {
    late Database worldDb;
    late Database saveDb;
    late CareerManager careerManager;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      careerManager = CareerManager();

      // Initial state: World with 1 league (4 teams)
      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('league_div1', 'DIV1', 'Division 1', 'Div1', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('div1_stage', 'league_div1', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'div1_stage', 4, 2, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": false, "penalties": false}'
        );

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Club Alpha', 'ALP', 'ENG'),
          ('c2', 'Club Beta', 'BET', 'ENG'),
          ('c3', 'Club Gamma', 'GAM', 'ENG'),
          ('c4', 'Club Delta', 'DEL', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Alpha First', 'ALP', 'SENIOR', 80),
          ('t2', 'c2', 'Beta First', 'BET', 'SENIOR', 75),
          ('t3', 'c3', 'Gamma First', 'GAM', 'SENIOR', 70),
          ('t4', 'c4', 'Delta First', 'DEL', 'SENIOR', 65);

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('div1_stage', 't1', 1),
          ('div1_stage', 't2', 2),
          ('div1_stage', 't3', 3),
          ('div1_stage', 't4', 4);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
    });

    test('Engine dynamically runs an 8-team Knockout Cup added purely via SQL', () {
      // 1. EXTEND DATABASE ONLY: Without touching any Dart code, insert 4 new teams
      // and an 8-team single-elimination tournament into worldDb.
      worldDb.execute('''
        -- 4 additional clubs and teams to make 8 total
        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c5', 'Club Epsilon', 'EPS', 'ENG'),
          ('c6', 'Club Zeta', 'ZET', 'ENG'),
          ('c7', 'Club Eta', 'ETA', 'ENG'),
          ('c8', 'Club Theta', 'THE', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t5', 'c5', 'Epsilon First', 'EPS', 'SENIOR', 60),
          ('t6', 'c6', 'Zeta First', 'ZET', 'SENIOR', 58),
          ('t7', 'c7', 'Eta First', 'ETA', 'SENIOR', 55),
          ('t8', 'c8', 'Theta First', 'THE', 'SENIOR', 52);

        -- Brand new tournament: 8-team Knockout Cup
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('national_cup', 'NCUP', 'National Knockout Cup', 'Cup', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('cup_stage_main', 'national_cup', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'cup_stage_main', 8, 1, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true, "subs_max": 5}'
        );

        -- 8 participants seeded into the tournament
        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('cup_stage_main', 't1', 1),
          ('cup_stage_main', 't2', 2),
          ('cup_stage_main', 't3', 3),
          ('cup_stage_main', 't4', 4),
          ('cup_stage_main', 't5', 5),
          ('cup_stage_main', 't6', 6),
          ('cup_stage_main', 't7', 7),
          ('cup_stage_main', 't8', 8);
      ''');

      // 2. Validate the modified database
      final valResult = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(valResult.isValid, isTrue, reason: 'Validation failed: \${valResult.errors}');

      // 3. Start a new career
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_cup_test',
        saveName: 'Multi Competition Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify that BOTH competitions were discovered and registered in the save
      final activeComps = saveDb.select(
        "SELECT competition_id FROM season_competitions WHERE season_id = 'save_cup_test_season_2026';",
      );
      final compIds = activeComps.map((r) => r['competition_id'] as String).toSet();
      expect(compIds, containsAll(['league_div1', 'national_cup']));

      // Verify Initial Cup Fixtures (Quarter-Finals: 8 teams -> 4 matches in round 1)
      final initialCupFixtures = saveDb.select(
        '''
        SELECT * FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'national_cup' AND f.round_number = 1;
        ''',
      );
      expect(initialCupFixtures.length, equals(4), reason: 'Quarter-finals must have 4 matches');

      // 4. Simulate the entire season
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_cup_test_season_2026',
      );

      // Verify Cup Progression:
      // Quarter-Finals: Round 1 (4 matches)
      // Semi-Finals:    Round 2 (2 matches)
      // Final:          Round 3 (1 match)
      // Total matches = 7
      final allCupFixtures = saveDb.select(
        '''
        SELECT f.* FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.competition_id = 'national_cup'
        ORDER BY f.round_number ASC;
        ''',
      );
      expect(allCupFixtures.length, equals(7), reason: '8-team knockout must result in 7 total matches');

      final r1Matches = allCupFixtures.where((f) => f['round_number'] == 1).toList();
      final r2Matches = allCupFixtures.where((f) => f['round_number'] == 2).toList();
      final r3Matches = allCupFixtures.where((f) => f['round_number'] == 3).toList();

      expect(r1Matches.length, equals(4), reason: 'Round 1 (QF) must have 4 matches');
      expect(r2Matches.length, equals(2), reason: 'Round 2 (SF) must have 2 matches');
      expect(r3Matches.length, equals(1), reason: 'Round 3 (Final) must have 1 match');

      // Verify all matches were played to a definitive winner (no unresolved draws in knockout)
      for (final f in allCupFixtures) {
        expect(f['status'], equals('PLAYED'));
        final hScore = f['home_score'] as int;
        final aScore = f['away_score'] as int;
        final hEt = f['home_extra_score'] as int? ?? 0;
        final aEt = f['away_extra_score'] as int? ?? 0;
        final hPk = f['home_pk_score'] as int?;
        final aPk = f['away_pk_score'] as int?;

        final totalHome = hScore + hEt;
        final totalAway = aScore + aEt;

        if (totalHome == totalAway) {
          // Must have been decided on penalties
          expect(hPk, isNotNull);
          expect(aPk, isNotNull);
          expect(hPk, isNot(equals(aPk)));
        }
      }

      // Verify Final Winner is crowned and recorded in season_competitions
      final cupRecord = saveDb.select(
        '''
        SELECT * FROM season_competitions
        WHERE competition_id = 'national_cup' AND season_id = 'save_cup_test_season_2026';
        ''',
      ).first;

      expect(cupRecord['status'], equals('COMPLETED'));
      final cupWinnerId = cupRecord['winner_team_id'] as String?;
      expect(cupWinnerId, isNotNull);

      // Verify the cup winner is indeed the winner of the final match
      final finalMatch = r3Matches.first;
      final finalHome = finalMatch['home_team_id'] as String;
      final finalAway = finalMatch['away_team_id'] as String;
      expect([finalHome, finalAway], contains(cupWinnerId));

      // Also verify League completed normally alongside the cup
      final leagueRecord = saveDb.select(
        '''
        SELECT * FROM season_competitions
        WHERE competition_id = 'league_div1' AND season_id = 'save_cup_test_season_2026';
        ''',
      ).first;
      expect(leagueRecord['status'], equals('COMPLETED'));
      expect(leagueRecord['winner_team_id'], isNotNull);
    });
  });
}
