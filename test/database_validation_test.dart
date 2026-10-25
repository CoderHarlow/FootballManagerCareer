import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/database_validator.dart';
import 'package:football_manager_career/core/database/schema.dart';

void main() {
  group('DatabaseValidator Tests', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      db.execute(DatabaseSchema.worldSchemaSql);
    });

    tearDown(() {
      db.close();
    });

    test('Fails when dataset_metadata is missing', () {
      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.code == 'MISSING_METADATA'), isTrue);
    });

    test('Fails when engine version is incompatible', () {
      db.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('test_data', 1, '1.0.0', 999, '2026-10-25');
      ''');

      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.code == 'INCOMPATIBLE_ENGINE_VERSION'), isTrue);
      expect(result.errors.first.message, contains('requires engine version 999'));
    });

    test('Rejects unsupported competition format with clear error message', () {
      db.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('test_data', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope)
        VALUES ('swiss_tourney', 'SWISS', 'Swiss League', 'Swiss', 'DOMESTIC');

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('swiss_stage_1', 'swiss_tourney', 1, 'SWISS_SYSTEM');
      ''');

      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      final err = result.errors.firstWhere((e) => e.code == 'UNSUPPORTED_FORMAT');
      expect(err.message, contains('Unsupported format "SWISS_SYSTEM"'));
      expect(err.message, contains('Completely new competition formats require engine code updates'));
    });

    test('Rejects knockout format with non-power-of-2 team count', () {
      db.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('test_data', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope)
        VALUES ('six_team_cup', '6CUP', 'Six Team Cup', '6Cup', 'DOMESTIC');

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_6cup', 'six_team_cup', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (stage_id, team_count, match_rules_json, tiebreaker_json)
        VALUES ('stage_6cup', 6, '{"extra_time": true, "penalties": true}', '["POINTS"]');
      ''');

      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      final err = result.errors.firstWhere((e) => e.code == 'KNOCKOUT_NON_POWER_OF_TWO');
      expect(err.message, contains('specifies 6 teams'));
      expect(err.message, contains('require a power-of-2 team count (2, 4, 8, 16, 32, 64)'));
    });

    test('Rejects single-elimination knockout without extra time or penalties', () {
      db.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('test_data', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope)
        VALUES ('cup_no_decider', 'NDCUP', 'No Decider Cup', 'NDCup', 'DOMESTIC');

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_ndcup', 'cup_no_decider', 1, 'SINGLE_ELIMINATION');

        INSERT INTO competition_rules (stage_id, team_count, match_rules_json, tiebreaker_json)
        VALUES ('stage_ndcup', 4, '{"extra_time": false, "penalties": false}', '["POINTS"]');
      ''');

      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      final err = result.errors.firstWhere((e) => e.code == 'KNOCKOUT_NO_DECIDER');
      expect(err.message, contains('must enable "penalties" or "extra_time" in match_rules_json'));
    });

    test('Rejects participant count mismatch', () {
      db.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('test_data', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope)
        VALUES ('league4', 'L4', 'League 4', 'L4', 'DOMESTIC');

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_l4', 'league4', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (stage_id, team_count, match_rules_json, tiebreaker_json)
        VALUES ('stage_l4', 4, '{"extra_time": false, "penalties": false}', '["POINTS"]');

        INSERT INTO clubs (id, name, short_name, country_code) VALUES ('c1', 'Club 1', 'C1', 'ENG');
        INSERT INTO teams (id, club_id, name, short_name, team_category) VALUES ('t1', 'c1', 'Team 1', 'T1', 'SENIOR');
        INSERT INTO default_participants (stage_id, team_id) VALUES ('stage_l4', 't1');
      ''');

      final result = DatabaseValidator.validateWorldDatabase(db);
      expect(result.isValid, isFalse);
      final err = result.errors.firstWhere((e) => e.code == 'PARTICIPANT_COUNT_MISMATCH');
      expect(err.message, contains('specifies team_count=4 in competition_rules, but has 1 participants'));
    });
  });
}
