import '../models/competition.dart';

class TiebreakerEngine {
  /// Sorts a list of standings according to the configured tiebreaker order.
  static List<Standing> sortStandings(
    List<Standing> standings,
    List<String> tiebreakers, {
    List<Fixture> headToHeadFixtures = const [],
  }) {
    final list = List<Standing>.from(standings);

    list.sort((a, b) {
      for (final rule in tiebreakers) {
        final cmp = _compareByRule(a, b, rule, headToHeadFixtures);
        if (cmp != 0) return cmp;
      }
      // Stable fallback: alphabetically by teamId
      return a.teamId.compareTo(b.teamId);
    });

    // Assign rank 1-indexed
    for (int i = 0; i < list.length; i++) {
      list[i].rank = i + 1;
    }

    return list;
  }

  static int _compareByRule(
    Standing a,
    Standing b,
    String rule,
    List<Fixture> fixtures,
  ) {
    switch (rule.toUpperCase()) {
      case 'POINTS':
        return b.points.compareTo(a.points); // higher is better
      case 'GOAL_DIFFERENCE':
        return b.goalDifference.compareTo(a.goalDifference);
      case 'GOALS_FOR':
        return b.goalsFor.compareTo(a.goalsFor);
      case 'WINS':
        return b.won.compareTo(a.won);
      case 'HEAD_TO_HEAD':
        return _compareHeadToHead(a.teamId, b.teamId, fixtures);
      default:
        return 0;
    }
  }

  static int _compareHeadToHead(String teamA, String teamB, List<Fixture> fixtures) {
    int pointsA = 0;
    int pointsB = 0;
    int gdA = 0;

    for (final f in fixtures) {
      if (!f.isCompleted) continue;
      if (f.homeTeamId == teamA && f.awayTeamId == teamB) {
        final hg = f.totalHomeGoals;
        final ag = f.totalAwayGoals;
        gdA += (hg - ag);
        if (hg > ag) {
          pointsA += 3;
        } else if (ag > hg) {
          pointsB += 3;
        } else {
          pointsA += 1;
          pointsB += 1;
        }
      } else if (f.homeTeamId == teamB && f.awayTeamId == teamA) {
        final hg = f.totalHomeGoals;
        final ag = f.totalAwayGoals;
        gdA -= (hg - ag);
        if (hg > ag) {
          pointsB += 3;
        } else if (ag > hg) {
          pointsA += 3;
        } else {
          pointsA += 1;
          pointsB += 1;
        }
      }
    }

    if (pointsA != pointsB) return pointsB.compareTo(pointsA);
    if (gdA != 0) return (-gdA).compareTo(0);
    return 0;
  }
}
