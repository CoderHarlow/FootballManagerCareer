import 'package:sqlite3/sqlite3.dart';
import 'formats/format_handler.dart';
import 'formats/group_stage_handler.dart';
import 'formats/knockout_handler.dart';
import 'formats/round_robin_handler.dart';
import 'formats/two_legged_tie_handler.dart';
import 'models/competition.dart';
import 'simulation/match_simulator.dart';

class CompetitionEngine {
  final Map<FormatType, FormatHandler> _formatHandlers = {};
  final MatchSimulator _matchSimulator;

  CompetitionEngine({MatchSimulator? matchSimulator})
      : _matchSimulator = matchSimulator ?? MatchSimulator() {
    registerFormatHandler(RoundRobinFormatHandler());
    registerFormatHandler(SingleEliminationFormatHandler());
    registerFormatHandler(TwoLeggedTieFormatHandler());
    registerFormatHandler(GroupStageToKnockoutFormatHandler());
  }

  MatchSimulator get matchSimulator => _matchSimulator;

  void registerFormatHandler(FormatHandler handler) {
    _formatHandlers[handler.formatType] = handler;
  }

  FormatHandler getHandler(FormatType formatType) {
    final handler = _formatHandlers[formatType];
    if (handler == null) {
      throw UnsupportedError(
        'No FormatHandler registered for format "${formatType.toDbString()}". '
        'New competition behaviours require registering a custom FormatHandler in the engine.',
      );
    }
    return handler;
  }

  /// Initializes fixtures for all competitions in an active season if not already created.
  void initializeSeasonFixtures({
    required Database saveDb,
    required String seasonId,
    required DateTime seasonStartDate,
    required Map<String, List<String>> stageParticipants,
    required Map<String, CompetitionStage> stages,
    required Map<String, CompetitionRules> rules,
  }) {
    final compRows = saveDb.select(
      'SELECT id, competition_id, current_stage_id FROM season_competitions WHERE season_id = ?;',
      [seasonId],
    );

    for (final compRow in compRows) {
      final seasonCompId = compRow['id'] as String;
      final currentStageId = compRow['current_stage_id'] as String;
      final stage = stages[currentStageId];
      final rule = rules[currentStageId];
      final participants = stageParticipants[currentStageId] ?? [];

      if (stage == null || rule == null) {
        throw StateError('Missing stage or rules definition for stage "$currentStageId"');
      }

      // Check if fixtures already exist
      final countRow = saveDb.select(
        'SELECT COUNT(*) as count FROM fixtures WHERE season_competition_id = ? AND stage_id = ?;',
        [seasonCompId, currentStageId],
      );
      final existingCount = countRow.first['count'] as int;
      if (existingCount > 0) continue;

      final handler = getHandler(stage.formatType);

      if (handler is GroupStageToKnockoutFormatHandler) {
        final pRows = saveDb.select(
          'SELECT team_id, group_index FROM season_participants WHERE season_competition_id = ? AND stage_id = ?;',
          [seasonCompId, currentStageId],
        );
        final participantMap = <String, int>{};
        for (final p in pRows) {
          participantMap[p['team_id'] as String] = p['group_index'] as int? ?? 0;
        }
        handler.setTeamGroupIndices(participantMap);
      }

      final fixtures = handler.generateInitialFixtures(
        seasonCompetitionId: seasonCompId,
        stage: stage,
        rules: rule,
        teamIds: participants,
        seasonStartDate: seasonStartDate,
      );

      // Persist generated fixtures
      for (final f in fixtures) {
        saveDb.execute(
          '''
          INSERT INTO fixtures (
            id, season_competition_id, stage_id, round_number, leg_number, match_date,
            home_team_id, away_team_id, status
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
          ''',
          [
            f.id,
            f.seasonCompetitionId,
            f.stageId,
            f.roundNumber,
            f.legNumber,
            f.matchDate,
            f.homeTeamId,
            f.awayTeamId,
            f.status.toDbString(),
          ],
        );
      }
    }
  }

