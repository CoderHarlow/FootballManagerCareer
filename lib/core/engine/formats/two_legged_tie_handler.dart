import '../models/competition.dart';
import 'format_handler.dart';

class TwoLeggedTieFormatHandler implements FormatHandler {
  @override
  FormatType get formatType => FormatType.twoLeggedTie;

  @override
  List<Fixture> generateInitialFixtures({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<String> teamIds,
    required DateTime seasonStartDate,
  }) {
    if (teamIds.length < 2) return [];

    final List<Fixture> fixtures = [];
    int matchIndex = 1;
    final leg1DateStr = seasonStartDate.toIso8601String().split('T').first;
    final leg2DateStr = seasonStartDate.add(const Duration(days: 7)).toIso8601String().split('T').first;

    for (int i = 0; i < teamIds.length; i += 2) {
      if (i + 1 < teamIds.length) {
        final team1 = teamIds[i];
        final team2 = teamIds[i + 1];

        // Leg 1: Team 1 (home) vs Team 2 (away)
        fixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r1_m${matchIndex}_leg1',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: 1,
          legNumber: 1,
          matchDate: leg1DateStr,
          homeTeamId: team1,
          awayTeamId: team2,
        ));

        // Leg 2: Team 2 (home) vs Team 1 (away)
        fixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r1_m${matchIndex}_leg2',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: 1,
          legNumber: 2,
          matchDate: leg2DateStr,
          homeTeamId: team2,
          awayTeamId: team1,
        ));

        matchIndex++;
      }
    }

    return fixtures;
  }

  @override
  List<Standing> calculateStandings({
    required String seasonCompetitionId,
    required String stageId,
    required List<String> teamIds,
    required List<Fixture> stageFixtures,
    required CompetitionRules rules,
  }) {
    return [];
  }

  @override
  List<Fixture> progressStage({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<Fixture> currentFixtures,
    required DateTime lastMatchDate,
  }) {
    if (currentFixtures.isEmpty) return [];

    int maxRound = 0;
    for (final f in currentFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final latestRoundFixtures = currentFixtures.where((f) => f.roundNumber == maxRound).toList();

    // All fixtures in latest round (both legs) must be completed
    if (!latestRoundFixtures.every((f) => f.isCompleted)) {
      return [];
    }

    // A tie has 2 fixtures. If there are 2 fixtures in this round, it's the Final!
    if (latestRoundFixtures.length <= 2) {
      return [];
    }

    // Resolve tie winners
    final winners = _resolveRoundTieWinners(latestRoundFixtures, rules.matchRules);
    if (winners.length < 2) return [];

    final int nextRound = maxRound + 1;
    final leg1DateStr = lastMatchDate.add(const Duration(days: 7)).toIso8601String().split('T').first;
    final leg2DateStr = lastMatchDate.add(const Duration(days: 14)).toIso8601String().split('T').first;

    final List<Fixture> nextFixtures = [];
    int matchIndex = 1;

    for (int i = 0; i < winners.length; i += 2) {
      if (i + 1 < winners.length) {
        final team1 = winners[i];
        final team2 = winners[i + 1];

        nextFixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r${nextRound}_m${matchIndex}_leg1',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: nextRound,
          legNumber: 1,
          matchDate: leg1DateStr,
          homeTeamId: team1,
          awayTeamId: team2,
        ));

        nextFixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r${nextRound}_m${matchIndex}_leg2',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: nextRound,
          legNumber: 2,
          matchDate: leg2DateStr,
          homeTeamId: team2,
          awayTeamId: team1,
        ));

        matchIndex++;
      }
    }

    return nextFixtures;
  }

  @override
  bool isStageComplete(CompetitionStage stage, List<Fixture> allStageFixtures) {
    if (allStageFixtures.isEmpty) return false;

    int maxRound = 0;
    for (final f in allStageFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final latestRoundFixtures = allStageFixtures.where((f) => f.roundNumber == maxRound).toList();
    // Final tie must have 2 fixtures and both completed
    return latestRoundFixtures.length == 2 && latestRoundFixtures.every((f) => f.isCompleted);
  }

  @override
  String? getStageWinner(
    CompetitionStage stage,
    CompetitionRules rules,
    List<Fixture> allStageFixtures,
    List<Standing> standings,
  ) {
    if (!isStageComplete(stage, allStageFixtures)) return null;

    int maxRound = 0;
    for (final f in allStageFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final finalTieFixtures = allStageFixtures.where((f) => f.roundNumber == maxRound).toList();
    final winners = _resolveRoundTieWinners(finalTieFixtures, rules.matchRules);
    return winners.isNotEmpty ? winners.first : null;
  }

  List<String> _resolveRoundTieWinners(List<Fixture> fixtures, MatchRules rules) {
    final List<String> winners = [];
    final leg1Map = <String, Fixture>{};
    final leg2Map = <String, Fixture>{};

    for (final f in fixtures) {
      if (f.legNumber == 1) {
        // key by sorted team pair
        final key = _tieKey(f.homeTeamId, f.awayTeamId);
        leg1Map[key] = f;
      } else if (f.legNumber == 2) {
        final key = _tieKey(f.homeTeamId, f.awayTeamId);
        leg2Map[key] = f;
      }
    }

    for (final key in leg1Map.keys) {
      final leg1 = leg1Map[key]!;
      final leg2 = leg2Map[key];
      if (leg2 != null && leg1.isCompleted && leg2.isCompleted) {
        final winner = resolveTieWinner(leg1, leg2, rules);
        winners.add(winner);
      }
    }

    return winners;
  }

  static String resolveTieWinner(Fixture leg1, Fixture leg2, MatchRules rules) {
    // leg1: Team A is home, Team B is away
    // leg2: Team B is home, Team A is away
    final teamA = leg1.homeTeamId;
    final teamB = leg1.awayTeamId;

    final leg1Home = leg1.homeScore ?? 0;
    final leg1Away = leg1.awayScore ?? 0;
    final leg2Home = leg2.homeScore ?? 0;
    final leg2Away = leg2.awayScore ?? 0;
    final leg2HomeEt = leg2.homeExtraScore ?? 0;
    final leg2AwayEt = leg2.awayExtraScore ?? 0;

    final int teamAGoals = leg1Home + leg2Away + leg2AwayEt;
    final int teamBGoals = leg1Away + leg2Home + leg2HomeEt;

    if (teamAGoals > teamBGoals) return teamA;
    if (teamBGoals > teamAGoals) return teamB;

    // Aggregate is tied. Check away goals if enabled
    if (rules.awayGoals) {
      final int teamAAway = leg2Away;
      final int teamBAway = leg1Away;
      if (teamAAway > teamBAway) return teamA;
      if (teamBAway > teamAAway) return teamB;
    }

    // Check penalty shootout recorded on leg 2
    if (leg2.homePkScore != null && leg2.awayPkScore != null) {
      // In leg2, home is Team B, away is Team A
      if (leg2.homePkScore! > leg2.awayPkScore!) return teamB;
      if (leg2.awayPkScore! > leg2.homePkScore!) return teamA;
    }

    // Default fallback to teamA if no shootout
    return teamA;
  }

  static String _tieKey(String team1, String team2) {
    final list = [team1, team2]..sort();
    return '${list[0]}__${list[1]}';
  }
}
