import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';

void main() {
  group('Round Robin League Engine Tests', () {
    late Database worldDb;
    late Database saveDb;
    late CareerManager careerManager;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      careerManager = CareerManager();

      // Seed 4 clubs and teams
      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('epl_tier1', 'EPL', 'Premier League', 'Prem', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('epl_stage_1', 'epl_tier1', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'epl_stage_1', 4, 2, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR"]',
          '{"extra_time": false, "penalties": false}'
        );

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Arsenal Red', 'ARS', 'ENG'),
          ('c2', 'Chelsea Blue', 'CHE', 'ENG'),
          ('c3', 'Liverpool Red', 'LIV', 'ENG'),
          ('c4', 'Manchester Blue', 'MCI', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Arsenal Senior', 'ARS', 'SENIOR', 85),
          ('t2', 'c2', 'Chelsea Senior', 'CHE', 'SENIOR', 82),
          ('t3', 'c3', 'Liverpool Senior', 'LIV', 'SENIOR', 86),
          ('t4', 'c4', 'Manchester City Senior', 'MCI', 'SENIOR', 88);

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('epl_stage_1', 't1', 1),
          ('epl_stage_1', 't2', 2),
          ('epl_stage_1', 't3', 3),
          ('epl_stage_1', 't4', 4);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
    });

    test('Initializes fixtures and simulates complete round-robin season', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_001',
        saveName: 'My Premier Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify fixtures generated: 4 teams * (4-1) * 2 legs = 12 matches total across 6 rounds
      final fixtureRows = saveDb.select('SELECT * FROM fixtures ORDER BY round_number ASC;');
      expect(fixtureRows.length, equals(12));

      final rounds = fixtureRows.map((r) => r['round_number'] as int).toSet();
      expect(rounds.length, equals(6)); // 6 distinct match weeks

      // Verify each team plays 6 matches (3 home, 3 away)
      for (final teamId in ['t1', 't2', 't3', 't4']) {
        final homeCount = fixtureRows.where((r) => r['home_team_id'] == teamId).length;
        final awayCount = fixtureRows.where((r) => r['away_team_id'] == teamId).length;
        expect(homeCount, equals(3), reason: 'Team \$teamId should have 3 home games');
        expect(awayCount, equals(3), reason: 'Team \$teamId should have 3 away games');
      }

      // Simulate the full season
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_001_season_2026',
      );

      // Verify all 12 fixtures are completed
      final completedFixtures = saveDb.select(
        "SELECT * FROM fixtures WHERE status = 'PLAYED';",
      );
      expect(completedFixtures.length, equals(12));

      // Verify Standings table
      final standingsRows = saveDb.select(
        'SELECT * FROM standings ORDER BY rank ASC;',
      );
      expect(standingsRows.length, equals(4));

      int totalPoints = 0;
      for (final s in standingsRows) {
        expect(s['played'], equals(6));
        final won = s['won'] as int;
        final drawn = s['drawn'] as int;
        final lost = s['lost'] as int;
        expect(won + drawn + lost, equals(6));
        expect(s['points'], equals((won * 3) + (drawn * 1)));
        expect(s['goal_difference'], equals((s['goals_for'] as int) - (s['goals_against'] as int)));
        totalPoints += (s['points'] as int);
      }

      // Points consistency: in standard 3-1-0 scoring, sum of points is 3 * wins + 2 * draws
      expect(totalPoints, greaterThanOrEqualTo(24));

      // Verify Champion is recorded in season_competitions
      final seasonComp = saveDb.select(
        "SELECT * FROM season_competitions WHERE id = 'save_001_season_2026_epl_tier1';",
      ).first;
      expect(seasonComp['status'], equals('COMPLETED'));
      expect(seasonComp['winner_team_id'], equals(standingsRows.first['team_id']));
      expect(seasonComp['winner_team_id'], isNotNull);
    });
  });
}
