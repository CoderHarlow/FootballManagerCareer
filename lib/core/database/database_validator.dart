import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../engine/models/football_world.dart';
import 'schema.dart';

class ValidationError {
  final String code;
  final String message;
  final String? table;
  final String? entityId;

  const ValidationError({
    required this.code,
    required this.message,
    this.table,
    this.entityId,
  });

  @override
  String toString() {
    final entityPart = entityId != null ? ' (Entity: $entityId)' : '';
    return '[$code] $message$entityPart';
  }
}

class ValidationResult {
  final bool isValid;
  final List<ValidationError> errors;
  final List<String> warnings;

  const ValidationResult({
    required this.isValid,
    required this.errors,
    this.warnings = const [],
  });

  factory ValidationResult.success({List<String> warnings = const []}) {
    return ValidationResult(isValid: true, errors: const [], warnings: warnings);
  }

  factory ValidationResult.failure(List<ValidationError> errors, {List<String> warnings = const []}) {
    return ValidationResult(isValid: false, errors: errors, warnings: warnings);
  }
}

class DatabaseValidator {
  static const Set<String> supportedFormats = {
    'ROUND_ROBIN',
    'SINGLE_ELIMINATION',
    'TWO_LEGGED_TIE',
    'GROUP_STAGE_TO_KNOCKOUT',
  };

  static const Set<String> supportedTiebreakers = {
    'POINTS',
    'GOAL_DIFFERENCE',
    'GOALS_FOR',
    'HEAD_TO_HEAD',
    'WINS',
  };

