import 'dart:convert';

/// Supported competition format types in the game engine.
enum FormatType {
  roundRobin,
  singleElimination,
  twoLeggedTie,
  groupStageToKnockout;

  static FormatType fromString(String str) {
    switch (str.toUpperCase()) {
      case 'ROUND_ROBIN':
        return FormatType.roundRobin;
      case 'SINGLE_ELIMINATION':
        return FormatType.singleElimination;
      case 'TWO_LEGGED_TIE':
        return FormatType.twoLeggedTie;
      case 'GROUP_STAGE_TO_KNOCKOUT':
        return FormatType.groupStageToKnockout;
      default:
        throw ArgumentError('Unknown format type: \$str');
    }
  }

  String toDbString() {
    switch (this) {
      case FormatType.roundRobin:
        return 'ROUND_ROBIN';
      case FormatType.singleElimination:
        return 'SINGLE_ELIMINATION';
      case FormatType.twoLeggedTie:
        return 'TWO_LEGGED_TIE';
      case FormatType.groupStageToKnockout:
        return 'GROUP_STAGE_TO_KNOCKOUT';
    }
  }
}

class MatchRules {
  final bool extraTime;
  final bool penalties;
  final bool awayGoals;
  final int substitutionsMax;
  final int substitutionStoppages;

  const MatchRules({
    this.extraTime = false,
    this.penalties = false,
    this.awayGoals = false,
    this.substitutionsMax = 5,
    this.substitutionStoppages = 3,
  });

  MatchRules copyWith({
    bool? extraTime,
    bool? penalties,
    bool? awayGoals,
    int? substitutionsMax,
    int? substitutionStoppages,
  }) {
    return MatchRules(
      extraTime: extraTime ?? this.extraTime,
      penalties: penalties ?? this.penalties,
      awayGoals: awayGoals ?? this.awayGoals,
      substitutionsMax: substitutionsMax ?? this.substitutionsMax,
      substitutionStoppages: substitutionStoppages ?? this.substitutionStoppages,
    );
  }

  factory MatchRules.fromJsonString(String jsonStr) {
    try {
      final Map<String, dynamic> map = jsonDecode(jsonStr);
      return MatchRules(
        extraTime: map['extra_time'] ?? false,
        penalties: map['penalties'] ?? false,
        awayGoals: map['away_goals'] ?? false,
        substitutionsMax: map['subs_max'] ?? 5,
        substitutionStoppages: map['sub_stoppages'] ?? 3,
      );
    } catch (_) {
      return const MatchRules();
    }
  }

  String toJsonString() {
    return jsonEncode({
      'extra_time': extraTime,
      'penalties': penalties,
      'away_goals': awayGoals,
      'subs_max': substitutionsMax,
      'sub_stoppages': substitutionStoppages,
    });
  }
}

class Competition {
  final String id;
  final String code;
  final String name;
  final String shortName;
  final String scope;
  final int tier;
  final String? countryCode;
  final int reputation;
  final String? iconKey;

  Competition({
    required this.id,
    required this.code,
    required this.name,
    required this.shortName,
    required this.scope,
    this.tier = 1,
    this.countryCode,
    this.reputation = 50,
    this.iconKey,
  });

  factory Competition.fromMap(Map<String, dynamic> map) {
    return Competition(
      id: map['id'] as String,
      code: map['code'] as String,
      name: map['name'] as String,
      shortName: map['short_name'] as String,
      scope: map['scope'] as String,
      tier: map['tier'] as int? ?? 1,
      countryCode: map['country_code'] as String?,
      reputation: map['reputation'] as int? ?? 50,
      iconKey: map['icon_key'] as String?,
    );
  }
}

class CompetitionStage {
  final String id;
  final String competitionId;
  final int stageOrder;
  final FormatType formatType;

  CompetitionStage({
    required this.id,
    required this.competitionId,
    required this.stageOrder,
    required this.formatType,
  });

  factory CompetitionStage.fromMap(Map<String, dynamic> map) {
    return CompetitionStage(
      id: map['id'] as String,
      competitionId: map['competition_id'] as String,
      stageOrder: map['stage_order'] as int,
      formatType: FormatType.fromString(map['format_type'] as String),
    );
  }
}

class SchedulingRules {
  final int startOffsetDays;
  final int matchIntervalDays;
  final int? preferredWeekday; // 1 = Monday ... 7 = Sunday
  final int minRestDays;

  const SchedulingRules({
    this.startOffsetDays = 0,
    this.matchIntervalDays = 7,
    this.preferredWeekday,
    this.minRestDays = 2,
  });

