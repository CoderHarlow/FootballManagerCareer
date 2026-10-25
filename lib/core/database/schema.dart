// Core database schema definition for Football Manager Career.

class DatabaseSchema {
  static const int currentSchemaVersion = 1;
  static const int currentEngineVersion = 1;

  /// Schema for the template World Database (world.db).
  /// This stores editable catalog data: competitions, formats, rules, clubs, teams, players.
  static const String worldSchemaSql = '''
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS dataset_metadata (
        id TEXT PRIMARY KEY,
        schema_version INTEGER NOT NULL,
        dataset_version TEXT NOT NULL,
        min_engine_version INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        description TEXT
    );

    CREATE TABLE IF NOT EXISTS countries (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT UNIQUE NOT NULL,
        continent TEXT NOT NULL CHECK(continent IN ('EUROPE', 'SOUTH_AMERICA', 'NORTH_AMERICA', 'AFRICA', 'ASIA', 'OCEANIA', 'OTHER')),
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
        flag_icon_key TEXT
    );

    CREATE TABLE IF NOT EXISTS stadiums (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        city TEXT,
        country_code TEXT,
        capacity INTEGER NOT NULL DEFAULT 15000,
        built_year INTEGER
    );

    CREATE TABLE IF NOT EXISTS competitions (
        id TEXT PRIMARY KEY,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        short_name TEXT NOT NULL,
        scope TEXT NOT NULL CHECK(scope IN ('DOMESTIC', 'CONTINENTAL', 'INTERNATIONAL')),
        tier INTEGER NOT NULL DEFAULT 1,
        country_code TEXT,
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
        icon_key TEXT
    );

    CREATE TABLE IF NOT EXISTS competition_stages (
        id TEXT PRIMARY KEY,
        competition_id TEXT NOT NULL,
        stage_order INTEGER NOT NULL,
        format_type TEXT NOT NULL,
        FOREIGN KEY(competition_id) REFERENCES competitions(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS competition_rules (
        stage_id TEXT PRIMARY KEY,
        team_count INTEGER NOT NULL,
        rounds_or_legs INTEGER NOT NULL DEFAULT 2,
        points_win INTEGER NOT NULL DEFAULT 3,
        points_draw INTEGER NOT NULL DEFAULT 1,
        points_loss INTEGER NOT NULL DEFAULT 0,
        tiebreaker_json TEXT NOT NULL,
        promotion_count INTEGER NOT NULL DEFAULT 0,
        relegation_count INTEGER NOT NULL DEFAULT 0,
        playoff_qualifiers INTEGER NOT NULL DEFAULT 0,
        match_rules_json TEXT NOT NULL,
        roster_rules_json TEXT,
        qualification_rules_json TEXT,
        scheduling_rules_json TEXT,
        FOREIGN KEY(stage_id) REFERENCES competition_stages(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS clubs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        short_name TEXT NOT NULL,
        country_code TEXT NOT NULL,
        city TEXT,
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
        primary_color TEXT DEFAULT '#000000',
        secondary_color TEXT DEFAULT '#FFFFFF',
        stadium_id TEXT,
        stadium_name TEXT,
        stadium_capacity INTEGER DEFAULT 15000,
        FOREIGN KEY(stadium_id) REFERENCES stadiums(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS teams (
        id TEXT PRIMARY KEY,
        club_id TEXT,
        country_code TEXT,
        name TEXT NOT NULL,
        short_name TEXT NOT NULL,
        team_category TEXT NOT NULL CHECK(team_category IN ('SENIOR', 'U21', 'RESERVE', 'NATIONAL')),
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
        FOREIGN KEY(club_id) REFERENCES clubs(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS default_participants (
        stage_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        seed INTEGER,
        group_index INTEGER DEFAULT 0,
        PRIMARY KEY(stage_id, team_id),
        FOREIGN KEY(stage_id) REFERENCES competition_stages(id) ON DELETE CASCADE,
        FOREIGN KEY(team_id) REFERENCES teams(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS players (
        id TEXT PRIMARY KEY,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        birth_date TEXT NOT NULL,
        nationality_code TEXT NOT NULL,
        preferred_foot TEXT CHECK(preferred_foot IN ('L', 'R', 'BOTH')),
        primary_position TEXT NOT NULL,
        secondary_positions_json TEXT DEFAULT '[]',
        overall_rating INTEGER CHECK(overall_rating BETWEEN 1 AND 99) DEFAULT 60,
        pace INTEGER CHECK(pace BETWEEN 1 AND 99) DEFAULT 60,
        shooting INTEGER CHECK(shooting BETWEEN 1 AND 99) DEFAULT 60,
        passing INTEGER CHECK(passing BETWEEN 1 AND 99) DEFAULT 60,
        dribbling INTEGER CHECK(dribbling BETWEEN 1 AND 99) DEFAULT 60,
        defending INTEGER CHECK(defending BETWEEN 1 AND 99) DEFAULT 60,
        physical INTEGER CHECK(physical BETWEEN 1 AND 99) DEFAULT 60,
        goalkeeping INTEGER CHECK(goalkeeping BETWEEN 1 AND 99) DEFAULT 60,
        attributes_json TEXT
    );

    CREATE TABLE IF NOT EXISTS player_positions (
        player_id TEXT NOT NULL,
        position TEXT NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        proficiency INTEGER CHECK(proficiency BETWEEN 1 AND 100) DEFAULT 100,
        PRIMARY KEY(player_id, position),
        FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS squad_contracts (
        id TEXT PRIMARY KEY,
        player_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        squad_number INTEGER,
        wage_per_week INTEGER DEFAULT 500,
        contract_expiry_year INTEGER NOT NULL,
        contract_start_year INTEGER,
        FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
        FOREIGN KEY(team_id) REFERENCES teams(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS national_squad_selections (
        id TEXT PRIMARY KEY,
        player_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        squad_number INTEGER,
        callup_year INTEGER NOT NULL,
        FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
        FOREIGN KEY(team_id) REFERENCES teams(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_clubs_country ON clubs(country_code);
    CREATE INDEX IF NOT EXISTS idx_teams_club ON teams(club_id);
    CREATE INDEX IF NOT EXISTS idx_players_nationality ON players(nationality_code);
    CREATE INDEX IF NOT EXISTS idx_players_position ON players(primary_position);
    CREATE INDEX IF NOT EXISTS idx_squad_contracts_team ON squad_contracts(team_id);
    CREATE INDEX IF NOT EXISTS idx_squad_contracts_player ON squad_contracts(player_id);
    CREATE INDEX IF NOT EXISTS idx_default_participants_stage ON default_participants(stage_id);
    CREATE INDEX IF NOT EXISTS idx_competition_stages_comp ON competition_stages(competition_id);
  ''';

