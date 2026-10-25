import '../models/competition.dart';
import '../simulation/tiebreaker.dart';
import 'format_handler.dart';

class GroupStageToKnockoutFormatHandler implements FormatHandler {
  // Map of teamId -> groupIndex for participant grouping
  final Map<String, int> _teamGroupIndices = {};

  @override
  FormatType get formatType => FormatType.groupStageToKnockout;

  void setTeamGroupIndices(Map<String, int> mapping) {
    _teamGroupIndices.addAll(mapping);
  }

  @override
  List<Fixture> generateInitialFixtures({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required List<String> teamIds,
    required DateTime seasonStartDate,
  }) {
    if (teamIds.length < 4) return [];

    // Group teams by their group index
    final Map<int, List<String>> groups = {};
    for (int i = 0; i < teamIds.length; i++) {
      final team = teamIds[i];
      final groupIdx = _teamGroupIndices[team] ?? (i % 2); // Default to 2 groups if unspecified
      groups.putIfAbsent(groupIdx, () => []).add(team);
    }

    final List<Fixture> allFixtures = [];
    int globalFixtureIndex = 1;

    // Generate round robin fixtures for each group
    for (final entry in groups.entries) {
      final groupIdx = entry.key;
      final groupTeams = entry.value;

      final groupFixtures = _generateGroupFixtures(
        seasonCompetitionId: seasonCompetitionId,
        stage: stage,
        rules: rules,
        groupIdx: groupIdx,
        groupTeams: groupTeams,
        seasonStartDate: seasonStartDate,
        startIndex: globalFixtureIndex,
      );

      allFixtures.addAll(groupFixtures);
      globalFixtureIndex += groupFixtures.length;
    }

    return allFixtures;
  }