  /// Simulates all scheduled fixtures for a given calendar date or round,
  /// updates standings, and advances stages if rounds complete.
  void simulatePendingFixtures({
    required Database saveDb,
    required String seasonId,
    required Map<String, CompetitionStage> stages,
    required Map<String, CompetitionRules> rules,
    required Map<String, int> teamReputations,
  }) {
    final fixtureRows = saveDb.select(
      '''
      SELECT f.*, sc.competition_id
      FROM fixtures f
      JOIN season_competitions sc ON f.season_competition_id = sc.id
      WHERE sc.season_id = ? AND f.status = 'SCHEDULED'
      ORDER BY f.round_number ASC, f.leg_number ASC, f.match_date ASC;
      ''',
      [seasonId],
    );

    if (fixtureRows.isEmpty) return;

    for (final row in fixtureRows) {
      final fixture = Fixture.fromMap(row);
      final stage = stages[fixture.stageId]!;
      final rule = rules[fixture.stageId]!;

      final homeRep = teamReputations[fixture.homeTeamId] ?? 50;
      final awayRep = teamReputations[fixture.awayTeamId] ?? 50;

      if (fixture.isLeg2) {
        // Look up corresponding Leg 1 fixture
        final leg1Rows = saveDb.select(
          '''
          SELECT * FROM fixtures
          WHERE season_competition_id = ? AND stage_id = ? AND round_number = ?
            AND home_team_id = ? AND away_team_id = ? AND leg_number = 1;
          ''',
          [
            fixture.seasonCompetitionId,
            fixture.stageId,
            fixture.roundNumber,
            fixture.awayTeamId,
            fixture.homeTeamId,
          ],
        );

        if (leg1Rows.isNotEmpty) {
          final leg1 = Fixture.fromMap(leg1Rows.first);
          _matchSimulator.simulateSecondLeg(
            fixture,
            leg1,
            homeReputation: homeRep,
            awayReputation: awayRep,
            rules: rule.matchRules,
          );
        } else {
          _matchSimulator.simulateMatch(
            fixture,
            homeReputation: homeRep,
            awayReputation: awayRep,
            rules: rule.matchRules,
          );
        }
      } else if (stage.formatType == FormatType.twoLeggedTie) {
        // Leg 1 of a two-legged tie cannot be decided by extra time or penalties
        _matchSimulator.simulateMatch(
          fixture,
          homeReputation: homeRep,
          awayReputation: awayRep,
          rules: rule.matchRules.copyWith(extraTime: false, penalties: false),
        );
      } else {
        _matchSimulator.simulateMatch(
          fixture,
          homeReputation: homeRep,
          awayReputation: awayRep,
          rules: rule.matchRules,
        );
      }

      // Save match results to DB
      saveDb.execute(
        '''
        UPDATE fixtures
        SET home_score = ?, away_score = ?, home_extra_score = ?, away_extra_score = ?,
            home_pk_score = ?, away_pk_score = ?, status = ?
        WHERE id = ?;
        ''',
        [
          fixture.homeScore,
          fixture.awayScore,
          fixture.homeExtraScore,
          fixture.awayExtraScore,
          fixture.homePkScore,
          fixture.awayPkScore,
          fixture.status.toDbString(),
          fixture.id,
        ],
      );
    }

    // After simulating matches, update standings and stage progressions
    updateStandingsAndProgression(
      saveDb: saveDb,
      seasonId: seasonId,
      stages: stages,
      rules: rules,
    );
  }

