import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:football_manager_career/core/database/schema.dart';
import 'package:football_manager_career/core/engine/career_manager.dart';
import 'package:football_manager_career/core/engine/formats/two_legged_tie_handler.dart';
import 'package:football_manager_career/core/engine/models/competition.dart';
import 'package:football_manager_career/core/engine/simulation/match_simulator.dart';

void main() {
  group('Two-Legged Tie Engine Tests', () {
    test('Calculates winner by higher aggregate score without extra time', () {
      final leg1 = Fixture(
        id: 'f1_leg1',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 1,
        matchDate: '2026-09-01',
        homeTeamId: 'team_a',
        awayTeamId: 'team_b',
        homeScore: 3,
        awayScore: 1,
        status: FixtureStatus.played,
      );

      final leg2 = Fixture(
        id: 'f1_leg2',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 2,
        matchDate: '2026-09-08',
        homeTeamId: 'team_b',
        awayTeamId: 'team_a',
        homeScore: 1,
        awayScore: 0,
        status: FixtureStatus.played,
      );

      // Aggregate: Team A (3 + 0 = 3), Team B (1 + 1 = 2) => Team A wins
      final winner = TwoLeggedTieFormatHandler.resolveTieWinner(
        leg1,
        leg2,
        const MatchRules(awayGoals: true),
      );
      expect(winner, equals('team_a'));
    });

    test('Away-goals rule enabled: advances team with more away goals when aggregate is tied', () {
      // Leg 1: Team A 1 - 2 Team B (at Team A's home, Team B has 2 away goals)
      final leg1 = Fixture(
        id: 'f2_leg1',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 1,
        matchDate: '2026-09-01',
        homeTeamId: 'team_a',
        awayTeamId: 'team_b',
        homeScore: 1,
        awayScore: 2,
        status: FixtureStatus.played,
      );

      // Leg 2: Team B 0 - 1 Team A (at Team B's home, Team A has 1 away goal)
      final leg2 = Fixture(
        id: 'f2_leg2',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 2,
        matchDate: '2026-09-08',
        homeTeamId: 'team_b',
        awayTeamId: 'team_a',
        homeScore: 0,
        awayScore: 1,
        status: FixtureStatus.played,
      );

      // Aggregate is 2 - 2.
      // Team B has 2 away goals, Team A has 1 away goal.
      final winner = TwoLeggedTieFormatHandler.resolveTieWinner(
        leg1,
        leg2,
        const MatchRules(awayGoals: true),
      );
      expect(winner, equals('team_b'), reason: 'Team B should win on away goals (2 vs 1)');
    });

    test('Away-goals rule disabled: aggregate tie triggers extra time / penalties', () {
      final leg1 = Fixture(
        id: 'f3_leg1',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 1,
        matchDate: '2026-09-01',
        homeTeamId: 'team_a',
        awayTeamId: 'team_b',
        homeScore: 1,
        awayScore: 2,
        status: FixtureStatus.played,
      );

      final leg2 = Fixture(
        id: 'f3_leg2',
        seasonCompetitionId: 'sc1',
        stageId: 'st1',
        roundNumber: 1,
        legNumber: 2,
        matchDate: '2026-09-08',
        homeTeamId: 'team_b',
        awayTeamId: 'team_a',
      );

      final simulator = MatchSimulator();

      // With awayGoals = false, aggregate 2-2 must NOT be decided by away goals
      // It should proceed to extra time and penalties
      simulator.simulateSecondLeg(
        leg2,
        leg1,
        homeReputation: 80,
        awayReputation: 80,
        rules: const MatchRules(
          awayGoals: false,
          extraTime: true,
          penalties: true,
        ),
      );

      expect(leg2.status, equals(FixtureStatus.played));
      final totalA = (leg1.homeScore ?? 0) + leg2.awayScore! + (leg2.awayExtraScore ?? 0);
      final totalB = (leg1.awayScore ?? 0) + leg2.homeScore! + (leg2.homeExtraScore ?? 0);

      if (totalA == totalB) {
        // If still tied after extra time, penalties must be recorded
        expect(leg2.homePkScore, isNotNull);
        expect(leg2.awayPkScore, isNotNull);
        expect(leg2.homePkScore, isNot(equals(leg2.awayPkScore)));
      }

      final winner = TwoLeggedTieFormatHandler.resolveTieWinner(
        leg1,
        leg2,
        const MatchRules(awayGoals: false, penalties: true),
      );
      expect(['team_a', 'team_b'], contains(winner));
    });

    test('Simulates complete 4-team two-legged tournament from database to champion', () {
      final worldDb = sqlite3.openInMemory();
      final saveDb = sqlite3.openInMemory();
      worldDb.execute(DatabaseSchema.worldSchemaSql);
      final careerManager = CareerManager();

      worldDb.execute('''
        INSERT INTO dataset_metadata (id, schema_version, dataset_version, min_engine_version, created_at)
        VALUES ('world_v1', 1, '1.0.0', 1, '2026-10-25');

        INSERT INTO competitions (id, code, name, short_name, scope, tier)
        VALUES ('euro_cup', 'ECUP', 'European Two-Legged Cup', 'EuroCup', 'CONTINENTAL', 1);

        INSERT INTO competition_stages (id, competition_id, stage_order, format_type)
        VALUES ('euro_stage_ko', 'euro_cup', 1, 'TWO_LEGGED_TIE');

        INSERT INTO competition_rules (
          stage_id, team_count, rounds_or_legs, points_win, points_draw, points_loss,
          tiebreaker_json, match_rules_json
        ) VALUES (
          'euro_stage_ko', 4, 2, 0, 0, 0,
          '[]',
          '{"extra_time": true, "penalties": true, "away_goals": true, "subs_max": 5}'
        );

        INSERT INTO clubs (id, name, short_name, country_code) VALUES
          ('c1', 'Real Madrid', 'RMA', 'ESP'),
          ('c2', 'Bayern Munich', 'BAY', 'GER'),
          ('c3', 'Paris Saint-Germain', 'PSG', 'FRA'),
          ('c4', 'Inter Milan', 'INT', 'ITA');

        INSERT INTO teams (id, club_id, name, short_name, team_category, reputation) VALUES
          ('t1', 'c1', 'Real Madrid First', 'RMA', 'SENIOR', 89),
          ('t2', 'c2', 'Bayern Munich First', 'BAY', 'SENIOR', 88),
          ('t3', 'c3', 'PSG First', 'PSG', 'SENIOR', 87),
          ('t4', 'c4', 'Inter Milan First', 'INT', 'SENIOR', 85);

        INSERT INTO default_participants (stage_id, team_id, seed) VALUES
          ('euro_stage_ko', 't1', 1),
          ('euro_stage_ko', 't2', 2),
          ('euro_stage_ko', 't3', 3),
          ('euro_stage_ko', 't4', 4);
      ''');

      careerManager.startNewCareer(
        worldDb: worldDb,
        saveDb: saveDb,
        saveId: 'save_two_legged',
        saveName: 'Euro Cup Career',
        userTeamId: 't1',
        startYear: 2026,
      );

      // Verify Round 1 (Semi-Finals) has 4 fixtures: 2 ties x 2 legs
      final r1Fixtures = saveDb.select(
        'SELECT * FROM fixtures WHERE round_number = 1 ORDER BY leg_number ASC;',
      );
      expect(r1Fixtures.length, equals(4));

      final leg1Matches = r1Fixtures.where((f) => f['leg_number'] == 1).toList();
      final leg2Matches = r1Fixtures.where((f) => f['leg_number'] == 2).toList();
      expect(leg1Matches.length, equals(2));
      expect(leg2Matches.length, equals(2));

      // Simulate the entire tournament
      careerManager.simulateSeason(
        worldDb: worldDb,
        saveDb: saveDb,
        seasonId: 'save_two_legged_season_2026',
      );

      // All fixtures must be played: 4 in Semi-Finals + 2 in Final = 6 fixtures total
      final allFixtures = saveDb.select('SELECT * FROM fixtures ORDER BY round_number ASC, leg_number ASC;');
      expect(allFixtures.length, equals(6), reason: '4-team two-legged cup must produce 6 matches total');
      expect(allFixtures.every((f) => f['status'] == 'PLAYED'), isTrue);

      final r2Fixtures = allFixtures.where((f) => f['round_number'] == 2).toList();
      expect(r2Fixtures.length, equals(2), reason: 'Final tie must have Leg 1 and Leg 2');

      // Verify Champion is crowned
      final compRecord = saveDb.select(
        "SELECT * FROM season_competitions WHERE competition_id = 'euro_cup';",
      ).first;
      expect(compRecord['status'], equals('COMPLETED'));
      expect(compRecord['winner_team_id'], isNotNull);

      final winnerId = compRecord['winner_team_id'] as String;
      final finalTeams = [r2Fixtures[0]['home_team_id'], r2Fixtures[0]['away_team_id']];
      expect(finalTeams, contains(winnerId));

      worldDb.close();
      saveDb.close();
    });
  });
}
