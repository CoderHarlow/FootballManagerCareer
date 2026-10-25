# Super Kickoff — Database Schema & Data Architecture Report

**Date of Analysis:** 2026-10-25  
**Target Package:** `app.superkickoff`  
**Primary Database:** `assets/flutter_assets/assets/superkickoff.db` (11.7 MB SQLite 3)  
**Historical Databases:** 9 seasonal databases (`1998.db` to `2026.db`, `2026_w_.db`)

---

## 1. Database Architecture & Bundle Strategy

Super Kickoff ships with 10 standalone, pre-populated SQLite 3 databases bundled in the APK. When a user begins a new career in a chosen era or mode, the corresponding `.db` file is loaded or copied to the app's local documents directory via `sqflite`.

### Database Volume Comparison

| Database File | File Size | Players (`jug_jugadores`) | Clubs (`eq_equipos`) | Leagues (`tor_torneos`) | Countries (`paises`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`superkickoff.db`** | **11.73 MB** | **62,928** | **2,136** | **245** | **254** |
| `2026.db` | 10.48 MB | 56,207 | 2,023 | 228 | 254 |
| `2025.db` | 10.34 MB | 55,624 | 2,014 | 225 | 254 |
| `2022.db` | 7.34 MB | 39,346 | 1,399 | 162 | 254 |
| `2021.db` | 5.11 MB | 26,966 | 954 | 115 | 254 |
| `2015.db` | 7.94 MB | 42,483 | 1,420 | 228 | 254 |
| `2012.db` | 7.07 MB | 37,767 | 1,360 | 192 | 254 |
| `2008.db` | 5.25 MB | 27,669 | 1,040 | 225 | 254 |
| `1998.db` | 3.51 MB | 17,461 | 700 | 225 | 254 |
| `2026_w_.db` | 1.36 MB | 5,366 | 200 | 228 | 254 |

---

## 2. Master Table Inventory (`superkickoff.db`)

The database contains 41 tables, 1 view (`vPaises`), and 1 internal SQLite metadata table (`sqlite_sequence`):

| Table Name | Rows in APK | Category | Primary Function |
| :--- | :--- | :--- | :--- |
| `jug_jugadores` | 62,928 | Players | Player attributes, ratings, age, potential, country, position |
| `eq_equipos_jugadores` | 62,938 | Rosters | Many-to-many club-player squad registration (`equid`, `jugid`) |
| `jug_contratos` | 62,936 | Finance | Active player contracts, salary, expiration, goal/assist/MVP bonuses |
| `eq_equipos` | 2,136 | Clubs | Football club data (name, country, division, overall rating, budget) |
| `eq_estadios` | 2,136 | Stadiums | Stadium capacities (general, stand, grandstand, box) and location |
| `eq_entrenadores` | 2,136 | Managers | AI and club head coaches |
| `tor_torneos` | 245 | Competitions | Leagues, cups, continental tournaments (rules, promotion/relegation) |
| `paises` | 254 | Countries | FIFA/world nations, ISO-2 codes, confederation, national rating |
| `tor_torneos_paises` | 280 | Geography | Competition host country and qualification relationships |
| `tor_cupos_internacionales`| 162 | Qualification | Continental tournament quotas per nation (e.g. Champions League) |
| `jug_posiciones_habilidades`| 164 | Attributes | Matrix mapping which skills are critical to each pitch position |
| `tor_grupos` | 35 | Tournaments | Group stage definitions (Group A, B, etc.) |
| `jug_habilidades` | 25 | Attributes | Skill definition dictionary (Remate, Pases, Regate, etc.) |
| `Patrocinadores` | 19 | Commercial | Available sponsors and tier levels |
| `jug_posiciones` | 11 | Positions | Pitch position definitions (GK, CB, LB, RB, DM, CM, AM, ST, etc.) |
| `tor_divisiones` | 5 | Competitions | Division tiers (1st Tier, 2nd Tier, etc.) |
| `tor_arbitros_tipos` | 5 | Match Officials | Referee personality / strictness profiles |
| `jug_status` | 3 | Status | Player availability status (Active, Injured, Suspended) |
| `android_metadata` | 1 | System | Android locale setting (`en_US`) |
| `eq_equipos_cesiones` | 0 | Transfers | Active player loans between clubs |
| `tor_partidos` | 0 | Matches | Match fixture records, scores, attendances, referee |
| `tor_partidos_incidencias`| 0 | Matches | Match timeline event logs stored in JSON (`tpi_json`) |
| `tor_partidos_jugadores` | 0 | Matches | Individual player match ratings, goals, minutes, cards |
| `tor_partidos_paises` | 0 | International | National team match records |
| `tor_partidos_jugadores_paises`| 0 | International | National team player match ratings and statistics |
| `tor_temporadas` | 0 | Seasons | Active career calendar seasons |
| `tor_temporadas_torneos` | 0 | Seasons | Tournament scheduling within an active season |
| `tor_temporadas_equipos` | 0 | Seasons | Club standings and placements per season |
| `tor_temporada_paises` | 0 | International | National team standings per season |
| `tor_transferencias_jugadores`| 0 | Transfers | Transfer market history log |
| `tor_transferencias_entrenadores`| 0 | Managers | Manager sackings and hirings log |
| `tor_inabilitados` | 0 | Discipline | Disciplinary suspensions log |
| `jus_stats` | 0 | Statistics | Career season-by-season player club statistics |
| `jus_stats_paises` | 0 | Statistics | Career season-by-season player national team statistics |
| `jug_premios` | 0 | Awards | Annual awards history (Golden Boot, MVP, Ballon d'Or) |
| `jug_jugadores_habilidades`| 0 | Attributes | Dynamic in-career skill progression records |
| `historial_user` | 0 | Career | User manager career summary record (matches, trophies, record) |
| `historial_ranking_mundial`| 0 | Rankings | World club ranking history |
| `mensajes` | 0 | Inbox | In-game interactive inbox news/messages |
| `pais_entrenador` | 0 | International | National team manager appointments |
| `pais_jugador_convocatoria`| 0 | International | National team player call-up lists |
| `Patrocinios` | 0 | Commercial | Active club sponsorship contracts and objectives |
| `vPaises` | 254 (view) | Reporting | SQL view aggregating country power, club counts, and tournament counts |

*(Note: Tables with 0 rows in the pre-packaged APK are runtime state tables populated as the user progresses through their career savegame).*

---

## 3. Core Entity Schemas & Relationships

### 3.1 Countries (`paises`)
- **Rows:** 254
- **Schema:**
  - `paid` (INTEGER, PK): Country ID
  - `nombre` (TEXT): Country name in Spanish (e.g., `'Alemania'`, `'Argentina'`, `'España'`)
  - `iso2` (TEXT): 2-letter ISO code (`'DE'`, `'AR'`, `'ES'`), matching `packages/flagkit/assets/flags/{iso2}@3x.png`
  - `poder` (INTEGER): National team strength rating (e.g. 50–90)
  - `pts` (INTEGER): World ranking coefficient points
  - `confederacion` (INTEGER): Confederation ID (1: CONMEBOL, 2: CONCACAF, 3: UEFA, 4: CAF, 5: AFC, 6: OFC)

### 3.2 Clubs (`eq_equipos`)
- **Rows:** 2,136
- **Schema:**
  - `equid` (INTEGER, PK): Club ID
  - `equi_abrev` (VARCHAR): Club abbreviation (e.g. `'BAR'`, `'RMA'`)
  - `equi_nombre` (VARCHAR): Club full name (e.g. `'Real Madrid'`, `'Barcelona'`, `'Manchester United'`)
  - `equi_funda` (INTEGER): Founding year
  - `equi_valor` (INTEGER): Financial valuation
  - `equi_poder` (INTEGER): Overall club team power rating (e.g. 40–88)
  - `equi_presupuesto` (INTEGER): Transfer budget
  - `equi_pts` (INTEGER): Ranking / coefficient points
  - `equi_estaid` (INTEGER): Home stadium ID (`eq_estadios.estaid`)
  - `equi_paid` (INTEGER): Country ID (`paises.paid`)
  - `equi_entid` (INTEGER): Manager ID (`eq_entrenadores.entid`)
  - `equi_division` (INTEGER): League tier (1 = top division, 2 = second division)

### 3.3 Players (`jug_jugadores`)
- **Rows:** 62,928
- **Schema:**
  - `jugid` (INTEGER, PK): Player unique ID
  - `jug_nombre` (VARCHAR(60)): Player display name (e.g. `'Lionel Messi'`, `'Erling Haaland'`)
  - `jug_edad` (TINYINT): Age (e.g. 17–42)
  - `jug_estatura` (SMALLINT): Height in cm (e.g. 175)
  - `jug_star` (TINYINT): Superstar flag (0 = normal player [62,853], 1 = global superstar [75])
  - `jug_valor` (INTEGER): Transfer market value in currency units
  - `jug_salario` (INTEGER): Weekly or monthly wage
  - `jug_perfil` (VARCHAR(1)): Preferred foot (`'D'` = Derecho/Right, `'I'` = Izquierdo/Left)
  - `jug_experiencia` (TINYINT): Experience points
  - `jug_condicion` (TINYINT): Physical fitness / stamina percentage (defaults to 100)
  - `jug_jstdid` (TINYINT): Status ID (`jug_status.jstdid`, 1 = Fit/Available)
  - `jug_poder` (TINYINT): Current Overall Rating (e.g. 45–94)
  - `jug_potencial` (TINYINT): Maximum Potential Rating (e.g. 60–100)
  - `jug_mercado` (TINYINT): Transfer market status (1 = Listed, 0 = Not listed)
  - `jug_paid` (INTEGER): Nationality (`paises.paid`)
  - `jug_posid` (TINYINT): Primary position (`jug_posiciones.posid`)
  - `jug_titular` (TINYINT): Default starter in squad (1 = starter, 0 = bench)
  - `jug_capitan` (TINYINT): Team captain flag
  - `jug_numero` (TINYINT): Squad shirt number
  - `jug_campeonatos` (VARCHAR(250)): Formatted list of won titles
  - `jug_pts` (INTEGER): Performance points
  - `jug_habilidad_A` (INTEGER): Primary signature skill ID (`jug_habilidades.habid`)
  - `jug_habilidad_B` (INTEGER): Secondary signature skill ID (`jug_habilidades.habid`)

### 3.4 Player Contracts (`jug_contratos`)
- **Rows:** 62,936
- **Schema:**
  - `jc_id` (INTEGER, PK): Contract ID
  - `jc_jugid` (INTEGER): Player ID (`jug_jugadores.jugid`)
  - `jc_equid` (INTEGER): Club ID (`eq_equipos.equid`)
  - `jc_inicio` (TEXT): Contract start date
  - `jc_fin` (TEXT): Contract expiry date
  - `jc_status` (INTEGER): Status (Active = 1)
  - `jc_salario` (INTEGER): Base wage
  - `jc_bonoGol` (INTEGER): Financial bonus per goal scored
  - `jc_bonoAsis` (INTEGER): Financial bonus per assist
  - `jc_bonoMVP` (INTEGER): Bonus for Man of the Match awards
  - `jc_bonoCampe` (INTEGER): Bonus for winning league championship
  - `jc_bonoPJ` (INTEGER): Appearance bonus per match played

### 3.5 Skills & Abilities Model (`jug_habilidades`)
- **Rows:** 25 defined skill attributes:
  1. `Atajo` (Goalkeeping: Shot stopping)
  2. `Reflejos` (Reflexes)
  3. `Anticipacion` (Anticipation)
  4. `Juego Aereo` (Aerial ability / aerial duels)
  5. `Posicionamiento` (Tactical positioning)
  6. `Entradas` (Tackling)
  7. `Marcacion` (Man marking)
  8. `Recuperador` (Ball recovery / interception)
  9. `Remate` (Finishing / shooting)
  10. `Cabeceo` (Heading accuracy)
  11. `Fuerza` (Physical strength)
  12. `Corpulencia` (Body balance / shielding)
  13. `Velocidad` (Sprint speed)
  14. `Agilidad` (Agility / turning speed)
  15. `Creatividad` (Playmaking / vision)
  16. `Pases` (Passing precision)
  17. `Resistencia` (Stamina)
  18. `Tiros Libres` (Free-kick taking)
  19. `Regate` (Dribbling)
  20. `Tecnica` (Ball control technique)
  21. `Liderazgo` (Leadership / mental fortitude)
  22. `Agresividad` (Aggression / pressing intensity)
  23. `Inteligencia` (Tactical decision making)
  24. `Control` (First touch control)
  25. `Movilidad` (Off-the-ball movement)

### 3.6 Pitch Positions (`jug_posiciones`)
- **Rows:** 11 tactical positions across 4 positional categories (`pos_tipo`):
  - Type 1 (Goalkeeper): `POR` (Portero)
  - Type 2 (Defenders): `DC` (Defensa Central), `DC` (Líbero), `DL` (Defensa Lateral / Fullback)
  - Type 3 (Midfielders): `M` (Defensivo / DM), `M` (Central / CM), `M` (Ofensivo / AM), `M` (Extremo / Wide Midfielder)
  - Type 4 (Forwards): `D` (Extremo / Winger), `D` (Media Punta / Second Striker), `D` (Centro Delantero / Striker)

### 3.7 Competitions & League Formats (`tor_torneos`)
- **Rows:** 245
- **Schema:**
  - `torid` (INTEGER, PK): Tournament ID
  - `tor_nombre` (VARCHAR): Tournament name (e.g. `'Liga Mx'`, `'UFIC LSA'`, `'Premier'`)
  - `tor_idiv` (TINYINT): Division level (1 = Top division, 2 = 2nd division, 0 = Cup/Continental)
  - `tor_organizacion` (TINYINT): Format type (1 = League, 2 = Group + Knockout, 3 = Pure Knockout)
  - `tor_vueltas` (TINYINT): Round-robin legs (1 = single round, 2 = home & away double round-robin)
  - `tor_inverso` (TINYINT): Reverse schedule flag
  - `tor_fecha_1` / `tor_fecha_2`: Calendar kickoff dates
  - `tor_dias`: Match calendar days of the week (e.g. `'6,7'` = Saturday/Sunday, `'4'` = Thursday)
  - `tor_cupos`: Number of participating clubs (e.g. `'16'`, `'18'`, `'20'`, `'32'`)
  - `tor_pts`: Points weighting coefficient
  - `tor_asciende`: Number of promotion spots
  - `tor_desciende`: Number of relegation spots
  - `tor_premio_equipos`: Team prize money
  - `tor_premio_goleador`: Golden boot prize money
  - `tor_premio_mvps`: MVP prize money

### 3.8 Match Engine Event Logging (`tor_partidos_incidencias`)
- **Schema:**
  - `incid` (INTEGER, PK): Incident unique ID
  - `tpi_partid` (INTEGER): Match ID (`tor_partidos.partid`)
  - `tpi_json` (TEXT): **JSON-encoded event timeline**. Rather than storing every pass or foul in individual SQL rows, the match simulation serializes key match events (goals, yellow cards, red cards, injuries, substitutions, penalty shootout logs) as structured JSON in a single row per match.

### 3.9 Commercial Sponsorship System (`Patrocinadores` & `Patrocinios`)
- `Patrocinadores` (19 rows): Level/tier classification of sponsors (`Pa_ID`, `Pa_nombre`, `Pa_nivel`).
- `Patrocinios` (0 rows, runtime): In-career club sponsor contracts with financial conditions:
  - `P_recompensaBase`: Base weekly/monthly payment.
  - `P_objetivo`: Specific tactical/league target (e.g. Finish in top 4, win cup).
  - `P_exito`: Target fulfillment state.
  - `P_isPrioridad`, `P_isPremioUnico`, `P_status`.