  factory SchedulingRules.fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return const SchedulingRules();
    }
    try {
      final Map<String, dynamic> map = jsonDecode(jsonStr);
      return SchedulingRules(
        startOffsetDays: map['start_offset_days'] as int? ?? 0,
        matchIntervalDays: map['match_interval_days'] as int? ?? 7,
        preferredWeekday: map['preferred_weekday'] as int?,
        minRestDays: map['min_rest_days'] as int? ?? 2,
      );
    } catch (_) {
      return const SchedulingRules();
    }
  }

  String toJsonString() {
    return jsonEncode({
      'start_offset_days': startOffsetDays,
      'match_interval_days': matchIntervalDays,
      'preferred_weekday': preferredWeekday,
      'min_rest_days': minRestDays,
    });
  }
}

class CompetitionRules {
  final String stageId;
  final int teamCount;
  final int roundsOrLegs;
  final int pointsWin;
  final int pointsDraw;
  final int pointsLoss;
  final List<String> tiebreakers;
  final int promotionCount;
  final int relegationCount;
  final int playoffQualifiers;
  final MatchRules matchRules;
  final String? rosterRulesJson;
  final String? qualificationRulesJson;
  final SchedulingRules schedulingRules;
  final String? schedulingRulesJson;

  CompetitionRules({
    required this.stageId,
    required this.teamCount,
    this.roundsOrLegs = 2,
    this.pointsWin = 3,
    this.pointsDraw = 1,
    this.pointsLoss = 0,
    required this.tiebreakers,
    this.promotionCount = 0,
    this.relegationCount = 0,
    this.playoffQualifiers = 0,
    required this.matchRules,
    this.rosterRulesJson,
    this.qualificationRulesJson,
    this.schedulingRules = const SchedulingRules(),
    this.schedulingRulesJson,
  });

  int get qualifyPerGroup {
    if (qualificationRulesJson != null) {
      try {
        final Map<String, dynamic> map = jsonDecode(qualificationRulesJson!);
        if (map.containsKey('qualify_per_group')) {
          return map['qualify_per_group'] as int;
        }
        if (map.containsKey('qualify_top')) {
          return map['qualify_top'] as int;
        }
      } catch (_) {}
    }
    return playoffQualifiers > 0 ? playoffQualifiers : 2;
  }

  factory CompetitionRules.fromMap(Map<String, dynamic> map) {
    List<String> tiebreakerList = [];
    final tiebreakerRaw = map['tiebreaker_json'];
    if (tiebreakerRaw != null && tiebreakerRaw is String) {
      try {
        final decoded = jsonDecode(tiebreakerRaw);
        if (decoded is List) {
          tiebreakerList = decoded.map((e) => e.toString().toUpperCase()).toList();
        }
      } catch (_) {}
    }
    if (tiebreakerList.isEmpty) {
      tiebreakerList = ['POINTS', 'GOAL_DIFFERENCE', 'GOALS_FOR', 'HEAD_TO_HEAD'];
    }

    final matchRulesRaw = map['match_rules_json'] as String? ?? '{}';
    final schedRaw = map['scheduling_rules_json'] as String?;
    return CompetitionRules(
      stageId: map['stage_id'] as String,
      teamCount: map['team_count'] as int,
      roundsOrLegs: map['rounds_or_legs'] as int? ?? 2,
      pointsWin: map['points_win'] as int? ?? 3,
      pointsDraw: map['points_draw'] as int? ?? 1,
      pointsLoss: map['points_loss'] as int? ?? 0,
      tiebreakers: tiebreakerList,
      promotionCount: map['promotion_count'] as int? ?? 0,
      relegationCount: map['relegation_count'] as int? ?? 0,
      playoffQualifiers: map['playoff_qualifiers'] as int? ?? 0,
      matchRules: MatchRules.fromJsonString(matchRulesRaw),
      rosterRulesJson: map['roster_rules_json'] as String?,
      qualificationRulesJson: map['qualification_rules_json'] as String?,
      schedulingRules: SchedulingRules.fromJsonString(schedRaw),
      schedulingRulesJson: schedRaw,
    );
  }
}

class Team {
  final String id;
  final String clubId;
  final String name;
  final String shortName;
  final String teamCategory;
  final int reputation;

  Team({
    required this.id,
    required this.clubId,
    required this.name,
    required this.shortName,
    this.teamCategory = 'SENIOR',
    this.reputation = 50,
  });

