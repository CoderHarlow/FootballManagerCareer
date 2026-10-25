import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';

void main() {
  group('Group Stage to Knockout Engine Tests', () {
    late Database worldDb;
    late Database saveDb;
    late CareerManager careerManager;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      careerManager = CareerManager();

      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('world_cup_mini', 'WC', 'Mini World Cup', 'WC', 'INTERNATIONAL', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('wc_stage_all', 'world_cup_mini', 1, 'GROUP_STAGE_TO_KNOCKOUT');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json, qualification_rules_json
        ) VALUES (
          'wc_stage_all', 8, 1, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": true, "penalties": true, "subs_max": 5}',
          '{"qualify_per_group": 2}'
        );

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Argentina', 'ARG', 'ARG'),
          ('c2', 'France', 'FRA', 'FRA'),
          ('c3', 'Brazil', 'BRA', 'BRA'),
          ('c4', 'England', 'ENG', 'ENG'),
          ('c5', 'Spain', 'ESP', 'ESP'),
          ('c6', 'Germany', 'GER', 'GER'),
          ('c7', 'Portugal', 'POR', 'POR'),
          ('c8', 'Netherlands', 'NED', 'NED');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Argentina Men', 'ARG', 'SENIOR', 90),
          ('t2', 'c2', 'France Men', 'FRA', 'SENIOR', 89),
          ('t3', 'c3', 'Brazil Men', 'BRA', 'SENIOR', 88),
          ('t4', 'c4', 'England Men', 'ENG', 'SENIOR', 86),
          ('t5', 'c5', 'Spain Men', 'ESP', 'SENIOR', 87),
          ('t6', 'c6', 'Germany Men', 'GER', 'SENIOR', 85),
          ('t7', 'c7', 'Portugal Men', 'POR', 'SENIOR', 84),
          ('t8', 'c8', 'Netherlands Men', 'NED', 'SENIOR', 83);

        -- Group 0: 4 teams
        INSERT INTO default_participants (stage_id, team_id, group_index, seed) VALUES
          ('wc_stage_all', 't1', 0, 1),
          ('wc_stage_all', 't2', 0, 2),
          ('wc_stage_all', 't3', 0, 3),
          ('wc_stage_all', 't4', 0, 4);

        -- Group 1: 4 teams
        INSERT INTO default_participants (stage_id, team_id, group_index, seed) VALUES
          ('wc_stage_all', 't5', 1, 1),
          ('wc_stage_all', 't6', 1, 2),
          ('wc_stage_all', 't7', 1, 3),
          ('wc_stage_all', 't8', 1, 4);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
    });

    test('Runs group stage with 2 groups, advances top 2 into knockout bracket, and crowns champion', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_wc',
        saveName: 'World Cup Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify Initial Group Fixtures:
      // 2 groups of 4 teams, 1 single round-robin leg
      // Each group plays 3 rounds of 2 matches = 6 matches per group = 12 total group matches
      final initialFixtures = saveDb.select('SELECT * FROM fixtures ORDER BY round_number ASC;');
      expect(initialFixtures.length, equals(12), reason: '2 groups of 4 teams with 1 leg must yield 12 matches');

      final roundNumbers = initialFixtures.map((f) => f['round_number'] as int).toSet();
      expect(roundNumbers, equals({1, 2, 3}), reason: 'Group phase should have 3 match days');

      // Simulate the entire tournament (groups -> semi-finals -> final)
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_wc_season_2026',
      );

      // Verify Standings were calculated for both groups
      final g0Standings = saveDb.select(
        'SELECT * FROM standings WHERE group_index = 0 ORDER BY rank ASC;',
      );
      final g1Standings = saveDb.select(
        'SELECT * FROM standings WHERE group_index = 1 ORDER BY rank ASC;',
      );

      expect(g0Standings.length, equals(4), reason: 'Group 0 must have 4 teams in standings');
      expect(g1Standings.length, equals(4), reason: 'Group 1 must have 4 teams in standings');

      for (final s in [...g0Standings, ...g1Standings]) {
        expect(s['played'], equals(3), reason: 'Each team must have played 3 group matches');
        final won = s['won'] as int;
        final drawn = s['drawn'] as int;
        final lost = s['lost'] as int;
        expect(won + drawn + lost, equals(3));
      }

      // Verify Total Fixtures:
      // Group phase: 12 matches (Rounds 1, 2, 3)
      // Semi-Finals: 2 matches (Round 4)
      // Final:       1 match (Round 5)
      // Total: 15 matches
      final allFixtures = saveDb.select('SELECT * FROM fixtures ORDER BY round_number ASC;');
      expect(allFixtures.length, equals(15), reason: 'Total tournament matches must equal 12 + 2 + 1 = 15');

      final r4Matches = allFixtures.where((f) => f['round_number'] == 4).toList();
      final r5Matches = allFixtures.where((f) => f['round_number'] == 5).toList();

      expect(r4Matches.length, equals(2), reason: 'Round 4 (Semi-Finals) must have 2 matches');
      expect(r5Matches.length, equals(1), reason: 'Round 5 (Final) must have 1 match');

      // Verify cross-group pairing in Semi-Finals:
      // Semi-Final participants must be the top 2 from Group 0 and top 2 from Group 1
      final sfTeamIds = r4Matches.expand((f) => [f['home_team_id'], f['away_team_id']]).toSet();
      final expectedQualified = {
        g0Standings[0]['team_id'],
        g0Standings[1]['team_id'],
        g1Standings[0]['team_id'],
        g1Standings[1]['team_id'],
      };
      expect(sfTeamIds, equals(expectedQualified), reason: 'Semi-finalists must be exactly top 2 from each group');

      // Verify Champion is crowned
      final compRecord = saveDb.select(
        "SELECT * FROM season_competitions WHERE competition_id = 'world_cup_mini';",
      ).first;

      expect(compRecord['status'], equals('COMPLETED'));
      expect(compRecord['winner_team_id'], isNotNull);

      final winnerId = compRecord['winner_team_id'] as String;
      final finalTeams = [r5Matches.first['home_team_id'], r5Matches.first['away_team_id']];
      expect(finalTeams, contains(winnerId), reason: 'Champion must be one of the finalists');
    });
  });
}
