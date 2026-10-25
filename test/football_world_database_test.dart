import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/calendar/calendar_manager.dart';
import 'package:football_manager_career/core/database/database_validator.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/database/world_database_service.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';
import 'package:football_manager_career/core/engine/models/football_world.dart';

void main() {
  group('Phase 5 — Football World Database & Import/Export Tests', () {
    late Database worldDb;
    late Database saveDb;
    late Directory tempDir;
    late WorldDatabaseService databaseService;
    late CareerManager careerManager;
    late CalendarManager calendarManager;

    setUp(() {
      worldDb = sqlite3.openInMemory();
      saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      tempDir = Directory.systemTemp.createTempSync('fm_phase5_test_');
      databaseService = WorldDatabaseService();
      careerManager = CareerManager();
      calendarManager = CalendarManager();

      // Base World setup
      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO countries (id, name, code, continent, reputation)
        VALUES ('c_eng', 'England', 'ENG', 'EUROPE', 85);

        INSERT INTO stadiums (id, name, city, country_code, capacity, built_year)
        VALUES ('s_emirates', 'Emirates Stadium', 'London', 'ENG', 60704, 2006);

        INSERT INTO clubs (id, name, short_name, country_code, city, reputation, stadium_id, stadium_name, stadium_capacity)
        VALUES ('c_ars', 'Arsenal', 'ARS', 'ENG', 'London', 85, 's_emirates', 'Emirates Stadium', 60704);

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation)
        VALUES ('t_ars_sen', 'c_ars', 'Arsenal Senior', 'ARS', 'SENIOR', 85);

        INSERT INTO clubs (id, name, short_name, country_code, city, reputation)
        VALUES ('c_che', 'Chelsea', 'CHE', 'ENG', 'London', 82);

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation)
        VALUES ('t_che_sen', 'c_che', 'Chelsea Senior', 'CHE', 'SENIOR', 82);

        -- National Team (club_id NULL, country_code specified)
        INSERT INTO teams (id, club_id, country_code, name, short_name, team_category, reputation)
        VALUES ('t_eng_nat', NULL, 'ENG', 'England National Team', 'ENG', 'NATIONAL', 88);

        -- Players
        INSERT INTO players (
          id, first_name, last_name, birth_date, nationality_code, preferred_foot,
          primary_position, secondary_positions_json, overall_rating, pace, shooting,
          passing, dribbling, defending, physical, goalkeeping, attributes_json
        ) VALUES (
          'p_saka', 'Bukayo', 'Saka', '2001-09-05', 'ENG', 'L',
          'RW', '["LW", "RM"]', 86, 85, 82, 83, 87, 65, 75, 12,
          '{"weak_foot": 4, "skill_moves": 4, "work_rate": "HIGH_MEDIUM"}'
        ), (
          'p_rice', 'Declan', 'Rice', '1999-01-14', 'ENG', 'R',
          'CDM', '["CM", "CB"]', 87, 75, 71, 82, 80, 88, 86, 12,
          '{"weak_foot": 3, "skill_moves": 3, "work_rate": "HIGH_HIGH"}'
        );

        -- Player Positions
        INSERT INTO player_positions (player_id, position, is_primary, proficiency)
        VALUES ('p_saka', 'RW', 1, 100), ('p_saka', 'LW', 0, 85);

        -- Squad Contracts
        INSERT INTO squad_contracts (id, player_id, team_id, squad_number, wage_per_week, contract_expiry_year, contract_start_year)
        VALUES ('sc_saka_ars', 'p_saka', 't_ars_sen', 7, 195000, 2028, 2023),
               ('sc_rice_ars', 'p_rice', 't_ars_sen', 41, 240000, 2029, 2023);

        -- National Squad Selections
        INSERT INTO national_squad_selections (id, player_id, team_id, squad_number, callup_year)
        VALUES ('nss_saka_eng', 'p_saka', 't_eng_nat', 7, 2026),
               ('nss_rice_eng', 'p_rice', 't_eng_nat', 4, 2026);

        -- Base Competition: 2-team League
        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('league_london', 'LDN', 'London Derby League', 'London', 'DOMESTIC', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('stage_ldn', 'league_london', 1, 'ROUND_ROBIN');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'stage_ldn', 2, 2, 3, 1, 0,
          '["POINTS", "GOAL_DIFFERENCE"]',
          '{"extra_time": false, "penalties": false}'
        );

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('stage_ldn', 't_ars_sen', 1),
          ('stage_ldn', 't_che_sen', 2);
      ''');
    });

    tearDown(() {
      worldDb.close();
      saveDb.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Creating and validating countries, clubs, players, squads, and competitions', () {
      final validation = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(validation.isValid, isTrue, reason: validation.errors.toString());

      // Query and verify Domain Models parse SQLite data correctly
      final countryRow = worldDb.select("SELECT * FROM countries WHERE id = 'c_eng';").first;
      final country = Country.fromMap(countryRow);
      expect(country.name, equals('England'));
      expect(country.code, equals('ENG'));
      expect(country.continent, equals('EUROPE'));

      final stadiumRow = worldDb.select("SELECT * FROM stadiums WHERE id = 's_emirates';").first;
      final stadium = Stadium.fromMap(stadiumRow);
      expect(stadium.capacity, equals(60704));

      final clubRow = worldDb.select("SELECT * FROM clubs WHERE id = 'c_ars';").first;
      final club = Club.fromMap(clubRow);
      expect(club.stadiumId, equals('s_emirates'));

      final playerRow = worldDb.select("SELECT * FROM players WHERE id = 'p_saka';").first;
      final player = Player.fromMap(playerRow);
      expect(player.fullName, equals('Bukayo Saka'));
      expect(player.primaryPosition, equals('RW'));
      expect(player.secondaryPositions, containsAll(['LW', 'RM']));
      expect(player.customAttributes['work_rate'], equals('HIGH_MEDIUM'));

      final contractRow = worldDb.select("SELECT * FROM squad_contracts WHERE id = 'sc_saka_ars';").first;
      final contract = SquadContract.fromMap(contractRow);
      expect(contract.squadNumber, equals(7));
      expect(contract.wagePerWeek, equals(195000));
    });

    test('2. Foreign-key and duplicate-record validation', () {
      // 2a. Foreign key failure: insert team with non-existent club_id
      expect(
        () => worldDb.execute('''
          INSERT INTO teams (id, club_id, name, short_name, team_category)
          VALUES ('t_ghost', 'c_non_existent', 'Ghost FC', 'GHO', 'SENIOR');
        '''),
        throwsA(isA<SqliteException>()),
      );

      // 2b. Foreign key failure: insert contract with non-existent player
      expect(
        () => worldDb.execute('''
          INSERT INTO squad_contracts (id, player_id, team_id, squad_number, wage_per_week, contract_expiry_year)
          VALUES ('sc_ghost', 'p_non_existent', 't_ars_sen', 99, 1000, 2028);
        '''),
        throwsA(isA<SqliteException>()),
      );

      // 2c. Duplicate player contract validation in DatabaseValidator
      worldDb.execute('''
        INSERT INTO squad_contracts (id, player_id, team_id, squad_number, wage_per_week, contract_expiry_year)
        VALUES ('sc_saka_dup', 'p_saka', 't_ars_sen', 77, 200000, 2029);
      ''');
      final dupCheck = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(dupCheck.isValid, isFalse);
      expect(dupCheck.errors.any((e) => e.code == 'DUPLICATE_PLAYER_CONTRACT'), isTrue);

      // Clean up duplicate contract for subsequent tests
      worldDb.execute("DELETE FROM squad_contracts WHERE id = 'sc_saka_dup';");

      // 2d. Invalid player position validation
      worldDb.execute('''
        INSERT INTO players (id, first_name, last_name, birth_date, nationality_code, primary_position)
        VALUES ('p_bad_pos', 'John', 'Doe', '2000-01-01', 'ENG', 'QUARTERBACK');
      ''');
      final posCheck = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(posCheck.isValid, isFalse);
      expect(posCheck.errors.any((e) => e.code == 'UNSUPPORTED_POSITION'), isTrue);
      worldDb.execute("DELETE FROM players WHERE id = 'p_bad_pos';");

      // 2e. SQLite schema CHECK constraint enforces player rating range [1, 99]
      expect(
        () => worldDb.execute('''
          INSERT INTO players (id, first_name, last_name, birth_date, nationality_code, primary_position, overall_rating)
          VALUES ('p_bad_rate', 'Super', 'Man', '2000-01-01', 'ENG', 'ST', 150);
        '''),
        throwsA(isA<SqliteException>()),
      );

      // 2f. DatabaseValidator catches invalid birth dates
      worldDb.execute('''
        INSERT INTO players (id, first_name, last_name, birth_date, nationality_code, primary_position)
        VALUES ('p_bad_date', 'Time', 'Traveler', 'invalid-date-format', 'ENG', 'ST');
      ''');
      final dateCheck = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(dateCheck.isValid, isFalse);
      expect(dateCheck.errors.any((e) => e.code == 'INVALID_BIRTH_DATE'), isTrue);
      worldDb.execute("DELETE FROM players WHERE id = 'p_bad_date';");
    });

    test('3. Valid database export and import', () {
      final exportPath = '${tempDir.path}/master_world_export.db';
      final importPath = '${tempDir.path}/imported_world.db';

      // Export in-memory database to file
      final exportResult = databaseService.exportDatabaseInstance(
        db: worldDb,
        targetFilePath: exportPath,
      );
      expect(exportResult.isSuccess, isTrue);
      expect(File(exportPath).existsSync(), isTrue);
      expect(exportResult.byteSize, greaterThan(0));

      // Validate exported file
      final valResult = databaseService.validateDatabaseFile(exportPath);
      expect(valResult.isValid, isTrue, reason: valResult.errors.toString());

      // Import to new destination
      final importResult = databaseService.importWorldDatabase(
        sourceFilePath: exportPath,
        targetFilePath: importPath,
      );
      expect(importResult.isSuccess, isTrue);
      expect(File(importPath).existsSync(), isTrue);
      expect(importResult.acceptedCompetitions, equals(1));
      expect(importResult.acceptedClubs, equals(2));
      expect(importResult.acceptedTeams, equals(3));
      expect(importResult.acceptedPlayers, equals(2));
      expect(importResult.acceptedContracts, equals(2));

      // Verify imported database can be opened and queried
      final importedDb = sqlite3.open(importPath);
      final count = importedDb.select('SELECT COUNT(*) as c FROM players;').first['c'];
      expect(count, equals(2));
      importedDb.close();
    });

    test('4. Rejection of corrupted, truncated, or incompatible database files', () {
      // 4a. Random text file (not an SQLite database)
      final fakeDbPath = '${tempDir.path}/fake.db';
      File(fakeDbPath).writeAsStringSync('Hello, this is just plain text, not SQLite!');

      final textVal = databaseService.validateDatabaseFile(fakeDbPath);
      expect(textVal.isValid, isFalse);
      expect(textVal.errors.any((e) => e.code == 'CORRUPTED_FILE' || e.code == 'INVALID_SQLITE_HEADER'), isTrue);

      final importTextRes = databaseService.importWorldDatabase(
        sourceFilePath: fakeDbPath,
        targetFilePath: '${tempDir.path}/should_never_exist.db',
      );
      expect(importTextRes.isSuccess, isFalse);
      expect(File('${tempDir.path}/should_never_exist.db').existsSync(), isFalse);

      // 4b. Missing required tables (empty SQLite file)
      final emptySqlitePath = '${tempDir.path}/empty.db';
      final emptyDb = sqlite3.open(emptySqlitePath);
      emptyDb.execute('CREATE TABLE dummy (id INTEGER PRIMARY KEY);');
      emptyDb.close();

      final emptyVal = databaseService.validateDatabaseFile(emptySqlitePath);
      expect(emptyVal.isValid, isFalse);
      expect(emptyVal.errors.any((e) => e.code == 'MISSING_REQUIRED_TABLE'), isTrue);

      // 4c. Incompatible engine version
      final incompatPath = '${tempDir.path}/incompat.db';
      final incompatDb = sqlite3.open(incompatPath);
      incompatDb.execute(DatabaseSchema.worldSchemaSql);
      incompatDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v99', 1, '99.0.0', 999, '2026-10-25');
      ''');
      incompatDb.close();

      final incompatVal = databaseService.validateDatabaseFile(incompatPath);
      expect(incompatVal.isValid, isFalse);
      expect(incompatVal.errors.any((e) => e.code == 'INCOMPATIBLE_ENGINE_VERSION'), isTrue);
    });

    test('5. Safe import failure without damaging the current database', () {
      final validTargetPath = '${tempDir.path}/current_active_world.db';

      // Export currently valid worldDb as active DB
      databaseService.exportDatabaseInstance(
        db: worldDb,
        targetFilePath: validTargetPath,
      );
      expect(File(validTargetPath).existsSync(), isTrue);
      final originalSize = File(validTargetPath).lengthSync();

      // Create a corrupted candidate file
      final corruptCandidate = '${tempDir.path}/corrupt_update.db';
      File(corruptCandidate).writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      // Attempt to import the corrupt update into the active DB
      final result = databaseService.importWorldDatabase(
        sourceFilePath: corruptCandidate,
        targetFilePath: validTargetPath,
      );

      // Import MUST fail cleanly
      expect(result.isSuccess, isFalse);

      // Active target database MUST remain completely untouched, with exact original size
      expect(File(validTargetPath).existsSync(), isTrue);
      expect(File(validTargetPath).lengthSync(), equals(originalSize));

      // Active target database can still be opened and queried perfectly
      final activeDb = sqlite3.open(validTargetPath);
      final check = DatabaseValidator.validateWorldDatabase(activeDb);
      expect(check.isValid, isTrue);
      activeDb.close();
    });

    test('6. Adding supported football data without Dart code changes', () {
      // Add a third club, its team, player, and squad contract purely through SQLite
      worldDb.execute('''
        INSERT INTO clubs (id, name, short_name, country_code, city, reputation)
        VALUES ('c_tot', 'Tottenham', 'TOT', 'ENG', 'London', 80);

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation)
        VALUES ('t_tot_sen', 'c_tot', 'Tottenham Senior', 'TOT', 'SENIOR', 80);

        INSERT INTO players (
          id, first_name, last_name, birth_date, nationality_code, primary_position, overall_rating
        ) VALUES (
          'p_son', 'Heung-min', 'Son', '1992-07-08', 'KOR', 'LW', 87
        );

        INSERT INTO squad_contracts (id, player_id, team_id, squad_number, wage_per_week, contract_expiry_year)
        VALUES ('sc_son_tot', 'p_son', 't_tot_sen', 7, 190000, 2026);
      ''');

      // DatabaseValidator accepts it dynamically
      final validation = DatabaseValidator.validateWorldDatabase(worldDb);
      expect(validation.isValid, isTrue);

      // Start career with the new club and players
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_sql_extension',
        saveName: 'SQL Extension Career',
        userTeamId: 't_tot_sen',
        startYear: 2026,
      );

      // Save database accurately snapshot the dynamically added club, player, and contract
      final playerInSave = saveDb.select("SELECT * FROM players WHERE id = 'p_son';");
      expect(playerInSave.isNotEmpty, isTrue);
      expect(playerInSave.first['first_name'], equals('Heung-min'));

      final contractInSave = saveDb.select("SELECT * FROM squad_contracts WHERE id = 'sc_son_tot';");
      expect(contractInSave.isNotEmpty, isTrue);
      expect(contractInSave.first['wage_per_week'], equals(190000));
    });

    test('7. Keeping active career saves isolated from world database changes', () {
      // Start a career save from worldDb
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_isolation_p5',
        saveName: 'Isolation P5',
        userTeamId: 't_ars_sen',
        startYear: 2026,
      );

      // Verify saveDb holds its own snapshots of players, clubs, teams, and squad contracts
      expect(saveDb.select('SELECT COUNT(*) as c FROM clubs;').first['c'], equals(2));
      expect(saveDb.select('SELECT COUNT(*) as c FROM teams;').first['c'], equals(3));
      expect(saveDb.select('SELECT COUNT(*) as c FROM players;').first['c'], equals(2));
      expect(saveDb.select('SELECT COUNT(*) as c FROM squad_contracts;').first['c'], equals(2));

      // NOW: Completely wipe or replace worldDb as if user imported a totally different database
      worldDb.execute('''
        DELETE FROM squad_contracts;
        DELETE FROM player_positions;
        DELETE FROM players;
        DELETE FROM default_participants;
        DELETE FROM competition_rules;
        DELETE FROM competition_stages;
        DELETE FROM competitions;
        DELETE FROM teams;
        DELETE FROM clubs;
        DELETE FROM stadiums;
        DELETE FROM countries;
      ''');

      // Verify worldDb is completely empty
      expect(worldDb.select('SELECT COUNT(*) as c FROM players;').first['c'], equals(0));
      expect(worldDb.select('SELECT COUNT(*) as c FROM clubs;').first['c'], equals(0));

      // In stark contrast, saveDb retains all clubs, players, contracts, and fixtures!
      expect(saveDb.select('SELECT COUNT(*) as c FROM clubs;').first['c'], equals(2));
      expect(saveDb.select('SELECT COUNT(*) as c FROM teams;').first['c'], equals(3));
      expect(saveDb.select('SELECT COUNT(*) as c FROM players;').first['c'], equals(2));
      expect(saveDb.select('SELECT COUNT(*) as c FROM squad_contracts;').first['c'], equals(2));

      // The career save is completely unharmed and operational!
      final saka = saveDb.select("SELECT * FROM players WHERE id = 'p_saka';").first;
      expect(saka['last_name'], equals('Saka'));
    });

    test('8. Compatibility with the existing competition and calendar systems', () {
      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_compat_p5',
        saveName: 'Compatibility P5',
        userTeamId: 't_ars_sen',
        startYear: 2026,
      );

      // Calendar advances date cleanly
      final day1 = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(day1.nextDate, equals(DateTime(2026, 8, 2)));

      // Fast forward to season match date (2026-08-15)
      saveDb.execute("UPDATE career_saves SET current_calendar_date = '2026-08-15';");

      final todayMatches = calendarManager.getTodaysFixtures(saveDb);
      expect(todayMatches.isNotEmpty, isTrue);
      expect(todayMatches.first.matchDate, equals('2026-08-15'));

      // Advancing Day 15 simulates matches and updates standings
      final day15 = calendarManager.advanceOneDay(saveDb: saveDb, worldDb: worldDb);
      expect(day15.playedFixtures.isNotEmpty, isTrue);

      final standings = saveDb.select('SELECT * FROM standings WHERE played > 0;');
      expect(standings.length, equals(2)); // Both Arsenal and Chelsea played
    });
  });
}
