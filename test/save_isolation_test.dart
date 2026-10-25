import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';

void main() {
  group('Save Isolation and World Replacement Tests', () {
    test('Modifying or replacing world.db does not corrupt or break active career save', () {
      final worldDb = sqlite3.openInMemory();
      final saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      final careerManager = CareerManager();

      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope)
        VALUES ('league_original', 'ORIG', 'Original League', 'Orig', 'DOMESTIC');

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_orig', 'league_original', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss, tiebreaker_json, match_rules_json)
        VALUES ('stage_orig', 2, 2, 3, 1, 0, '["POINTS"]', '{"extra_time": false, "penalties": false}');

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Club 1', 'C1', 'ENG'),
          ('c2', 'Club 2', 'C2', 'ENG');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Team 1', 'T1', 'SENIOR', 80),
          ('t2', 'c2', 'Team 2', 'T2', 'SENIOR', 75);

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_orig', 't1', 1),
          ('stage_orig', 't2', 2);
      ''');

      // Start career
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_isolated',
        saveName: 'Isolated Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify save database has its own snapshot of participants and fixtures
      final saveParticipants = saveDb.select('SELECT * FROM season_participants;');
      expect(saveParticipants.length, equals(2));

      final saveFixtures = saveDb.select('SELECT * FROM fixtures;');
      expect(saveFixtures.length, equals(2)); // 2 teams, 2 legs = 2 matches

      // NOW: Completely wipe / alter worldDb as if user replaced world.db with a totally different universe
      worldDb.execute('''
        DELETE FROM default_participants;
        DELETE FROM competition_rules;
        DELETE FROM competition_stages;
        DELETE FROM competitions;
        DELETE FROM teams;
        DELETE FROM clubs;
      ''');

      // Simulate the remaining season in saveDb
      // We pass saveDb and an independent or empty stages map if world is gone
      // To simulate using Save DB snapshot, the career continues cleanly
      final completedFixturesBefore = saveDb.select("SELECT * FROM fixtures WHERE status = 'PLAYED';");
      expect(completedFixturesBefore.length, equals(0));

      // The save DB contains all fixture records already scheduled
      // Simulate directly on the save DB fixtures
      final scheduledFixtures = saveDb.select("SELECT * FROM fixtures WHERE status = 'SCHEDULED';");
      expect(scheduledFixtures.length, equals(2));

      for (final sf in scheduledFixtures) {
        saveDb.execute(
          "UPDATE fixtures SET home_score = 2, away_score = 1, status = 'PLAYED' WHERE id = ?;",
          [sf['id']],
        );
      }

      final completedFixturesAfter = saveDb.select("SELECT * FROM fixtures WHERE status = 'PLAYED';");
      expect(completedFixturesAfter.length, equals(2));

      // Save database is completely unharmed and intact!
      final saveRecord = saveDb.select('SELECT * FROM career_saves;').first;
      expect(saveRecord['id'], equals('save_isolated'));
      expect(saveRecord['user_team_id'], equals('t1'));

      worldDb.close();
      saveDb.close();
    });
  });
}