  List<Fixture> _generateGroupFixtures({
    required String seasonCompetitionId,
    required CompetitionStage stage,
    required CompetitionRules rules,
    required int groupIdx,
    required List<String> groupTeams,
    required DateTime seasonStartDate,
    required int startIndex,
  }) {
    final List<String> teams = List.from(groupTeams);
    if (teams.length.isOdd) {
      teams.add('__BYE__');
    }

    final int n = teams.length;
    final int roundsPerLeg = n - 1;
    final int matchesPerRound = n ~/ 2;
    final int legs = rules.roundsOrLegs;

    final List<Fixture> fixtures = [];
    int fixtureIndex = startIndex;
    DateTime matchDate = seasonStartDate;

    for (int leg = 0; leg < legs; leg++) {
      final List<String> pool = List.from(teams);

      for (int round = 0; round < roundsPerLeg; round++) {
        final int roundNumber = (leg * roundsPerLeg) + round + 1;

        for (int m = 0; m < matchesPerRound; m++) {
          final String team1 = pool[m];
          final String team2 = pool[n - 1 - m];

          if (team1 == '__BYE__' || team2 == '__BYE__') {
            continue;
          }

          final bool homeTeam1 = (round + m) % 2 == 0;
          final String home = (leg % 2 == 0)
              ? (homeTeam1 ? team1 : team2)
              : (homeTeam1 ? team2 : team1);
          final String away = (leg % 2 == 0)
              ? (homeTeam1 ? team2 : team1)
              : (homeTeam1 ? team1 : team2);

          fixtures.add(Fixture(
            id: '${seasonCompetitionId}_${stage.id}_g${groupIdx}_f${fixtureIndex++}',
            seasonCompetitionId: seasonCompetitionId,
            stageId: stage.id,
            roundNumber: roundNumber,
            matchDate: matchDate.toIso8601String().split('T').first,
            homeTeamId: home,
            awayTeamId: away,
          ));
        }

        final last = pool.removeLast();
        pool.insert(1, last);
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
    // Determine maximum group round number
    final int maxGroupRound = _getMaxGroupRound(rules, teamIds);

    // Filter group-phase fixtures only
    final groupFixtures = stageFixtures.where((f) => f.roundNumber <= maxGroupRound).toList();

    // Group teams
    final Map<int, List<String>> groups = {};
    for (int i = 0; i < teamIds.length; i++) {
      final team = teamIds[i];
      final groupIdx = _teamGroupIndices[team] ?? (i % 2);
      groups.putIfAbsent(groupIdx, () => []).add(team);
    }

    final List<Standing> allStandings = [];

    for (final entry in groups.entries) {
      final groupIdx = entry.key;
      final groupTeams = entry.value;

      final Map<String, Standing> table = {
        for (final t in groupTeams)
          t: Standing(
            seasonCompetitionId: seasonCompetitionId,
            stageId: stageId,
            groupIndex: groupIdx,
            teamId: t,
          )
      };

      for (final f in groupFixtures) {
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

      final sortedGroupStandings = TiebreakerEngine.sortStandings(
        table.values.toList(),
        rules.tiebreakers,
        headToHeadFixtures: groupFixtures,
      );

      allStandings.addAll(sortedGroupStandings);
    }

    return allStandings;
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

    final teamIds = _teamGroupIndices.keys.toList();
    final int maxGroupRound = _getMaxGroupRound(rules, teamIds);

    // Check if group stage is completed
    final groupFixtures = currentFixtures.where((f) => f.roundNumber <= maxGroupRound).toList();
    if (!groupFixtures.every((f) => f.isCompleted)) {
      return []; // Group stage still in progress
    }

    final knockoutFixtures = currentFixtures.where((f) => f.roundNumber > maxGroupRound).toList();

    // 1. If knockout fixtures have NOT yet been scheduled, create initial knockout round
    if (knockoutFixtures.isEmpty) {
      final standings = calculateStandings(
        seasonCompetitionId: seasonCompetitionId,
        stageId: stage.id,
        teamIds: teamIds,
        stageFixtures: currentFixtures,
        rules: rules,
      );

      final qualifiedTeams = _selectAndPairQualifiedTeams(standings, rules);
      if (qualifiedTeams.length < 2) return [];

      final int firstKoRound = maxGroupRound + 1;
      final matchDateStr = lastMatchDate.add(const Duration(days: 7)).toIso8601String().split('T').first;
      final List<Fixture> nextFixtures = [];
      int matchIndex = 1;

      for (int i = 0; i < qualifiedTeams.length; i += 2) {
        if (i + 1 < qualifiedTeams.length) {
          nextFixtures.add(Fixture(
            id: '${seasonCompetitionId}_${stage.id}_ko_r${firstKoRound}_m${matchIndex++}',
            seasonCompetitionId: seasonCompetitionId,
            stageId: stage.id,
            roundNumber: firstKoRound,
            matchDate: matchDateStr,
            homeTeamId: qualifiedTeams[i],
            awayTeamId: qualifiedTeams[i + 1],
          ));
        }
      }

      return nextFixtures;
    }

    // 2. Knockout bracket already exists. Progress to next knockout round if current round is complete
    int maxKoRound = maxGroupRound;
    for (final f in knockoutFixtures) {
      if (f.roundNumber > maxKoRound) maxKoRound = f.roundNumber;
    }

    final latestKoFixtures = knockoutFixtures.where((f) => f.roundNumber == maxKoRound).toList();
    if (!latestKoFixtures.every((f) => f.isCompleted)) {
      return [];
    }

    // If latest round had only 1 match, the tournament is finished!
    if (latestKoFixtures.length == 1) {
      return [];
    }

    // Advance winners to the next round
    final List<String> winners = [];
    for (final f in latestKoFixtures) {
      final winner = f.winnerTeamId;
      if (winner != null) {
        winners.add(winner);
      }
    }

    if (winners.length < 2) return [];

    final int nextKoRound = maxKoRound + 1;
    final nextDateStr = lastMatchDate.add(const Duration(days: 7)).toIso8601String().split('T').first;
    final List<Fixture> nextFixtures = [];
    int matchIndex = 1;

    for (int i = 0; i < winners.length; i += 2) {
      if (i + 1 < winners.length) {
        nextFixtures.add(Fixture(
          id: '${seasonCompetitionId}_${stage.id}_ko_r${nextKoRound}_m${matchIndex++}',
          seasonCompetitionId: seasonCompetitionId,
          stageId: stage.id,
          roundNumber: nextKoRound,
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

    int maxRound = 0;
    for (final f in allStageFixtures) {
      if (f.roundNumber > maxRound) maxRound = f.roundNumber;
    }

    final latestFixtures = allStageFixtures.where((f) => f.roundNumber == maxRound).toList();
    // Must reach a final round of 1 match and that match must be completed
    return latestFixtures.length == 1 && latestFixtures.first.isCompleted;
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

  int _getMaxGroupRound(CompetitionRules rules, List<String> teamIds) {
    final Map<int, List<String>> groups = {};
    for (int i = 0; i < teamIds.length; i++) {
      final team = teamIds[i];
      final groupIdx = _teamGroupIndices[team] ?? (i % 2);
      groups.putIfAbsent(groupIdx, () => []).add(team);
    }

    int maxTeamsInGroup = 0;
    for (final g in groups.values) {
      if (g.length > maxTeamsInGroup) maxTeamsInGroup = g.length;
    }
    if (maxTeamsInGroup.isOdd) maxTeamsInGroup++;

    final roundsPerLeg = (maxTeamsInGroup > 1) ? maxTeamsInGroup - 1 : 1;
    return roundsPerLeg * rules.roundsOrLegs;
  }

  List<String> _selectAndPairQualifiedTeams(List<Standing> standings, CompetitionRules rules) {
    final int qualifyCount = rules.qualifyPerGroup;

    // Separate standings by group
    final Map<int, List<Standing>> groupStandings = {};
    for (final s in standings) {
      groupStandings.putIfAbsent(s.groupIndex, () => []).add(s);
    }

    final sortedGroupIndices = groupStandings.keys.toList()..sort();
    final numGroups = sortedGroupIndices.length;

    // Select top K from each group
    final Map<int, List<String>> qualifiedPerGroup = {};
    for (final g in sortedGroupIndices) {
      final list = groupStandings[g]!;
      list.sort((a, b) => a.rank.compareTo(b.rank));
      qualifiedPerGroup[g] = list.take(qualifyCount).map((s) => s.teamId).toList();
    }

    // Cross-pair qualified teams (e.g. 1st of Group A vs 2nd of Group B)
    final List<String> paired = [];

    if (numGroups == 2 && qualifyCount == 2) {
      // 2 groups with top 2: 4 teams (Semi-Finals)
      final g0 = qualifiedPerGroup[sortedGroupIndices[0]] ?? [];
      final g1 = qualifiedPerGroup[sortedGroupIndices[1]] ?? [];
      if (g0.length >= 2 && g1.length >= 2) {
        // Match 1: 1A vs 2B
        paired.add(g0[0]);
        paired.add(g1[1]);
        // Match 2: 1B vs 2A
        paired.add(g1[0]);
        paired.add(g0[1]);
      }
    } else if (numGroups == 4 && qualifyCount == 2) {
      // 4 groups with top 2: 8 teams (Quarter-Finals)
      final g0 = qualifiedPerGroup[sortedGroupIndices[0]] ?? [];
      final g1 = qualifiedPerGroup[sortedGroupIndices[1]] ?? [];
      final g2 = qualifiedPerGroup[sortedGroupIndices[2]] ?? [];
      final g3 = qualifiedPerGroup[sortedGroupIndices[3]] ?? [];

      if (g0.length >= 2 && g1.length >= 2 && g2.length >= 2 && g3.length >= 2) {
        // 1A vs 2B
        paired.add(g0[0]); paired.add(g1[1]);
        // 1C vs 2D
        paired.add(g2[0]); paired.add(g3[1]);
        // 1B vs 2A
        paired.add(g1[0]); paired.add(g0[1]);
        // 1D vs 2C
        paired.add(g3[0]); paired.add(g2[1]);
      }
    } else {
      // Generic fallback pairing
      final List<String> allQualified = [];
      for (final g in sortedGroupIndices) {
        allQualified.addAll(qualifiedPerGroup[g] ?? []);
      }
      paired.addAll(allQualified);
    }

    return paired;
  }
}
