# Super Kickoff — Complete Historical Era & Database Inventory

**Date of Analysis:** 2026-10-25  
**Target Package:** `app.superkickoff` (Version `4.3.4`, Build `119`)  
**Archive Source:** `reference/superkickoff/app.superkickoff.apk`  
**Internal Asset Directory:** `assets/flutter_assets/assets/`  
**Report Location:** `reference/analysis/historical_era_inventory.md`

---

## 1. Executive Summary & Verification

During static read-only inspection of the base APK (`app.superkickoff.apk`), **10 distinct SQLite 3 databases** were located, inspected, and verified.

Every database was extracted into memory, verified against SQLite 3 header specifications (`SQLite format 3\x00`), and queried directly. The inspection confirmed that Super Kickoff maintains a **multi-era career architecture**: instead of altering a single database, the game ships separate, self-contained database snapshots representing classic football eras, historical seasons, modern seasons, and a dedicated women's football dataset.

All 10 databases share **100% schema parity** (identical 44 tables, 1 view, and matching column definitions). All runtime state tables (`tor_temporadas`, `tor_partidos`, `tor_transferencias_jugadores`) are empty (0 rows), confirming they are pristine baseline seed databases for career starts.

---

## 2. Discovered Databases Verification

All 10 database files exist at the following exact internal archive paths:

| # | Database Filename | Exact Internal APK Path | File Size (Bytes) | Compressed Size | Header Verification |
| :-: | :--- | :--- | :--- | :--- | :--- |
| 1 | **`superkickoff.db`** | `assets/flutter_assets/assets/superkickoff.db` | 11,735,040 B (~11.7 MB) | 4,175,988 B | `SQLite format 3` (Valid) |
| 2 | **`1998.db`** | `assets/flutter_assets/assets/1998.db` | 3,506,176 B (~3.5 MB) | 1,224,613 B | `SQLite format 3` (Valid) |
| 3 | **`2008.db`** | `assets/flutter_assets/assets/2008.db` | 5,251,072 B (~5.3 MB) | 1,850,555 B | `SQLite format 3` (Valid) |
| 4 | **`2012.db`** | `assets/flutter_assets/assets/2012.db` | 7,069,696 B (~7.1 MB) | 2,544,454 B | `SQLite format 3` (Valid) |
| 5 | **`2015.db`** | `assets/flutter_assets/assets/2015.db` | 7,938,048 B (~7.9 MB) | 2,850,875 B | `SQLite format 3` (Valid) |
| 6 | **`2021.db`** | `assets/flutter_assets/assets/2021.db` | 5,111,808 B (~5.1 MB) | 1,864,800 B | `SQLite format 3` (Valid) |
| 7 | **`2022.db`** | `assets/flutter_assets/assets/2022.db` | 7,340,032 B (~7.3 MB) | 2,571,008 B | `SQLite format 3` (Valid) |
| 8 | **`2025.db`** | `assets/flutter_assets/assets/2025.db` | 10,342,400 B (~10.3 MB) | 3,673,937 B | `SQLite format 3` (Valid) |
| 9 | **`2026.db`** | `assets/flutter_assets/assets/2026.db` | 10,477,568 B (~10.5 MB) | 3,777,502 B | `SQLite format 3` (Valid) |
| 10 | **`2026_w_.db`** | `assets/flutter_assets/assets/2026_w_.db` | 1,355,776 B (~1.4 MB) | 423,558 B | `SQLite format 3` (Valid) |

---

## 3. Historical Era Comparison Matrix

The table below summarizes the quantitative scope and classification of each database:

