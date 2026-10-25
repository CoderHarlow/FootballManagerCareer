import '../models/competition.dart';
import 'format_handler.dart';

class SingleEliminationFormatHandler implements FormatHandler {
  @override
  FormatType get formatType => FormatType.singleElimination;

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
    final matchDateStr = seasonStartDate.toIso8601String().split('T').first;

    // Pair teams sequentially: team 0 vs team 1, team 2 vs team 3...
    for (int i = 0; i < teamIds.length; i += 2) {
      if (i + 1 < teamIds.length) {
        fixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r1_m${matchIndex++}',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: 1,
          matchDate: matchDateStr,
          homeTeamId: teamIds[i],
          awayTeamId: teamIds[i + 1],
        ));
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
    // Single elimination knockouts don't have table standings.
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

    // Find the latest round
    int maxRound = 0;
    for (final f in currentFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final latestRoundFixtures = currentFixtures.where((f) => f.roundNumber == maxRound).toList();

    // If any fixture in latest round is not completed, we cannot progress
    if (!latestRoundFixtures.every((f) => f.isCompleted)) {
      return [];
    }

    // If latest round only had 1 match, tournament final is finished!
    if (latestRoundFixtures.length == 1) {
      return [];
    }

    // Collect winners
    final List<String> winners = [];
    for (final f in latestRoundFixtures) {
      final winner = f.winnerTeamId;
      if (winner != null) {
        winners.add(winner);
      }
    }

    if (winners.length < 2) {
      return [];
    }

    // Generate next round
    final int nextRound = maxRound + 1;
    final nextDateStr = lastMatchDate.add(const Duration(days: 7)).toIso8601String().split('T').first;
    final List<Fixture> nextFixtures = [];
    int matchIndex = 1;

    for (int i = 0; i < winners.length; i += 2) {
      if (i + 1 < winners.length) {
        nextFixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_r${nextRound}_m${matchIndex++}',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: nextRound,
          matchDate: nextDateStr,
          homeTeamId: winners[i],
          awayTeamId: winners[i + 1],
        ));
      }
    }

    return nextFixtures;
  }

  @override
  bool isStageComplete(CompetitionStage stage, List<Fixture> allStageFixtures) {
    if (allStageFixtures.isEmpty) return false;

    // Must have a round with exactly 1 match (the final) and that match must be completed
    int maxRound = 0;
    for (final f in allStageFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final latestRoundFixtures = allStageFixtures.where((f) => f.roundNumber == maxRound).toList();
    return latestRoundFixtures.length == 1 && latestRoundFixtures.first.isCompleted;
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

    final finalMatch = allStageFixtures.firstWhere((f) => f.roundNumber == maxRound);
    return finalMatch.winnerTeamId;
  }
}