  /// Performs a comprehensive validation on a World Database.
  static ValidationResult validateWorldDatabase(Database db) {
    final List<ValidationError> errors = [];
    final List<String> warnings = [];

    // 0. Required Tables Check
    const requiredTables = [
      'dataset_metadata',
      'competitions',
      'competition_stages',
      'competition_rules',
      'clubs',
      'teams',
      'default_participants',
      'players',
      'squad_contracts',
    ];
    try {
      final existingTables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      for (final req in requiredTables) {
        if (!existingTables.contains(req)) {
          errors.add(ValidationError(
            code: 'MISSING_REQUIRED_TABLE',
            message: 'World database is missing required table "$req".',
            table: req,
          ));
        }
      }
      if (errors.isNotEmpty) {
        return ValidationResult.failure(errors, warnings: warnings);
      }
    } catch (e) {
      errors.add(ValidationError(
        code: 'TABLE_CHECK_ERROR',
        message: 'Could not query sqlite_master for table definitions: $e',
      ));
      return ValidationResult.failure(errors, warnings: warnings);
    }

    // 1. Foreign Key Integrity Check
    try {
      final fkRows = db.select('PRAGMA foreign_key_check;');
      if (fkRows.isNotEmpty) {
        for (final row in fkRows) {
          final tableName = row['table']?.toString() ?? 'unknown';
          final rowId = row['rowid']?.toString() ?? 'unknown';
          errors.add(ValidationError(
            code: 'FOREIGN_KEY_VIOLATION',
            message: 'Foreign key constraint violated in table "$tableName" on rowid $rowId',
            table: tableName,
          ));
        }
      }
    } catch (e) {
      errors.add(ValidationError(
        code: 'PRAGMA_ERROR',
        message: 'Failed to run foreign_key_check: $e',
      ));
    }

    // 2. Metadata & Version Check
    try {
      final metaRows = db.select('SELECT * FROM dataset_metadata LIMIT 1;');
      if (metaRows.isEmpty) {
        errors.add(const ValidationError(
          code: 'MISSING_METADATA',
          message: 'Table dataset_metadata is empty. A valid dataset ID and version are required.',
          table: 'dataset_metadata',
        ));
      } else {
        final meta = metaRows.first;
        final minEngineVersion = meta['min_engine_version'] as int? ?? 1;
        if (minEngineVersion > DatabaseSchema.currentEngineVersion) {
          errors.add(ValidationError(
            code: 'INCOMPATIBLE_ENGINE_VERSION',
            message:
                'Database requires engine version $minEngineVersion, but current engine is ${DatabaseSchema.currentEngineVersion}. Please update the app.',
            table: 'dataset_metadata',
          ));
        }
      }
    } catch (e) {
      errors.add(ValidationError(
        code: 'METADATA_TABLE_ERROR',
        message: 'Could not query dataset_metadata: $e',
      ));
    }

    // 3. Competitions Validation
    final compRows = db.select('SELECT id, name FROM competitions;');
    if (compRows.isEmpty) {
      warnings.add('No competitions defined in this dataset.');
    }

    for (final comp in compRows) {
      final compId = comp['id'] as String;
      final compName = comp['name']?.toString() ?? compId;

      // Check stages exist
      final stageRows = db.select(
        'SELECT id, stage_order, format_type FROM competition_stages WHERE competition_id = ? ORDER BY stage_order ASC;',
        [compId],
      );

      if (stageRows.isEmpty) {
        errors.add(ValidationError(
          code: 'NO_STAGES_FOR_COMPETITION',
          message: 'Competition "$compName" has no stages defined.',
          table: 'competition_stages',
          entityId: compId,
        ));
        continue;
      }

      for (final stage in stageRows) {
        final stageId = stage['id'] as String;
        final formatType = (stage['format_type'] as String).toUpperCase();

        // 4. Validate Format Support
        if (!supportedFormats.contains(formatType)) {
          final formatsStr = supportedFormats.join(', ');
          errors.add(ValidationError(
            code: 'UNSUPPORTED_FORMAT',
            message:
                'Unsupported format "$formatType" in stage "$stageId". Supported formats are: $formatsStr. Completely new competition formats require engine code updates.',
            table: 'competition_stages',
            entityId: stageId,
          ));
          continue;
        }

        // 5. Validate Stage Rules
        final ruleRows = db.select(
          'SELECT * FROM competition_rules WHERE stage_id = ?;',
          [stageId],
        );

        if (ruleRows.isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_STAGE_RULES',
            message: 'No competition_rules found for stage "$stageId".',
            table: 'competition_rules',
            entityId: stageId,
          ));
          continue;
        }

        final rule = ruleRows.first;
        final teamCount = rule['team_count'] as int;
        final matchRulesRaw = rule['match_rules_json'] as String? ?? '{}';
        final tiebreakersRaw = rule['tiebreaker_json'] as String? ?? '[]';

        // Validate Knockout power-of-2 requirement
        if (formatType == 'SINGLE_ELIMINATION' || formatType == 'TWO_LEGGED_TIE') {
          if (teamCount < 2 || (teamCount & (teamCount - 1)) != 0) {
            errors.add(ValidationError(
              code: 'KNOCKOUT_NON_POWER_OF_TWO',
              message:
                  'Knockout stage "$stageId" specifies $teamCount teams. Knockout formats require a power-of-2 team count (2, 4, 8, 16, 32, 64). Non-power-of-2 byes or preliminary rounds require custom engine formats.',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }

          // Knockout must have extra time or penalties enabled
          try {
            final Map<String, dynamic> mr = jsonDecode(matchRulesRaw);
            final bool extraTime = mr['extra_time'] ?? false;
            final bool penalties = mr['penalties'] ?? false;
            if (!extraTime && !penalties) {
              errors.add(ValidationError(
                code: 'KNOCKOUT_NO_DECIDER',
                message:
                    'Knockout stage "$stageId" must enable "penalties" or "extra_time" in match_rules_json to resolve ties.',
                table: 'competition_rules',
                entityId: stageId,
              ));
            }
          } catch (_) {
            errors.add(ValidationError(
              code: 'INVALID_MATCH_RULES_JSON',
              message: 'match_rules_json in stage "$stageId" is not valid JSON.',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }
        }

        // Validate Group Stage to Knockout requirement
        if (formatType == 'GROUP_STAGE_TO_KNOCKOUT') {
          if (teamCount < 4) {
            errors.add(ValidationError(
              code: 'GROUP_STAGE_TOO_FEW_TEAMS',
              message: 'Group stage stage "$stageId" requires at least 4 teams (got $teamCount).',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }

          try {
            final Map<String, dynamic> mr = jsonDecode(matchRulesRaw);
            final bool extraTime = mr['extra_time'] ?? false;
            final bool penalties = mr['penalties'] ?? false;
            if (!extraTime && !penalties) {
              errors.add(ValidationError(
                code: 'KNOCKOUT_NO_DECIDER',
                message:
                    'Group-stage-to-knockout stage "$stageId" must enable "penalties" or "extra_time" in match_rules_json to resolve knockout draws.',
                table: 'competition_rules',
                entityId: stageId,
              ));
            }
          } catch (_) {
            errors.add(ValidationError(
              code: 'INVALID_MATCH_RULES_JSON',
              message: 'match_rules_json in stage "$stageId" is not valid JSON.',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }

          final groupCountRows = db.select(
            'SELECT COUNT(DISTINCT group_index) as gc FROM default_participants WHERE stage_id = ?;',
            [stageId],
          );
          final int groupCount = groupCountRows.isNotEmpty ? (groupCountRows.first['gc'] as int? ?? 1) : 1;

          final qualRulesRaw = rule['qualification_rules_json'] as String?;
          int qualifyPerGroup = 2;
          if (qualRulesRaw != null) {
            try {
              final Map<String, dynamic> qm = jsonDecode(qualRulesRaw);
              qualifyPerGroup = qm['qualify_per_group'] ?? qm['qualify_top'] ?? 2;
            } catch (_) {
              errors.add(ValidationError(
                code: 'INVALID_QUALIFICATION_RULES_JSON',
                message: 'qualification_rules_json in stage "$stageId" is not valid JSON.',
                table: 'competition_rules',
                entityId: stageId,
              ));
            }
          }

          final int totalQualified = groupCount * qualifyPerGroup;
          if (totalQualified < 2 || (totalQualified & (totalQualified - 1)) != 0) {
            errors.add(ValidationError(
              code: 'KNOCKOUT_NON_POWER_OF_TWO',
              message:
                  'Group stage stage "$stageId" produces $totalQualified qualified teams ($groupCount groups x $qualifyPerGroup qualified). Knockout brackets require a power-of-2 team count (2, 4, 8, 16, 32).',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }
        }

        // Validate Round Robin participant minimum
        if (formatType == 'ROUND_ROBIN' && teamCount < 2) {
          errors.add(ValidationError(
            code: 'ROUND_ROBIN_TOO_FEW_TEAMS',
            message: 'Round-robin stage "$stageId" requires at least 2 teams.',
            table: 'competition_rules',
            entityId: stageId,
          ));
        }

        // Validate Tiebreakers
        try {
          final List<dynamic> tbs = jsonDecode(tiebreakersRaw);
          for (final tb in tbs) {
            final tbStr = tb.toString().toUpperCase();
            if (!supportedTiebreakers.contains(tbStr)) {
              final supportedStr = supportedTiebreakers.join(', ');
              errors.add(ValidationError(
                code: 'UNSUPPORTED_TIEBREAKER',
                message:
                    'Stage "$stageId" specifies unsupported tiebreaker "$tbStr". Supported: $supportedStr.',
                table: 'competition_rules',
                entityId: stageId,
              ));
            }
          }
        } catch (_) {
          errors.add(ValidationError(
            code: 'INVALID_TIEBREAKER_JSON',
            message: 'tiebreaker_json in stage "$stageId" is not valid JSON.',
            table: 'competition_rules',
            entityId: stageId,
          ));
        }

        // 6. Validate Scheduling Rules if present
        final schedRulesRaw = rule['scheduling_rules_json'] as String?;
        if (schedRulesRaw != null && schedRulesRaw.trim().isNotEmpty) {
          try {
            final Map<String, dynamic> sm = jsonDecode(schedRulesRaw);
            if (sm.containsKey('match_interval_days')) {
              final interval = sm['match_interval_days'];
              if (interval is! int || interval <= 0) {
                errors.add(ValidationError(
                  code: 'INVALID_MATCH_INTERVAL',
                  message: 'match_interval_days in stage "$stageId" must be a positive integer (got $interval).',
                  table: 'competition_rules',
                  entityId: stageId,
                ));
              }
            }
            if (sm.containsKey('min_rest_days')) {
              final rest = sm['min_rest_days'];
              if (rest is! int || rest < 0) {
                errors.add(ValidationError(
                  code: 'INVALID_MIN_REST_DAYS',
                  message: 'min_rest_days in stage "$stageId" cannot be negative (got $rest).',
                  table: 'competition_rules',
                  entityId: stageId,
                ));
              }
            }
            if (sm.containsKey('preferred_match_day')) {
              final pmd = sm['preferred_match_day'];
              if (pmd is! int || pmd < 1 || pmd > 7) {
                errors.add(ValidationError(
                  code: 'INVALID_PREFERRED_MATCH_DAY',
                  message: 'preferred_match_day in stage "$stageId" must be between 1 (Monday) and 7 (Sunday).',
                  table: 'competition_rules',
                  entityId: stageId,
                ));
              }
            }
            if (sm.containsKey('start_date') && sm['start_date'] != null) {
              final startDateStr = sm['start_date'].toString();
              if (DateTime.tryParse(startDateStr) == null) {
                errors.add(ValidationError(
                  code: 'INVALID_START_DATE',
                  message: 'start_date in stage "$stageId" must be a valid ISO-8601 date (got "$startDateStr").',
                  table: 'competition_rules',
                  entityId: stageId,
                ));
              }
            }
          } catch (_) {
            errors.add(ValidationError(
              code: 'INVALID_SCHEDULING_RULES_JSON',
              message: 'scheduling_rules_json in stage "$stageId" is not valid JSON.',
              table: 'competition_rules',
              entityId: stageId,
            ));
          }
        }

        // 7. Validate Participants Count
        final participantRows = db.select(
          'SELECT COUNT(*) as count FROM default_participants WHERE stage_id = ?;',
          [stageId],
        );
        final actualParticipants = participantRows.first['count'] as int;
        if (actualParticipants != teamCount) {
          errors.add(ValidationError(
            code: 'PARTICIPANT_COUNT_MISMATCH',
            message:
                'Stage "$stageId" specifies team_count=$teamCount in competition_rules, but has $actualParticipants participants in default_participants.',
            table: 'default_participants',
            entityId: stageId,
          ));
        }
      }
    }
    // 4. Validate Clubs
    final clubRows = db.select('SELECT id, name, country_code, reputation FROM clubs;');
    for (final c in clubRows) {
      final rep = c['reputation'] as int? ?? 50;
      if (rep < 1 || rep > 100) {
        errors.add(ValidationError(
          code: 'INVALID_CLUB_REPUTATION',
          message: 'Club "${c['id']}" has reputation $rep out of allowed range [1, 100].',
          table: 'clubs',
          entityId: c['id'] as String,
        ));
      }
    }

    // 5. Validate Teams
    final teamRows = db.select('SELECT id, club_id, country_code, name, team_category, reputation FROM teams;');
    for (final t in teamRows) {
      final rep = t['reputation'] as int? ?? 50;
      final category = t['team_category'] as String;
      final clubId = t['club_id'] as String?;
      final countryCode = t['country_code'] as String?;

      if (rep < 1 || rep > 100) {
        errors.add(ValidationError(
          code: 'INVALID_TEAM_REPUTATION',
          message: 'Team "${t['id']}" has reputation $rep out of allowed range [1, 100].',
          table: 'teams',
          entityId: t['id'] as String,
        ));
      }

      if (category == 'NATIONAL') {
        if (countryCode == null || countryCode.trim().isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_NATIONAL_TEAM_COUNTRY',
            message: 'National team "${t['id']}" must specify a country_code.',
            table: 'teams',
            entityId: t['id'] as String,
          ));
        }
      } else {
        if (clubId == null || clubId.trim().isEmpty) {
          errors.add(ValidationError(
            code: 'MISSING_TEAM_CLUB_ID',
            message: 'Club team "${t['id']}" of category $category must reference a club_id.',
            table: 'teams',
            entityId: t['id'] as String,
          ));
        }
      }
    }

    // 6. Validate Players
    final playerRows = db.select('''
      SELECT id, first_name, last_name, birth_date, nationality_code,
             primary_position, secondary_positions_json, overall_rating,
             pace, shooting, passing, dribbling, defending, physical, goalkeeping
      FROM players;
    ''');
    for (final p in playerRows) {
      final pid = p['id'] as String;
      final primaryPos = p['primary_position'] as String;
      if (!FootballPositions.isValid(primaryPos)) {
        errors.add(ValidationError(
          code: 'UNSUPPORTED_POSITION',
          message: 'Player "$pid" specifies unsupported primary position "$primaryPos". Supported positions: ${FootballPositions.all.join(", ")}.',
          table: 'players',
          entityId: pid,
        ));
      }

      final bdate = p['birth_date'] as String;
      if (DateTime.tryParse(bdate) == null) {
        errors.add(ValidationError(
          code: 'INVALID_BIRTH_DATE',
          message: 'Player "$pid" has invalid birth_date "$bdate". Must be valid ISO-8601 (YYYY-MM-DD).',
          table: 'players',
          entityId: pid,
        ));
      }

      // Validate ratings 1-99
      final ratingKeys = [
        'overall_rating', 'pace', 'shooting', 'passing',
        'dribbling', 'defending', 'physical', 'goalkeeping'
      ];
      for (final k in ratingKeys) {
        final val = p[k] as int? ?? 60;
        if (val < 1 || val > 99) {
          errors.add(ValidationError(
            code: 'INVALID_PLAYER_ATTRIBUTE',
            message: 'Player "$pid" has attribute $k=$val out of allowed range [1, 99].',
            table: 'players',
            entityId: pid,
          ));
        }
      }

      // Validate secondary positions if any
      final secRaw = p['secondary_positions_json'] as String?;
      if (secRaw != null && secRaw.trim().isNotEmpty && secRaw != '[]') {
        try {
          final decoded = jsonDecode(secRaw);
          if (decoded is List) {
            for (final pos in decoded) {
              if (!FootballPositions.isValid(pos.toString())) {
                errors.add(ValidationError(
                  code: 'UNSUPPORTED_POSITION',
                  message: 'Player "$pid" specifies unsupported secondary position "$pos".',
                  table: 'players',
                  entityId: pid,
                ));
              }
            }
          } else {
            errors.add(ValidationError(
              code: 'INVALID_SECONDARY_POSITIONS',
              message: 'Player "$pid" secondary_positions_json must be a JSON array.',
              table: 'players',
              entityId: pid,
            ));
          }
        } catch (_) {
          errors.add(ValidationError(
            code: 'INVALID_SECONDARY_POSITIONS',
            message: 'Player "$pid" secondary_positions_json is not valid JSON.',
            table: 'players',
            entityId: pid,
          ));
        }
      }
    }

    // 7. Validate Squad Contracts
    final contractRows = db.select('SELECT id, player_id, team_id, wage_per_week, contract_expiry_year FROM squad_contracts;');
    for (final sc in contractRows) {
      final cid = sc['id'] as String;
      final wage = sc['wage_per_week'] as int? ?? 0;
      final expiry = sc['contract_expiry_year'] as int;

      if (wage < 0) {
        errors.add(ValidationError(
          code: 'INVALID_WAGE',
          message: 'Squad contract "$cid" cannot have negative wage ($wage).',
          table: 'squad_contracts',
          entityId: cid,
        ));
      }
      if (expiry < 1900) {
        errors.add(ValidationError(
          code: 'INVALID_CONTRACT_EXPIRY',
          message: 'Squad contract "$cid" has invalid expiry year ($expiry).',
          table: 'squad_contracts',
          entityId: cid,
        ));
      }
    }

    // Check duplicate contracts for same player in same team
    final dupContracts = db.select('''
      SELECT team_id, player_id, COUNT(*) as c
      FROM squad_contracts
      GROUP BY team_id, player_id
      HAVING c > 1;
    ''');
    for (final dc in dupContracts) {
      errors.add(ValidationError(
        code: 'DUPLICATE_PLAYER_CONTRACT',
        message: 'Player "${dc['player_id']}" has multiple active contracts in team "${dc['team_id']}" (${dc['c']} contracts).',
        table: 'squad_contracts',
        entityId: dc['player_id'] as String,
      ));
    }

    // 8. Validate Countries (if populated)
    final countryRows = db.select('SELECT id, name, code, continent, reputation FROM countries;');
    const validContinents = {
      'EUROPE', 'SOUTH_AMERICA', 'NORTH_AMERICA', 'AFRICA', 'ASIA', 'OCEANIA', 'OTHER'
    };
    for (final co in countryRows) {
      final cont = co['continent'] as String;
      final rep = co['reputation'] as int? ?? 50;
      if (!validContinents.contains(cont.toUpperCase())) {
        errors.add(ValidationError(
          code: 'INVALID_CONTINENT',
          message: 'Country "${co['id']}" specifies unsupported continent "$cont".',
          table: 'countries',
          entityId: co['id'] as String,
        ));
      }
      if (rep < 1 || rep > 100) {
        errors.add(ValidationError(
          code: 'INVALID_COUNTRY_REPUTATION',
          message: 'Country "${co['id']}" has reputation $rep out of allowed range [1, 100].',
          table: 'countries',
          entityId: co['id'] as String,
        ));
      }
    }

    // 9. Validate Stadiums (if populated)
    final stadiumRows = db.select('SELECT id, name, capacity FROM stadiums;');
    for (final st in stadiumRows) {
      final cap = st['capacity'] as int;
      if (cap <= 0) {
        errors.add(ValidationError(
          code: 'INVALID_STADIUM_CAPACITY',
          message: 'Stadium "${st['id']}" must have positive capacity (got $cap).',
          table: 'stadiums',
          entityId: st['id'] as String,
        ));
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.failure(errors, warnings: warnings);
    }
    return ValidationResult.success(warnings: warnings);
  }

  /// Validates a Career Save Database for scheduling consistency,
  /// absence of duplicate fixtures, valid match dates, and no same-club clashes.
  static ValidationResult validateSaveDatabase(Database saveDb) {
    final List<ValidationError> errors = [];
    final List<String> warnings = [];

    // 1. Check for Duplicate Fixtures
    final dupRows = saveDb.select('''
      SELECT season_competition_id, stage_id, round_number, leg_number, home_team_id, away_team_id, COUNT(*) as c
      FROM fixtures
      GROUP BY season_competition_id, stage_id, round_number, leg_number, home_team_id, away_team_id
      HAVING c > 1;
    ''');
    if (dupRows.isNotEmpty) {
      for (final dup in dupRows) {
        errors.add(ValidationError(
          code: 'DUPLICATE_FIXTURES',
          message:
              'Duplicate fixture detected: stage ${dup['stage_id']}, round ${dup['round_number']}, leg ${dup['leg_number']}, home ${dup['home_team_id']}, away ${dup['away_team_id']} (count: ${dup['c']})',
          table: 'fixtures',
        ));
      }
    }

    // 2. Check for Missing or Invalid Dates
    final invalidDateRows = saveDb.select('''
      SELECT id, match_date FROM fixtures WHERE match_date IS NULL OR match_date = '';
    ''');
    if (invalidDateRows.isNotEmpty) {
      for (final r in invalidDateRows) {
        errors.add(ValidationError(
          code: 'MISSING_FIXTURE_DATE',
          message: 'Fixture ${r['id']} has no match_date assigned.',
          table: 'fixtures',
          entityId: r['id']?.toString(),
        ));
      }
    }

    // Check parseable ISO dates
    final allFixtureRows = saveDb.select('SELECT id, match_date FROM fixtures WHERE match_date IS NOT NULL;');
    for (final r in allFixtureRows) {
      final dateStr = r['match_date'] as String;
      if (DateTime.tryParse(dateStr) == null) {
        errors.add(ValidationError(
          code: 'INVALID_FIXTURE_DATE',
          message: 'Fixture ${r['id']} has unparseable match_date "$dateStr".',
          table: 'fixtures',
          entityId: r['id'] as String,
        ));
      }
    }

    // 3. Check for Impossible Scheduling Constraints (Same club scheduled twice on same date)
    final clashRows = saveDb.select('''
      SELECT team_id, match_date, COUNT(*) as c
      FROM (
        SELECT home_team_id AS team_id, match_date FROM fixtures WHERE status != 'POSTPONED'
        UNION ALL
        SELECT away_team_id AS team_id, match_date FROM fixtures WHERE status != 'POSTPONED'
      )
      GROUP BY team_id, match_date
      HAVING c > 1;
    ''');
    if (clashRows.isNotEmpty) {
      for (final clash in clashRows) {
        errors.add(ValidationError(
          code: 'SAME_DATE_FIXTURE_CLASH',
          message:
              'Team ${clash['team_id']} is scheduled to play multiple matches on the same date (${clash['match_date']}).',
          table: 'fixtures',
          entityId: clash['team_id']?.toString(),
        ));
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.failure(errors, warnings: warnings);
    }
    return ValidationResult.success(warnings: warnings);
  }
}