| Database | Classification / Mode | Represented Season / Era | Players (`jug_jugadores`) | Clubs (`eq_equipos`) | Leagues (`tor_torneos`) | Stadiums (`eq_estadios`) | Avg Player Age | Key Headline Player |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **`superkickoff.db`** | **Master Database** | Current World Roster | **62,928** | **2,136** | **245** | **2,136** | 25.01 | L. Messi (39, Inter Miami) |
| **`1998.db`** | Historical Snapshot | 1997–1998 / World Cup 98 | **17,461** | **700** | **225** | **700** | 24.63 | Z. Zidane (26, Juventus) |
| **`2008.db`** | Historical Snapshot | 2007–2008 / Euro 2008 | **27,669** | **1,040** | **225** | **1,040** | 25.27 | F. Lampard (30, Chelsea) |
| **`2012.db`** | Historical Snapshot | 2011–2012 / Euro 2012 | **37,767** | **1,360** | **192** | **1,360** | 25.76 | L. Messi (25, Barcelona) |
| **`2015.db`** | Historical Snapshot | 2014–2015 / MSN vs BBC | **42,483** | **1,420** | **228** | **1,420** | 25.73 | C. Ronaldo (30, Real Madrid) |
| **`2021.db`** | Historical Snapshot | 2021–2022 (Fall 2021) | **26,966** | **954** | **115** | **954** | 25.61 | L. Messi (34, PSG) |
| **`2022.db`** | Historical Snapshot | 2022–2023 / World Cup 22 | **39,346** | **1,399** | **162** | **1,399** | 25.73 | K. Benzema (34, Real Madrid) |
| **`2025.db`** | Modern Snapshot | 2024–2025 Season | **55,624** | **2,014** | **225** | **2,014** | 25.28 | K. Mbappé (26, Real Madrid) |
| **`2026.db`** | Modern Snapshot | 2025–2026 Season | **56,207** | **2,023** | **228** | **2,023** | 25.28 | E. Haaland (25, Man. City) |
| **`2026_w_.db`** | Women's Football | 2026 Women's Leagues | **5,366** | **200** | **228** | **200** | 24.36 | A. Putellas (32, Barcelona) |

*(Note: Every database contains exactly **254 countries** in `paises`, **25 skill dimensions** in `jug_habilidades`, **11 positions** in `jug_posiciones`, and **19 sponsor levels** in `Patrocinadores`).*

---

## 4. In-Depth Historical Evidence & Classification

