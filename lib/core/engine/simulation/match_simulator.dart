import 'dart:math';
import '../models/competition.dart';

class MatchSimulator {
  final Random _random;

  MatchSimulator({Random? random}) : _random = random ?? Random();

  /// Simulates a fixture obeying the competition's match rules.
  void simulateMatch(
    Fixture fixture, {
    int homeReputation = 50,
    int awayReputation = 50,
    MatchRules rules = const MatchRules(),
  }) {
    // Basic reputation difference [-50, +50] + home advantage
    const homeAdvantage = 5;
    final int ratingDiff = (homeReputation + homeAdvantage) - awayReputation;

    // Expected goals base: around 1.3 - 1.5 per team
    final double homeExpected = (1.4 + (ratingDiff * 0.02)).clamp(0.2, 4.0);
    final double awayExpected = (1.2 - (ratingDiff * 0.02)).clamp(0.2, 4.0);

    fixture.homeScore = _simulateGoals(homeExpected);
    fixture.awayScore = _simulateGoals(awayExpected);

    // Check Extra Time if tied and allowed
    if (fixture.homeScore == fixture.awayScore && rules.extraTime) {
      final double homeEtExpected = homeExpected * 0.33;
      final double awayEtExpected = awayExpected * 0.33;
      fixture.homeExtraScore = _simulateGoals(homeEtExpected);
      fixture.awayExtraScore = _simulateGoals(awayEtExpected);
    } else {
      fixture.homeExtraScore = 0;
      fixture.awayExtraScore = 0;
    }

    // Check Penalties if tied and allowed
    final int regularAndEtHome = fixture.homeScore! + (fixture.homeExtraScore ?? 0);
    final int regularAndEtAway = fixture.awayScore! + (fixture.awayExtraScore ?? 0);

    if (regularAndEtHome == regularAndEtAway && rules.penalties) {
      _simulatePenalties(fixture);
    } else {
      fixture.homePkScore = null;
      fixture.awayPkScore = null;
    }

    fixture.status = FixtureStatus.played;
  }

  /// Simulates Leg 2 of a two-legged tie, taking the Leg 1 result into account
  /// to decide whether extra time and/or penalty shootouts are required on aggregate.
  void simulateSecondLeg(
    Fixture leg2,
    Fixture leg1, {
    int homeReputation = 50,
    int awayReputation = 50,
    MatchRules rules = const MatchRules(),
  }) {
    // leg1: Team A (home) vs Team B (away)
    // leg2: Team B (home) vs Team A (away)
    const homeAdvantage = 5;
    final int ratingDiff = (homeReputation + homeAdvantage) - awayReputation;

    final double homeExpected = (1.4 + (ratingDiff * 0.02)).clamp(0.2, 4.0);
    final double awayExpected = (1.2 - (ratingDiff * 0.02)).clamp(0.2, 4.0);

    leg2.homeScore = _simulateGoals(homeExpected);
    leg2.awayScore = _simulateGoals(awayExpected);

    // Aggregate score calculation
    // Team A is leg1 home, leg2 away
    // Team B is leg1 away, leg2 home
    final int teamAGoals = (leg1.homeScore ?? 0) + leg2.awayScore!;
    final int teamBGoals = (leg1.awayScore ?? 0) + leg2.homeScore!;

    leg2.homeExtraScore = 0;
    leg2.awayExtraScore = 0;
    leg2.homePkScore = null;
    leg2.awayPkScore = null;

    if (teamAGoals == teamBGoals) {
      // Check away goals rule
      bool tiedOnAwayGoals = true;
      if (rules.awayGoals) {
        final int teamAAway = leg2.awayScore!;
        final int teamBAway = leg1.awayScore ?? 0;
        if (teamAAway != teamBAway) {
          // Tie broken on away goals!
          tiedOnAwayGoals = false;
        }
      }

      if (tiedOnAwayGoals) {
        // Needs Extra Time if enabled
        if (rules.extraTime) {
          final double homeEtExpected = homeExpected * 0.33;
          final double awayEtExpected = awayExpected * 0.33;
          leg2.homeExtraScore = _simulateGoals(homeEtExpected);
          leg2.awayExtraScore = _simulateGoals(awayEtExpected);

          final int teamAWithEt = teamAGoals + leg2.awayExtraScore!;
          final int teamBWithEt = teamBGoals + leg2.homeExtraScore!;

          if (teamAWithEt == teamBWithEt && rules.penalties) {
            _simulatePenalties(leg2);
          }
        } else if (rules.penalties) {
          _simulatePenalties(leg2);
        }
      }
    }

    leg2.status = FixtureStatus.played;
  }

  int _simulateGoals(double expected) {
    // Poisson approximation via random draws
    int goals = 0;
    double p = 1.0;
    final double l = exp(-expected);
    do {
      goals++;
      p *= _random.nextDouble();
    } while (p > l);
    return goals - 1;
  }

  void _simulatePenalties(Fixture fixture) {
    // Standard best of 5 shootout + sudden death until winner is decided
    int homePenalties = 0;
    int awayPenalties = 0;

    for (int i = 0; i < 5; i++) {
      if (_random.nextDouble() < 0.75) homePenalties++;
      if (_random.nextDouble() < 0.75) awayPenalties++;
    }

    // Sudden death if equal
    while (homePenalties == awayPenalties) {
      final bool h = _random.nextDouble() < 0.70;
      final bool a = _random.nextDouble() < 0.70;
      if (h) homePenalties++;
      if (a) awayPenalties++;
    }

    fixture.homePkScore = homePenalties;
    fixture.awayPkScore = awayPenalties;
  }
}