  void updateStandingsAndProgression({
    required Database saveDb,
    required String seasonId,
    required Map<String, CompetitionStage> stages,
    required Map<String, CompetitionRules> rules,
  }) {
    final compRows = saveDb.select(
      'SELECT id, competition_id, current_stage_id, status FROM season_competitions WHERE season_id = ?;',
      [seasonId],
    );

    for (final compRow in compRows) {
      final seasonCompId = compRow['id'] as String;
      final currentStageId = compRow['current_stage_id'] as String;
      final stage = stages[currentStageId];
      final rule = rules[currentStageId];
      if (stage == null || rule == null) continue;

      final handler = getHandler(stage.formatType);

      if (handler is GroupStageToKnockoutFormatHandler) {
        final pRows = saveDb.select(
          'SELECT team_id, group_index FROM season_participants WHERE season_competition_id = ? AND stage_id = ?;',
          [seasonCompId, currentStageId],
        );
        final participantMap = <String, int>{};
        for (final p in pRows) {
          participantMap[p['team_id'] as String] = p['group_index'] as int? ?? 0;
        }
        handler.setTeamGroupIndices(participantMap);
      }

      // Load all fixtures for this stage
      final stageFixtureRows = saveDb.select(
        'SELECT * FROM fixtures WHERE season_competition_id = ? AND stage_id = ? ORDER BY round_number ASC, leg_number ASC;',
        [seasonCompId, currentStageId],
      );
      final stageFixtures = stageFixtureRows.map((r) => Fixture.fromMap(r)).toList();

      // Load participants
      final participantRows = saveDb.select(
        'SELECT team_id FROM season_participants WHERE season_competition_id = ? AND stage_id = ?;',
        [seasonCompId, currentStageId],
      );
      final teamIds = participantRows.map((r) => r['team_id'] as String).toList();

      // 1. Calculate & persist Standings (for round-robin and group stages)
      final standings = handler.calculateStandings(
        seasonCompetitionId: seasonCompId,
        stageId: currentStageId,
        teamIds: teamIds,
        stageFixtures: stageFixtures,
        rules: rule,
      );

      for (final s in standings) {
        saveDb.execute(
          '''
          INSERT INTO standings (
            season_competition_id, stage_id, group_index, team_id,
            played, won, drawn, lost, goals_for, goals_against, goal_difference, points, rank
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(season_competition_id, stage_id, group_index, team_id) DO UPDATE SET
            played = excluded.played,
            won = excluded.won,
            drawn = excluded.drawn,
            lost = excluded.lost,
            goals_for = excluded.goals_for,
            goals_against = excluded.goals_against,
            goal_difference = excluded.goal_difference,
            points = excluded.points,
            rank = excluded.rank;
          ''',
          [
            s.seasonCompetitionId,
            s.stageId,
            s.groupIndex,
            s.teamId,
            s.played,
            s.won,
            s.drawn,
            s.lost,
            s.goalsFor,
            s.goalsAgainst,
            s.goalDifference,
            s.points,
            s.rank,
          ],
        );
      }

      // 2. Stage progression check (e.g. next round of knockout cup)
      final lastDate = stageFixtures.isNotEmpty
          ? DateTime.parse(stageFixtures.last.matchDate)
          : DateTime.now();

      final nextFixtures = handler.progressStage(
        seasonCompetitionId: seasonCompId,
        stage: stage,
        rules: rule,
        currentFixtures: stageFixtures,
        lastMatchDate: lastDate,
      );

      if (nextFixtures.isNotEmpty) {
        for (final f in nextFixtures) {
          saveDb.execute(
            '''
            INSERT INTO fixtures (
              id, season_competition_id, stage_id, round_number, leg_number, match_date,
              home_team_id, away_team_id, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            ''',
            [
              f.id,
              f.seasonCompetitionId,
              f.stageId,
              f.roundNumber,
              f.legNumber,
              f.matchDate,
              f.homeTeamId,
              f.awayTeamId,
              f.status.toDbString(),
            ],
          );
        }
      }

      // 3. Check if current stage is finished
      // Reload fixtures to include any freshly generated
      final updatedFixtureRows = saveDb.select(
        'SELECT * FROM fixtures WHERE season_competition_id = ? AND stage_id = ?;',
        [seasonCompId, currentStageId],
      );
      final updatedFixtures = updatedFixtureRows.map((r) => Fixture.fromMap(r)).toList();

      if (handler.isStageComplete(stage, updatedFixtures)) {
        // Check if there is a next stage in this competition
        final nextStages = stages.values
            .where((s) => s.competitionId == compRow['competition_id'] && s.stageOrder > stage.stageOrder)
            .toList()
          ..sort((a, b) => a.stageOrder.compareTo(b.stageOrder));

        if (nextStages.isNotEmpty) {
          final targetStage = nextStages.first;
          final targetRule = rules[targetStage.id]!;

          // Select qualified teams from current stage standings
          final qualifyCount = targetRule.teamCount;
          final qualifiedTeams = standings.take(qualifyCount).map((s) => s.teamId).toList();

          // Advance season_competitions to targetStage
          saveDb.execute(
            'UPDATE season_competitions SET current_stage_id = ? WHERE id = ?;',
            [targetStage.id, seasonCompId],
          );

          // Insert season_participants for targetStage
          for (int i = 0; i < qualifiedTeams.length; i++) {
            saveDb.execute(
              '''
              INSERT INTO season_participants (season_competition_id, stage_id, team_id, group_index, seed)
              VALUES (?, ?, ?, 0, ?)
              ON CONFLICT(season_competition_id, stage_id, team_id) DO NOTHING;
              ''',
              [seasonCompId, targetStage.id, qualifiedTeams[i], i + 1],
            );
          }

          // Generate fixtures for targetStage
          final targetHandler = getHandler(targetStage.formatType);
          final nextStageStartDate = DateTime.parse(updatedFixtures.last.matchDate).add(const Duration(days: 7));
          final targetFixtures = targetHandler.generateInitialFixtures(
            seasonCompetitionId: seasonCompId,
            stage: targetStage,
            rules: targetRule,
            teamIds: qualifiedTeams,
            seasonStartDate: nextStageStartDate,
          );

          for (final f in targetFixtures) {
            saveDb.execute(
              '''
              INSERT INTO fixtures (
                id, season_competition_id, stage_id, round_number, leg_number, match_date,
                home_team_id, away_team_id, status
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
              ''',
              [
                f.id,
                f.seasonCompetitionId,
                f.stageId,
                f.roundNumber,
                f.legNumber,
                f.matchDate,
                f.homeTeamId,
                f.awayTeamId,
                f.status.toDbString(),
              ],
            );
          }
        } else {
          // Final stage complete: crown champion!
          final winner = handler.getStageWinner(stage, rule, updatedFixtures, standings);
          if (winner != null) {
            saveDb.execute(
              'UPDATE season_competitions SET status = ?, winner_team_id = ? WHERE id = ?;',
              ['COMPLETED', winner, seasonCompId],
            );
          }
        }
      }
    }
  }
}