  /// Schema for a specific Career Save Database (save_xxx.db).
  /// This stores an isolated snapshot of competition formats, rules, teams, and
  /// dynamic fixtures, standings, and game calendar states.
  static const String saveSchemaSql = '''
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS career_saves (
        id TEXT PRIMARY KEY,
        save_name TEXT NOT NULL,
        user_team_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        current_calendar_date TEXT NOT NULL,
        dataset_version TEXT NOT NULL,
        schema_version INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS clubs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        short_name TEXT NOT NULL,
        country_code TEXT NOT NULL,
        city TEXT,
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
        primary_color TEXT DEFAULT '#000000',
        secondary_color TEXT DEFAULT '#FFFFFF',
        stadium_id TEXT,
        stadium_name TEXT,
        stadium_capacity INTEGER DEFAULT 15000
    );

    CREATE TABLE IF NOT EXISTS teams (
        id TEXT PRIMARY KEY,
        club_id TEXT,
        country_code TEXT,
        name TEXT NOT NULL,
        short_name TEXT NOT NULL,
        team_category TEXT NOT NULL CHECK(team_category IN ('SENIOR', 'U21', 'RESERVE', 'NATIONAL')),
        reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50
    );

    CREATE TABLE IF NOT EXISTS players (
        id TEXT PRIMARY KEY,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        birth_date TEXT NOT NULL,
        nationality_code TEXT NOT NULL,
        preferred_foot TEXT CHECK(preferred_foot IN ('L', 'R', 'BOTH')),
        primary_position TEXT NOT NULL,
        secondary_positions_json TEXT DEFAULT '[]',
        overall_rating INTEGER CHECK(overall_rating BETWEEN 1 AND 99) DEFAULT 60,
        pace INTEGER CHECK(pace BETWEEN 1 AND 99) DEFAULT 60,
        shooting INTEGER CHECK(shooting BETWEEN 1 AND 99) DEFAULT 60,
        passing INTEGER CHECK(passing BETWEEN 1 AND 99) DEFAULT 60,
        dribbling INTEGER CHECK(dribbling BETWEEN 1 AND 99) DEFAULT 60,
        defending INTEGER CHECK(defending BETWEEN 1 AND 99) DEFAULT 60,
        physical INTEGER CHECK(physical BETWEEN 1 AND 99) DEFAULT 60,
        goalkeeping INTEGER CHECK(goalkeeping BETWEEN 1 AND 99) DEFAULT 60,
        attributes_json TEXT
    );

    CREATE TABLE IF NOT EXISTS player_positions (
        player_id TEXT NOT NULL,
        position TEXT NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0,
        proficiency INTEGER CHECK(proficiency BETWEEN 1 AND 100) DEFAULT 100,
        PRIMARY KEY(player_id, position)
    );

    CREATE TABLE IF NOT EXISTS squad_contracts (
        id TEXT PRIMARY KEY,
        player_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        squad_number INTEGER,
        wage_per_week INTEGER DEFAULT 500,
        contract_expiry_year INTEGER NOT NULL,
        contract_start_year INTEGER
    );

    CREATE TABLE IF NOT EXISTS career_seasons (
        id TEXT PRIMARY KEY,
        save_id TEXT NOT NULL,
        season_year INTEGER NOT NULL,
        start_date TEXT,
        end_date TEXT,
        status TEXT NOT NULL CHECK(status IN ('PRE_SEASON', 'IN_PROGRESS', 'COMPLETED')),
        FOREIGN KEY(save_id) REFERENCES career_saves(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS season_competitions (
        id TEXT PRIMARY KEY,
        season_id TEXT NOT NULL,
        competition_id TEXT NOT NULL,
        current_stage_id TEXT,
        status TEXT NOT NULL CHECK(status IN ('SCHEDULED', 'ACTIVE', 'COMPLETED')),
        winner_team_id TEXT,
        FOREIGN KEY(season_id) REFERENCES career_seasons(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS season_participants (
        season_competition_id TEXT NOT NULL,
        stage_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        group_index INTEGER DEFAULT 0,
        seed INTEGER,
        PRIMARY KEY(season_competition_id, stage_id, team_id),
        FOREIGN KEY(season_competition_id) REFERENCES season_competitions(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS fixtures (
        id TEXT PRIMARY KEY,
        season_competition_id TEXT NOT NULL,
        stage_id TEXT NOT NULL,
        round_number INTEGER NOT NULL,
        leg_number INTEGER NOT NULL DEFAULT 1,
        match_date TEXT NOT NULL,
        home_team_id TEXT NOT NULL,
        away_team_id TEXT NOT NULL,
        home_score INTEGER,
        away_score INTEGER,
        home_extra_score INTEGER,
        away_extra_score INTEGER,
        home_pk_score INTEGER,
        away_pk_score INTEGER,
        status TEXT NOT NULL CHECK(status IN ('SCHEDULED', 'PLAYED', 'POSTPONED')),
        FOREIGN KEY(season_competition_id) REFERENCES season_competitions(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS standings (
        season_competition_id TEXT NOT NULL,
        stage_id TEXT NOT NULL,
        group_index INTEGER NOT NULL DEFAULT 0,
        team_id TEXT NOT NULL,
        played INTEGER NOT NULL DEFAULT 0,
        won INTEGER NOT NULL DEFAULT 0,
        drawn INTEGER NOT NULL DEFAULT 0,
        lost INTEGER NOT NULL DEFAULT 0,
        goals_for INTEGER NOT NULL DEFAULT 0,
        goals_against INTEGER NOT NULL DEFAULT 0,
        goal_difference INTEGER NOT NULL DEFAULT 0,
        points INTEGER NOT NULL DEFAULT 0,
        rank INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(season_competition_id, stage_id, group_index, team_id),
        FOREIGN KEY(season_competition_id) REFERENCES season_competitions(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_fixtures_match_date ON fixtures(match_date);
    CREATE INDEX IF NOT EXISTS idx_fixtures_season_comp ON fixtures(season_competition_id);
    CREATE INDEX IF NOT EXISTS idx_standings_comp_stage ON standings(season_competition_id, stage_id);
  ''';
}
