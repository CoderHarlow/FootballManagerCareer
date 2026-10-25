import '../models/competition.dart';
import '../simulation/tiebreaker.dart';
import 'format_handler.dart';

class RoundRobinFormatHandler implements FormatHandler {
  @override
  FormatType get formatType => FormatType.roundRobin;

  @override
  List<Fixture> generateInitialFixtures({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<String> teamIds,
    required DateTime seasonStartDate,
  }) {
    if (teamIds.length < 2) return [];

    final List<String> teams = List.from(teamIds);
    final bool hasDummy = teams.length.isOdd;
    if (hasDummy) {
      teams.add('__BYE__');
    }

    final int n = teams.length;
    final int roundsPerLeg = n - 1;
    final int matchesPerRound = n ~/ 2;
    final int legs = rules.roundsOrLegs;

    final List<Fixture> fixtures = [];
    int globalFixtureIndex = 1;
    DateTime matchDate = seasonStartDate;

    for (int leg = 0; leg < legs; leg++) {
      final List<String> pool = List.from(teams);

      for (int round = 0; round < roundsPerLeg; round++) {
        final int roundNumber = (leg * roundsPerLeg) + round + 1;

        for (int m = 0; m < matchesPerRound; m++) {
          final String team1 = pool[m];
          final String team2 = pool[n - 1 - m];

          if (team1 == '__BYE__' || team2 == '__BYE__') {
            continue; // Skip bye match
          }

          // Alternate home and away to balance schedule
          final bool homeTeam1 = (round + m) % 2 == 0;
          final String home = (leg % 2 == 0)
              ? (homeTeam1 ? team1 : team2)
              : (homeTeam1 ? team2 : team1);
          final String away = (leg % 2 == 0)
              ? (homeTeam1 ? team2 : team1)
              : (homeTeam1 ? team1 : team2);

          fixtures.add(Fixture(
            id: '${seasonCompetitionId}_${stage.id}_f${globalFixtureIndex++}',
            seasonCompetitionId: seasonCompetitionId,
            stageId: stage.id,
            roundNumber: roundNumber,
            matchDate: matchDate.toIso8601String().split('T').first,
            homeTeamId: home,
            awayTeamId: away,
          ));
        }

        // Rotate pool (keep first element fixed, cycle the rest)
        final last = pool.removeLast();
        pool.insert(1, last);

        // Advance 7 days per match week
        matchDate = matchDate.add(const Duration(days: 7));
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
    final Map<String, Standing> table = {
      for (final t in teamIds)
        t: Standing(
          seasonCompetitionId: seasonCompetitionId,
          stageId: stageId,
          teamId: t,
        )
    };

    for (final f in stageFixtures) {
      if (!f.isCompleted) continue;
      final home = table[f.homeTeamId];
      final away = table[f.awayTeamId];
      if (home == null || away == null) continue;

      final hg = f.totalHomeGoals;
      final ag = f.totalAwayGoals;

      home.played++;
      away.played++;
      home.goalsFor += hg;
      home.goalsAgainst += ag;
      home.goalDifference = home.goalsFor - home.goalsAgainst;

      away.goalsFor += ag;
      away.goalsAgainst += hg;
      away.goalDifference = away.goalsFor - away.goalsAgainst;

      if (hg > ag) {
        home.won++;
        home.points += rules.pointsWin;
        away.lost++;
        away.points += rules.pointsLoss;
      } else if (ag > hg) {
        away.won++;
        away.points += rules.pointsWin;
        home.lost++;
        home.points += rules.pointsLoss;
      } else {
        home.drawn++;
        home.points += rules.pointsDraw;
        away.drawn++;
        away.points += rules.pointsDraw;
      }
    }

    return TiebreakerEngine.sortStandings(
      table.values.toList(),
      rules.tiebreakers,
      headToHeadFixtures: stageFixtures,
    );
  }

  @override
  List<Fixture> progressStage({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<Fixture> currentFixtures,
    required DateTime lastMatchDate,
  }) {
    // In a pure round robin, all fixtures are generated upfront.
    return [];
  }

  @override
  bool isStageComplete(CompetitionStage stage, List<Fixture> allStageFixtures) {
    if (allStageFixtures.isEmpty) return false;
    return allStageFixtures.every((f) => f.isCompleted);
  }

  @override
  String? getStageWinner(
    CompetitionStage stage,
    CompetitionRules rules,
    List<Fixture> allStageFixtures,
    List<Standing> standings,
  ) {
    if (!isStageComplete(stage, allStageFixtures)) return null;
    if (standings.isEmpty) return null;
    return standings.first.teamId; // Top ranked team wins the league
  }
}