  factory Team.fromMap(Map<String, dynamic> map) {
    return Team(
      id: map['id'] as String,
      clubId: map['club_id'] as String,
      name: map['name'] as String,
      shortName: map['short_name'] as String,
      teamCategory: map['team_category'] as String? ?? 'SENIOR',
      reputation: map['reputation'] as int? ?? 50,
    );
  }
}

enum FixtureStatus {
  scheduled,
  played,
  postponed;

  static FixtureStatus fromString(String str) {
    switch (str.toUpperCase()) {
      case 'PLAYED':
        return FixtureStatus.played;
      case 'POSTPONED':
        return FixtureStatus.postponed;
      default:
        return FixtureStatus.scheduled;
    }
  }

  String toDbString() {
    switch (this) {
      case FixtureStatus.played:
        return 'PLAYED';
      case FixtureStatus.postponed:
        return 'POSTPONED';
      case FixtureStatus.scheduled:
        return 'SCHEDULED';
    }
  }
}

class Fixture {
  final String id;
  final String seasonCompetitionId;
  final String stageId;
  final int roundNumber;
  final int legNumber;
  final String matchDate;
  final String homeTeamId;
  final String awayTeamId;
  int? homeScore;
  int? awayScore;
  int? homeExtraScore;
  int? awayExtraScore;
  int? homePkScore;
  int? awayPkScore;
  FixtureStatus status;

  Fixture({
    required this.id,
    required this.seasonCompetitionId,
    required this.stageId,
    required this.roundNumber,
    this.legNumber = 1,
    required this.matchDate,
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeScore,
    this.awayScore,
    this.homeExtraScore,
    this.awayExtraScore,
    this.homePkScore,
    this.awayPkScore,
    this.status = FixtureStatus.scheduled,
  });

  bool get isCompleted => status == FixtureStatus.played;
  bool get isLeg2 => legNumber == 2;

  int get totalHomeGoals => (homeScore ?? 0) + (homeExtraScore ?? 0);
  int get totalAwayGoals => (awayScore ?? 0) + (awayExtraScore ?? 0);

  String? get winnerTeamId {
    if (!isCompleted) return null;
    if (totalHomeGoals > totalAwayGoals) return homeTeamId;
    if (totalAwayGoals > totalHomeGoals) return awayTeamId;
    if (homePkScore != null && awayPkScore != null) {
      if (homePkScore! > awayPkScore!) return homeTeamId;
      if (awayPkScore! > homePkScore!) return awayTeamId;
    }
    return null; // Draw
  }

  factory Fixture.fromMap(Map<String, dynamic> map) {
    return Fixture(
      id: map['id'] as String,
      seasonCompetitionId: map['season_competition_id'] as String,
      stageId: map['stage_id'] as String,
      roundNumber: map['round_number'] as int,
      legNumber: map['leg_number'] as int? ?? 1,
      matchDate: map['match_date'] as String,
      homeTeamId: map['home_team_id'] as String,
      awayTeamId: map['away_team_id'] as String,
      homeScore: map['home_score'] as int?,
      awayScore: map['away_score'] as int?,
      homeExtraScore: map['home_extra_score'] as int?,
      awayExtraScore: map['away_extra_score'] as int?,
      homePkScore: map['home_pk_score'] as int?,
      awayPkScore: map['away_pk_score'] as int?,
      status: FixtureStatus.fromString(map['status'] as String? ?? 'SCHEDULED'),
    );
  }
}

class Standing {
  final String seasonCompetitionId;
  final String stageId;
  final int groupIndex;
  final String teamId;
  int played;
  int won;
  int drawn;
  int lost;
  int goalsFor;
  int goalsAgainst;
  int goalDifference;
  int points;
  int rank;

  Standing({
    required this.seasonCompetitionId,
    required this.stageId,
    this.groupIndex = 0,
    required this.teamId,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.goalDifference = 0,
    this.points = 0,
    this.rank = 0,
  });

  factory Standing.fromMap(Map<String, dynamic> map) {
    return Standing(
      seasonCompetitionId: map['season_competition_id'] as String,
      stageId: map['stage_id'] as String,
      groupIndex: map['group_index'] as int? ?? 0,
      teamId: map['team_id'] as String,
      played: map['played'] as int? ?? 0,
      won: map['won'] as int? ?? 0,
      drawn: map['drawn'] as int? ?? 0,
      lost: map['lost'] as int? ?? 0,
      goalsFor: map['goals_for'] as int? ?? 0,
      goalsAgainst: map['goals_against'] as int? ?? 0,
      goalDifference: map['goal_difference'] as int? ?? 0,
      points: map['points'] as int? ?? 0,
      rank: map['rank'] as int? ?? 0,
    );
  }
}
