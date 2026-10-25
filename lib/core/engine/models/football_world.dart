import 'dart:convert';

/// Represents a country or territory in the football world.
class Country {
  final String id;
  final String name;
  final String code; // ISO-3 or unique code (e.g. ENG, FRA, BRA)
  final String continent; // EUROPE, SOUTH_AMERICA, etc.
  final int reputation;
  final String? flagIconKey;

  const Country({
    required this.id,
    required this.name,
    required this.code,
    required this.continent,
    this.reputation = 50,
    this.flagIconKey,
  });

  factory Country.fromMap(Map<String, dynamic> map) {
    return Country(
      id: map['id'] as String,
      name: map['name'] as String,
      code: map['code'] as String,
      continent: map['continent'] as String,
      reputation: map['reputation'] as int? ?? 50,
      flagIconKey: map['flag_icon_key'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'continent': continent,
      'reputation': reputation,
      'flag_icon_key': flagIconKey,
    };
  }
}

/// Represents a football stadium.
class Stadium {
  final String id;
  final String name;
  final String? city;
  final String? countryCode;
  final int capacity;
  final int? builtYear;

  const Stadium({
    required this.id,
    required this.name,
    this.city,
    this.countryCode,
    this.capacity = 15000,
    this.builtYear,
  });

  factory Stadium.fromMap(Map<String, dynamic> map) {
    return Stadium(
      id: map['id'] as String,
      name: map['name'] as String,
      city: map['city'] as String?,
      countryCode: map['country_code'] as String?,
      capacity: map['capacity'] as int? ?? 15000,
      builtYear: map['built_year'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'city': city,
      'country_code': countryCode,
      'capacity': capacity,
      'built_year': builtYear,
    };
  }
}

/// Represents a football club.
class Club {
  final String id;
  final String name;
  final String shortName;
  final String countryCode;
  final String? city;
  final int reputation;
  final String primaryColor;
  final String secondaryColor;
  final String? stadiumId;
  final String? stadiumName;
  final int stadiumCapacity;

  const Club({
    required this.id,
    required this.name,
    required this.shortName,
    required this.countryCode,
    this.city,
    this.reputation = 50,
    this.primaryColor = '#000000',
    this.secondaryColor = '#FFFFFF',
    this.stadiumId,
    this.stadiumName,
    this.stadiumCapacity = 15000,
  });

  factory Club.fromMap(Map<String, dynamic> map) {
    return Club(
      id: map['id'] as String,
      name: map['name'] as String,
      shortName: map['short_name'] as String,
      countryCode: map['country_code'] as String,
      city: map['city'] as String?,
      reputation: map['reputation'] as int? ?? 50,
      primaryColor: map['primary_color'] as String? ?? '#000000',
      secondaryColor: map['secondary_color'] as String? ?? '#FFFFFF',
      stadiumId: map['stadium_id'] as String?,
      stadiumName: map['stadium_name'] as String?,
      stadiumCapacity: map['stadium_capacity'] as int? ?? 15000,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'short_name': shortName,
      'country_code': countryCode,
      'city': city,
      'reputation': reputation,
      'primary_color': primaryColor,
      'secondary_color': secondaryColor,
      'stadium_id': stadiumId,
      'stadium_name': stadiumName,
      'stadium_capacity': stadiumCapacity,
    };
  }
}

/// Represents a player's position proficiency.
class PlayerPosition {
  final String playerId;
  final String position;
  final bool isPrimary;
  final int proficiency;

  const PlayerPosition({
    required this.playerId,
    required this.position,
    this.isPrimary = false,
    this.proficiency = 100,
  });

  factory PlayerPosition.fromMap(Map<String, dynamic> map) {
    return PlayerPosition(
      playerId: map['player_id'] as String,
      position: map['position'] as String,
      isPrimary: (map['is_primary'] as int? ?? 0) == 1,
      proficiency: map['proficiency'] as int? ?? 100,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'player_id': playerId,
      'position': position,
      'is_primary': isPrimary ? 1 : 0,
      'proficiency': proficiency,
    };
  }
}

/// Supported standard football positions.
class FootballPositions {
  static const Set<String> all = {
    'GK',
    'CB',
    'LB',
    'RB',
    'LWB',
    'RWB',
    'CDM',
    'CM',
    'CAM',
    'LM',
    'RM',
    'LW',
    'RW',
    'CF',
    'ST',
  };