### 4.1 `1998.db` — Confirmed Era: 1997–1998 Season & 1998 World Cup
* **Database Size:** 3,506,176 B | 17,461 players | 700 clubs | 225 competitions
* **Player Age Range:** 15 – 47 years (Average: 24.63)
* **Concrete Roster Evidence:**
  * **Zinedine Zidane:** Age 26, Overall 87, Club: **Juventus** (Won 1998 FIFA World Cup and 1998 Ballon d'Or).
  * **Ronaldo ("O Fenômeno"):** Age 22, Overall 86, Club: **Inter Milan** (Transferred from Barcelona to Inter in 1997).
  * **Jürgen Klinsmann:** Age 34, Overall 85, Club: **Tottenham Hotspur** (Returned to Spurs for the 1997/98 season).
  * **Youri Djorkaeff:** Age 30, Overall 85, Club: **Inter Milan**.
  * **Raúl González:** Age 21, Overall 83, Club: **Real Madrid**.
  * **Ronaldinho:** Age 18, Overall 55, Club: **Grêmio** (Breakthrough rookie season in Porto Alegre).
  * **Alf-Inge Haaland (Father of Erling Haaland):** Age 26, Overall 67, Club: **Leeds United**.
  * **Notable Absence:** Neither Lionel Messi (born June 1987, age 11) nor Cristiano Ronaldo (born Feb 1985, age 13) exists in this database.

### 4.2 `2008.db` — Confirmed Era: 2007–2008 Season & UEFA Euro 2008
* **Database Size:** 5,251,072 B | 27,669 players | 1,040 clubs | 225 competitions
* **Player Age Range:** 14 – 56 years (Average: 25.27)
* **Concrete Roster Evidence:**
  * **Frank Lampard:** Age 30, Overall 91, Club: **Chelsea** (2008 Champions League finalist).
  * **Steven Gerrard:** Age 28, Overall 89, Club: **Liverpool**.
  * **Thierry Henry:** Age 31, Overall 88, Club: **Barcelona** (Transferred from Arsenal summer 2007).
  * **David Villa:** Age 27, Overall 88, Club: **Valencia** (Top scorer of UEFA Euro 2008).
  * **John Terry:** Age 28, Overall 88, Club: **Chelsea**.
  * **Ronaldinho:** Age 28, Overall 87, Club: **Barcelona** (Final season at Barcelona before AC Milan transfer).
  * **Cristiano Ronaldo:** Age 23, Overall 86, Club: **Manchester United** (42 goals in 2007/08, won Premier League, Champions League, and 2008 Ballon d'Or).
  * **Lionel Messi:** Age 21, Overall 74, Club: **Barcelona** (Wearing #19, pre-Guardiola breakthrough era).

### 4.3 `2012.db` — Confirmed Era: 2011–2012 Season (Peak Messi vs. Ronaldo)
* **Database Size:** 7,069,696 B | 37,767 players | 1,360 clubs | 192 competitions
* **Player Age Range:** 14 – 49 years (Average: 25.76)
* **Concrete Roster Evidence:**
  * **Lionel Messi:** Age 25, Overall **94**, Club: **Barcelona** (Calendar year of 91 goals; 73 goals in 2011/12 club season).
  * **Cristiano Ronaldo:** Age 27, Overall **93**, Club: **Real Madrid** (José Mourinho's 100-point La Liga championship).
  * **Frank Lampard:** Age 34, Overall 92, Club: **Chelsea** (Won Champions League in Munich, May 2012).
  * **Samuel Eto'o:** Age 31, Overall 92, Club: **Anzhi Makhachkala** (High-profile move to Dagestan, Russia in late 2011).
  * **Wayne Rooney:** Age 27, Overall 90, Club: **Manchester United**.
  * **Ronaldinho:** Age 32, Overall 84, Club: **Atlético Mineiro** (Return to Brazil).

### 4.4 `2015.db` — Confirmed Era: 2014–2015 Season ("MSN" Treble Era)
* **Database Size:** 7,938,048 B | 42,483 players | 1,420 clubs | 228 competitions
* **Player Age Range:** 14 – 81 years (Average: 25.73)
* **Concrete Roster Evidence:**
  * **Cristiano Ronaldo:** Age 30, Overall 90, Club: **Real Madrid** (48 league goals, Pichichi winner).
  * **Zlatan Ibrahimović:** Age 34, Overall 89, Club: **Paris Saint-Germain**.
  * **Lionel Messi:** Age 28, Overall 87, Club: **Barcelona** (Luis Enrique treble-winning season with Neymar and Suárez).
  * **Diego Godín:** Age 29, Overall 87, Club: **Atlético Madrid** (Reigning 2014 La Liga champions).
  * **Luis Suárez:** Age 28, Overall 86, Club: **Barcelona** (Transferred summer 2014 from Liverpool).

### 4.5 `2021.db` — Confirmed Era: 2021–2022 Season (Summer 2021 Transfer Blockbuster)
* **Database Size:** 5,111,808 B | 26,966 players | 954 clubs | 115 competitions
* **Player Age Range:** 15 – 51 years (Average: 25.61)
* **Concrete Roster Evidence:**
  * **Lionel Messi:** Age 34, Overall 88, Club: **Paris Saint-Germain** (Historic free transfer in August 2021).
  * **Cristiano Ronaldo:** Age 36, Overall 86, Club: **Manchester United** (Dramatic return transfer August 27, 2021).
  * **Robert Lewandowski:** Age 33, Overall 87, Club: **Bayern München** (Broke Gerd Müller's Bundesliga single-season record).
  * **Neymar Jr:** Age 29, Overall 87, Club: **Paris Saint-Germain**.
  * **Kylian Mbappé:** Age 22, Overall 86, Club: **Paris Saint-Germain**.
  * **Erling Haaland:** Age 21, Overall 83, Club: **Borussia Dortmund**.

### 4.6 `2022.db` — Confirmed Era: 2022–2023 Season & 2022 World Cup Year
* **Database Size:** 7,340,032 B | 39,346 players | 1,399 clubs | 162 competitions
* **Player Age Range:** 14 – 49 years (Average: 25.73)
* **Concrete Roster Evidence:**
  * **Karim Benzema:** Age 34, Overall 83, Club: **Real Madrid** (2022 Ballon d'Or winner after Champions League campaign).
  * **Robert Lewandowski:** Age 34, Overall 83, Club: **Barcelona** (Summer 2022 transfer from Bayern).
  * **Erling Haaland:** Age 22, Overall 73, Club: **Manchester City** (Transferred July 2022 from Dortmund).
  * **Sadio Mané:** Age 30, Overall 80, Club: **Bayern München** (Transferred June 2022 from Liverpool).
  * **Lionel Messi:** Age 35, Overall 84, Club: **Paris Saint-Germain** (World Cup winning season).
  * **Cristiano Ronaldo:** Age 37, Overall 78, Club: **Manchester United** (Pre-Al-Nassr December move).

### 4.7 `2025.db` — Confirmed Era: 2024–2025 Season
* **Database Size:** 10,342,400 B | 55,624 players | 2,014 clubs | 225 competitions
* **Player Age Range:** 15 – 49 years (Average: 25.28)
* **Concrete Roster Evidence:**
  * **Kylian Mbappé:** Age 26, Overall 91, Club: **Real Madrid** (Free transfer July 2024).
  * **Alexander Isak:** Age 25, Overall 90, Club: **Liverpool**.
  * **Erling Haaland:** Age 25, Overall 90, Club: **Manchester City**.
  * **Lamine Yamal:** Age 18, Overall 89, Club: **Barcelona** (Breakout Euro 2024 champion).
  * **Lionel Messi:** Age 38, Overall 86, Club: **Inter Miami** (MLS).
  * **Cristiano Ronaldo:** Age 40, Overall 83, Club: **Al-Nassr** (Saudi Pro League).

### 4.8 `2026.db` — Confirmed Era: 2025–2026 Modern Season
* **Database Size:** 10,477,568 B | 56,207 players | 2,023 clubs | 228 competitions
* **Player Age Range:** 14 – 58 years (Average: 25.28)
* **Concrete Roster Evidence:**
  * **Erling Haaland:** Age 25, Overall 90, Club: **Manchester City**.
  * **Kylian Mbappé:** Age 27, Overall 90, Club: **Real Madrid**.
  * **Mohamed Salah:** Age 33, Overall 88, Club: **Liverpool**.
  * **Harry Kane:** Age 32, Overall 88, Club: **Bayern München**.
  * **Lionel Messi:** Age 38, Overall 85, Club: **Inter Miami**.
  * **Cristiano Ronaldo:** Age 41, Overall 84, Club: **Al-Nassr**.

### 4.9 `2026_w_.db` — Confirmed Classification: Women's Football Dataset (2026)
* **Database Size:** 1,355,776 B | 5,366 female players | 200 clubs | 228 competitions
* **Player Age Range:** 15 – 46 years (Average: 24.36)
* **Concrete Competition Evidence:**
  * Tournaments include: **`Liga MX Femenil`**, **`WSL`** (Women's Super League), **`WSL 2`**, **`WFA Cup`** (Women's FA Cup), **`Brasileiro Série A1`**.
* **Concrete Club Evidence:**
  * Clubs include: **Gotham FC**, **VfL Wolfsburg**, **AS Roma**, **Kansas City Current**, **OL Lyonnes**, **Houston Dash**, **FC Barcelona Femení**, **Orlando Pride**.
* **Concrete Player Evidence:**
  * **Alexia Putellas:** Age 32, Overall 82, Club: **Barcelona** (Two-time Ballon d'Or Femení).
  * **Aitana Bonmatí:** Age 28, Overall 80, Club: **Barcelona** (Reigning Ballon d'Or Femení).
  * **Martina Tufeković:** Age 31, Overall 88, Club: **Wolfsburg**.
  * **Ann-Katrin Berger:** Age 35, Overall 88, Club: **Gotham FC**.
  * **Kayla Sharples:** Age 28, Overall 87, Club: **Kansas City Current**.
  * **Sam Kerr:** Represented via Chelsea and national squads.

### 4.10 `superkickoff.db` — Confirmed Classification: Active Master Database
* **Database Size:** 11,735,040 B | 62,928 players | 2,136 clubs | 245 competitions
* **Role:** Serves as the primary, default baseline database.
* Contains the most expansive roster in the game (including extensive lower divisions and world leagues not present in the historical snapshots).
* Reflects the current state of world football (Messi at Inter Miami, Ronaldo at Al-Nassr, Mbappé at Real Madrid, Haaland at Man City).

---

## 5. Cross-Era Player Evolution Analysis

Tracking specific reference players across all 10 databases proves that player records were authentically constructed for each era rather than batch-copied:

| Player Name | 1998.db | 2008.db | 2012.db | 2015.db | 2021.db | 2022.db | 2025.db | 2026.db | superkickoff.db |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Zinedine Zidane** | Age 26 (Juventus) | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* |
| **Ronaldo Nazário** | Age 22 (Inter) | *Not listed* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* |
| **Ronaldinho** | Age 18 (Grêmio) | Age 28 (Barcelona) | Age 32 (Atl. Mineiro) | *Not listed* | *Retired* | *Retired* | *Retired* | *Retired* | *Retired* |
| **Lionel Messi** | *Not in DB* | Age 21 (Barcelona) | Age 25 (Barcelona) | Age 28 (Barcelona) | Age 34 (PSG) | Age 35 (PSG) | Age 38 (Inter Miami) | Age 38 (Inter Miami) | Age 39 (Inter Miami) |
| **Cristiano Ronaldo**| *Not in DB* | Age 23 (Man. United) | Age 27 (Real Madrid) | Age 30 (Real Madrid) | Age 36 (Man. United) | Age 37 (Man. United) | Age 40 (Al-Nassr) | Age 41 (Al-Nassr) | Age 41 (Al-Nassr) |
| **Kylian Mbappé** | *Not in DB* | *Not in DB* | *Not in DB* | *Not in DB* | Age 22 (PSG) | Age 23 (PSG) | Age 26 (Real Madrid) | Age 27 (Real Madrid) | Age 27 (Real Madrid) |
| **Erling Haaland** | *Not in DB* | *Not in DB* | *Not in DB* | *Not in DB* | Age 21 (Dortmund) | Age 22 (Man. City) | Age 25 (Man. City) | Age 25 (Man. City) | Age 26 (Man. City) |

---

## 6. Schema Parity & Architectural Uniformity

A strict schema diff was executed comparing all 44 tables, views, and columns of `superkickoff.db` against all 9 other databases:

* **Table Difference:** `0` (Every database contains the exact same 44 tables and 1 view).
* **Column Difference in `jug_jugadores`:** `0` (Identical 23 columns: `jugid`, `jug_nombre`, `jug_edad`, `jug_estatura`, `jug_star`, `jug_valor`, `jug_salario`, `jug_perfil`, `jug_experiencia`, `jug_condicion`, `jug_jstdid`, `jug_poder`, `jug_potencial`, `jug_mercado`, `jug_paid`, `jug_posid`, `jug_titular`, `jug_capitan`, `jug_numero`, `jug_campeonatos`, `jug_pts`, `jug_habilidad_A`, `jug_habilidad_B`).
* **Column Difference in `eq_equipos`:** `0` (Identical 12 columns: `equid`, `equi_abrev`, `equi_nombre`, `equi_funda`, `equi_valor`, `equi_poder`, `equi_presupuesto`, `equi_pts`, `equi_estaid`, `equi_paid`, `equi_entid`, `equi_division`).
* **Runtime Data State:** `0` rows across all databases in `tor_temporadas`, `tor_partidos`, `tor_partidos_incidencias`, `tor_transferencias_jugadores`, and `historial_user`.

### Architectural Takeaway:
This 100% schema parity means Super Kickoff's Flutter frontend requires **zero schema migrations or conditional branching** when switching game modes or starting a career in a retro era. The app simply instantiates `sqflite` with the selected database file, and all SQL queries, models, and UI widgets function identically.

---

## 7. Confirmed Findings vs. Hypotheses

| Finding | Classification | Supporting Evidence |
| :--- | :--- | :--- |
| **10 Total Databases in APK** | **Confirmed** | Exact archive entries verified in `assets/flutter_assets/assets/`. |
| **`1998.db` = 1997/98 Season** | **Confirmed** | Zidane (26, Juventus), Ronaldo (22, Inter), Klinsmann (34, Tottenham), Ronaldinho (18, Grêmio). |
| **`2008.db` = 2007/08 Season** | **Confirmed** | Lampard (30, Chelsea), Ronaldinho & Henry (Barcelona), C. Ronaldo (23, Man Utd), Messi (21, Barcelona). |
| **`2012.db` = 2011/12 Season** | **Confirmed** | Messi (25, Barcelona, 94 OVR), C. Ronaldo (27, Real Madrid, 93 OVR), Eto'o (31, Anzhi). |
| **`2015.db` = 2014/15 Season** | **Confirmed** | Messi (28, Barcelona), C. Ronaldo (30, Real Madrid), Suárez (28, Barcelona), Godín (29, Atl Madrid). |
| **`2021.db` = 2021/22 Fall Snapshot** | **Confirmed** | Messi (34, PSG), C. Ronaldo (36, Man United), Lewandowski (33, Bayern). |
| **`2022.db` = 2022/23 Season** | **Confirmed** | Benzema (34, Real Madrid), Lewandowski (34, Barcelona), Haaland (22, Man City), Mané (30, Bayern). |
| **`2025.db` / `2026.db` = Modern Seasons** | **Confirmed** | Mbappé (Real Madrid), Yamal (Barcelona), Messi (Inter Miami), Ronaldo (Al-Nassr). |
| **`2026_w_.db` = Women's Football** | **Confirmed** | 200 women's clubs (Gotham, Wolfsburg, Roma, Kansas City), WSL, Liga MX Femenil, Putellas & Bonmatí. |
| **`superkickoff.db` = Master Database** | **Confirmed** | Largest roster (62,928 players, 2,136 clubs, 245 leagues). |
| **Clean Baseline Seeds** | **Confirmed** | All runtime tables (`tor_partidos`, `tor_temporadas`) have 0 rows. |
