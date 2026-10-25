import 'package:sqlite3/sqlite3.dart';
import '../calendar/fixture_scheduler.dart';
import '../database/database_validator.dart';
import '../database/schema.dart';
import 'competition_engine.dart';
import 'models/competition.dart';

class CareerManager {
  final CompetitionEngine engine;

  CareerManager({CompetitionEngine? engine})
      : engine = engine ?? CompetitionEngine();

  /// Creates a new Career Save database snapshot from the given World Database.
  /// This completely isolates the active career from future changes or replacement of world.db.
  void startNewCareer({
    required Database worldDb,
    required Database saveDb,
    required String saveId,
    required String saveName,
    required String userTeamId,
    required int startYear,
  }) {
    // 1. Validate World DB first
    final validation = DatabaseValidator.validateWorldDatabase(worldDb);
    if (!validation.isValid) {
      throw StateError('Cannot create career from invalid world database: ${validation.errors.join("; ")}');
    }

    // 2. Initialize Save Schema
    saveDb.execute(DatabaseSchema.saveSchemaSql);

    // 3. Record Career Save info
    final metaRow = worldDb.select('SELECT dataset_version, schema_version FROM dataset_metadata LIMIT 1;').first;
    final datasetVersion = metaRow['dataset_version'] as String;
    final schemaVersion = metaRow['schema_version'] as int;

    saveDb.execute(
      '''
      INSERT INTO career_saves (
        id, save_name, user_team_id, created_at, current_calendar_date,
        dataset_version, schema_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        saveId,
        saveName,
        userTeamId,
        DateTime.now().toIso8601String(),
        '$startYear-08-01',
        datasetVersion,
        schemaVersion,
      ],
    );

    // 3b. Snapshot World entities (clubs, teams, players, squad contracts) into Save DB
    // This completely isolates career-save data from subsequent world database changes or replacement
    final clubRows = worldDb.select('SELECT * FROM clubs;');
    for (final c in clubRows) {
      saveDb.execute(
        '''
        INSERT INTO clubs (
          id, name, short_name, country_code, city, reputation,
          primary_color, secondary_color, stadium_id, stadium_name, stadium_capacity
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        ''',
        [
          c['id'], c['name'], c['short_name'], c['country_code'], c['city'],
          c['reputation'], c['primary_color'], c['secondary_color'],
          c['stadium_id'], c['stadium_name'], c['stadium_capacity']
        ],
      );
    }

    final teamRows = worldDb.select('SELECT * FROM teams;');
    for (final t in teamRows) {
      saveDb.execute(
        '''
        INSERT INTO teams (id, club_id, country_code, name, short_name, team_category, reputation)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        ''',
        [t['id'], t['club_id'], t['country_code'], t['name'], t['short_name'], t['team_category'], t['reputation']],
      );
    }

    final playerRows = worldDb.select('SELECT * FROM players;');
    for (final p in playerRows) {
      saveDb.execute(
        '''
        INSERT INTO players (
          id, first_name, last_name, birth_date, nationality_code, preferred_foot,
          primary_position, secondary_positions_json, overall_rating, pace, shooting,
          passing, dribbling, defending, physical, goalkeeping, attributes_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        ''',
        [
          p['id'], p['first_name'], p['last_name'], p['birth_date'], p['nationality_code'],
          p['preferred_foot'], p['primary_position'], p['secondary_positions_json'] ?? '[]',
          p['overall_rating'], p['pace'], p['shooting'], p['passing'], p['dribbling'],
          p['defending'], p['physical'], p['goalkeeping'], p['attributes_json']
        ],
      );
    }

    final posRows = worldDb.select('SELECT * FROM player_positions;');
    for (final pr in posRows) {
      saveDb.execute(
        '''
        INSERT INTO player_positions (player_id, position, is_primary, proficiency)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(player_id, position) DO NOTHING;
        ''',
        [pr['player_id'], pr['position'], pr['is_primary'], pr['proficiency']],
      );
    }

    final contractRows = worldDb.select('SELECT * FROM squad_contracts;');
    for (final sc in contractRows) {
      saveDb.execute(
        '''
        INSERT INTO squad_contracts (id, player_id, team_id, squad_number, wage_per_week, contract_expiry_year, contract_start_year)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
        ''',
        [
          sc['id'], sc['player_id'], sc['team_id'], sc['squad_number'],
          sc['wage_per_week'], sc['contract_expiry_year'], sc['contract_start_year']
        ],
      );
    }

    // 4. Create First Season
    final seasonId = '${saveId}_season_$startYear';
    final seasonStartStr = '$startYear-08-15';
    final seasonEndStr = '${startYear + 1}-05-31';
    saveDb.execute(
      '''
      INSERT INTO career_seasons (id, save_id, season_year, start_date, end_date, status)
      VALUES (?, ?, ?, ?, ?, 'IN_PROGRESS');
      ''',
      [seasonId, saveId, startYear, seasonStartStr, seasonEndStr],
    );

    // 5. Discover all competitions in World DB and instantiate them into Save DB
    final compRows = worldDb.select('SELECT id FROM competitions;');
    for (final c in compRows) {
      final compId = c['id'] as String;
      final seasonCompId = '${seasonId}_$compId';

      // Find first stage
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
        [seasonCompId, seasonId, compId, firstStageId],
      );

      // Copy default participants as a frozen snapshot into Save DB
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

    // 6. Generate initial fixtures in Save DB
    final stages = _loadStages(worldDb);
    final rules = _loadRules(worldDb);
    final stageParticipants = _loadParticipants(saveDb, seasonId);

    engine.initializeSeasonFixtures(
      saveDb: saveDb,
      seasonId: seasonId,
      seasonStartDate: DateTime(startYear, 8, 15),
      stageParticipants: stageParticipants,
      stages: stages,
      rules: rules,
    );

    // Resolve any initial date clashes across competitions
    FixtureScheduler().resolveConflicts(saveDb, seasonId);
  }

  /// Simulates matches until all current competitions for this season are complete.
  void simulateSeason({
    required Database worldDb,
    required Database saveDb,
    required String seasonId,
  }) {
    final stages = _loadStages(worldDb);
    final rules = _loadRules(worldDb);
    final reputations = _loadTeamReputations(worldDb);

    int maxIterations = 100;
    while (maxIterations-- > 0) {
      final scheduledCountRow = saveDb.select(
        '''
        SELECT COUNT(*) as count
        FROM fixtures f
        JOIN season_competitions sc ON f.season_competition_id = sc.id
        WHERE sc.season_id = ? AND f.status = 'SCHEDULED';
        ''',
        [seasonId],
      );
      final scheduledCount = scheduledCountRow.first['count'] as int;
      if (scheduledCount == 0) {
        break; // No more scheduled matches (including newly progressed rounds)
      }

      engine.simulatePendingFixtures(
        saveDb: saveDb,
        seasonId: seasonId,
        stages: stages,
        rules: rules,
        teamReputations: reputations,
      );
    }
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