  static bool isValid(String pos) => all.contains(pos.toUpperCase());
}

/// Represents a football player.
class Player {
  final String id;
  final String firstName;
  final String lastName;
  final String birthDate;
  final String nationalityCode;
  final String preferredFoot; // L, R, BOTH
  final String primaryPosition;
  final List<String> secondaryPositions;
  final int overallRating;
  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;
  final int goalkeeping;
  final Map<String, dynamic> customAttributes;

  const Player({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.nationalityCode,
    this.preferredFoot = 'R',
    required this.primaryPosition,
    this.secondaryPositions = const [],
    this.overallRating = 60,
    this.pace = 60,
    this.shooting = 60,
    this.passing = 60,
    this.dribbling = 60,
    this.defending = 60,
    this.physical = 60,
    this.goalkeeping = 60,
    this.customAttributes = const {},
  });

  String get fullName => '$firstName $lastName';

  factory Player.fromMap(Map<String, dynamic> map) {
    List<String> secPositions = [];
    final secRaw = map['secondary_positions_json'];
    if (secRaw is String && secRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(secRaw);
        if (decoded is List) {
          secPositions = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    Map<String, dynamic> customAttrs = {};
    final attrsRaw = map['attributes_json'];
    if (attrsRaw is String && attrsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(attrsRaw);
        if (decoded is Map<String, dynamic>) {
          customAttrs = decoded;
        }
      } catch (_) {}
    }

    return Player(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      birthDate: map['birth_date'] as String,
      nationalityCode: map['nationality_code'] as String,
      preferredFoot: map['preferred_foot'] as String? ?? 'R',
      primaryPosition: map['primary_position'] as String,
      secondaryPositions: secPositions,
      overallRating: map['overall_rating'] as int? ?? 60,
      pace: map['pace'] as int? ?? 60,
      shooting: map['shooting'] as int? ?? 60,
      passing: map['passing'] as int? ?? 60,
      dribbling: map['dribbling'] as int? ?? 60,
      defending: map['defending'] as int? ?? 60,
      physical: map['physical'] as int? ?? 60,
      goalkeeping: map['goalkeeping'] as int? ?? 60,
      customAttributes: customAttrs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'birth_date': birthDate,
      'nationality_code': nationalityCode,
      'preferred_foot': preferredFoot,
      'primary_position': primaryPosition,
      'secondary_positions_json': jsonEncode(secondaryPositions),
      'overall_rating': overallRating,
      'pace': pace,
      'shooting': shooting,
      'passing': passing,
      'dribbling': dribbling,
      'defending': defending,
      'physical': physical,
      'goalkeeping': goalkeeping,
      'attributes_json': customAttributes.isNotEmpty ? jsonEncode(customAttributes) : null,
    };
  }
}

/// Represents a player's contract / squad registration with a team.
class SquadContract {
  final String id;
  final String playerId;
  final String teamId;
  final int? squadNumber;
  final int wagePerWeek;
  final int contractExpiryYear;
  final int? contractStartYear;

  const SquadContract({
    required this.id,
    required this.playerId,
    required this.teamId,
    this.squadNumber,
    this.wagePerWeek = 500,
    required this.contractExpiryYear,
    this.contractStartYear,
  });

  factory SquadContract.fromMap(Map<String, dynamic> map) {
    return SquadContract(
      id: map['id'] as String,
      playerId: map['player_id'] as String,
      teamId: map['team_id'] as String,
      squadNumber: map['squad_number'] as int?,
      wagePerWeek: map['wage_per_week'] as int? ?? 500,
      contractExpiryYear: map['contract_expiry_year'] as int,
      contractStartYear: map['contract_start_year'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'player_id': playerId,
      'team_id': teamId,
      'squad_number': squadNumber,
      'wage_per_week': wagePerWeek,
      'contract_expiry_year': contractExpiryYear,
      'contract_start_year': contractStartYear,
    };
  }
}

/// Represents a player's selection for a national squad.
class NationalSquadSelection {
  final String id;
  final String playerId;
  final String teamId; // National team ID
  final int? squadNumber;
  final int callupYear;

  const NationalSquadSelection({
    required this.id,
    required this.playerId,
    required this.teamId,
    this.squadNumber,
    required this.callupYear,
  });

  factory NationalSquadSelection.fromMap(Map<String, dynamic> map) {
    return NationalSquadSelection(
      id: map['id'] as String,
      playerId: map['player_id'] as String,
      teamId: map['team_id'] as String,
      squadNumber: map['squad_number'] as int?,
      callupYear: map['callup_year'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'player_id': playerId,
      'team_id': teamId,
      'squad_number': squadNumber,
      'callup_year': callupYear,
    };
  }
}
