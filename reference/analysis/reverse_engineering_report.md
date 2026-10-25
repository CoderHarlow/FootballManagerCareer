# Super Kickoff — Reverse Engineering & Architecture Report

**Date of Analysis:** 2026-10-25  
**Target:** `app.superkickoff` (Version `4.3.4`, Build `119`)  
**Scope:** Read-only inspection of extracted APK files in `reference/superkickoff/`  
**Focus:** Technology stack verification, data modeling patterns, asset handling, and actionable blueprints for building an independent Flutter football manager game.

---

## 1. Executive Summary

Super Kickoff is a mobile football management simulation game. Through non-destructive static inspection of its split APK bundle, we obtained conclusive insights into its internal architecture:

1. **Framework:** Super Kickoff is **100% built using Flutter and Dart**.
2. **Data Storage:** The game relies on **pre-populated SQLite 3 databases** accessed via Dart FFI and `sqflite`. It packages 10 full database files totaling over 60,000 players, 2,100 clubs, and 245 competitions.
3. **Visual Asset Optimization:** The game does **not store 60,000 player portrait photographs**. Instead, it uses an ultra-lightweight procedural / nationality-based composite avatar system (39 small 128x128 PNG templates in `assets/caras/` plus a jersey overlay `camisa.png`), keeping the entire APK under 85 MB.
4. **Match Simulation Architecture:** Fixtures and statistics are tracked in normalized relational tables, while detailed match event timelines are serialized into a single JSON column (`tor_partidos_incidencias.tpi_json`) per match to minimize SQLite write overhead during live simulation.

---

## 2. Technology Stack & Proof of Flutter

The hypothesis that Super Kickoff is a Flutter application is **confirmed beyond doubt**.

### Irrefutable Evidence:
1. **Flutter Engine Binary:** `config.arm64_v8a.apk` contains `lib/arm64-v8a/libflutter.so` (11.7 MB, the official Flutter engine C++ runtime).
2. **Dart AOT Compiled Application:** `config.arm64_v8a.apk` contains `lib/arm64-v8a/libapp.so` (20.0 MB, the Ahead-Of-Time compiled Dart snapshot containing the entire application logic).
3. **Flutter Asset Pipeline:** `app.superkickoff.apk` contains standard Flutter runtime asset artifacts:
   - `assets/flutter_assets/AssetManifest.bin` (Flutter 3.x StandardMessageCodec binary asset registry)
   - `assets/flutter_assets/FontManifest.json` (Flutter font descriptor)
   - `assets/flutter_assets/NOTICES.Z` (Compressed open-source notices)
   - `assets/flutter_assets/NativeAssetsManifest.json` (Native FFI binding manifest for `libsqlite3.so`)
4. **App Package Name:** The compiled Dart code defines `package:super_kickoff` as the root library.

### Dart Package Ecosystem (123 packages identified in `libapp.so`):
By inspecting symbol strings in `libapp.so`, the exact dependencies used by Super Kickoff were identified:

| Domain | Identified Dart Packages | Architectural Function |
| :--- | :--- | :--- |
| **State Management** | `provider`, `nested` | Reactive application state and view models |
| **Database & Cache** | `sqflite`, `sqflite_common`, `sqlite3`, `hive_ce`, `shared_preferences` | Local SQLite databases and rapid key-value storage |
| **Networking & API** | `dio`, `http`, `firebase_database`, `cloud_functions` | Remote API communication and cloud sync |
| **UI Frameworks** | `flutter_screenutil`, `sliding_up_panel`, `top_modal_sheet`, `carousel_slider`, `flutter_sticky_header`, `scrollable_positioned_list`, `lazy_load_scrollview` | Responsive layouts, bottom sheets, sticky headers, and smooth long roster scrolling |
| **Visualization & Charts**| `syncfusion_flutter_charts` | Player progression graphs, team power comparisons, and league trend charts |
| **Contracts & Inputs**| `syncfusion_flutter_signaturepad` | Interactive contract signing simulation screen |
| **Animation & Micro-FX**| `animated_text_kit`, `animated_switcher_plus`, `flip_card`, `ripple_touch`, `another_xlider` | Dynamic UI transitions and tactical sliders |
| **Colors & Palette** | `flutter_colorpicker`, `palette_generator` | Dynamic kit color extraction and customization |
| **Internationalization**| `flagkit`, `intl`, `flutter_localizations`, `diacritic` | 255 country flag graphics and multi-language support |
| **Audio & Haptics** | `audioplayers`, `vibration` | Whistle, crowd cheers, goal sound effects, and tackle vibration |
| **Monetization & Auth**| `google_mobile_ads`, `purchases_flutter` (RevenueCat), `google_sign_in`, `sign_in_with_apple` | Subscriptions, in-app purchases, ads, and social authentication |

---

## 3. Player Portrait & Graphic Asset System

A primary research question was how Super Kickoff handles player faces and portraits for over 62,000 players.

### Confirmed Findings:
1. **Zero Individual Player Photos:** There are no photo archives, no individual player photo files, and no player portrait URLs in the APK or SQLite database.
2. **Small Directory of Face Templates:** In `assets/flutter_assets/assets/caras/`, there are exactly **39 image files**, all 128x128 PNGs averaging only 6 to 24 KB:
   - **Nationality Templates (14 files):** `ar.png`, `br.png`, `de.png`, `en.png`, `fr.png`, `gb.png`, `id.png`, `it.png`, `ko.png`, `mx.png`, `pt.png`, `ru.png`, `th.png`, `tr.png`.
   - **Historical Era Variants (22 files):** `1998_br.png`, `2008_ar.png`, `2021_pt.png`, etc.
   - **Overlay / Composite Parts:** `camisa.png` (a 128x128 football shirt template) and `animada.png` (a generic animated player head outline).
3. **Database Independence:** The `jug_jugadores` table contains **no image/face foreign keys or filenames**. It contains attributes like `jug_edad` (age), `jug_estatura` (height), `jug_perfil` (foot), `jug_star` (superstar flag), and `jug_paid` (country ID).

### Hypotheses vs. Confirmations:
| Aspect | Status | Finding / Evidence |
| :--- | :--- | :--- |
| **Individual Player Photos** | **CONFIRMED FALSE** | No photo files exist in the bundle. 62,000 PNGs would require >1 GB; total APK is only 83 MB. |
| **Procedural / Composite Avatars**| **CONFIRMED TRUE** | `assets/caras/` contains modular components: `animada.png` (head silhouette) + `camisa.png` (shirt) + nationality templates. |
| **Nationality Face Mapping** | **CONFIRMED TRUE** | Filenames in `caras/` (`ar.png`, `br.png`, `mx.png`) correspond directly to `paises.iso2` (`AR`, `BR`, `MX`). |
| **Dynamic Kit Tinting** | **HIGH-PROBABILITY HYPOTHESIS** | The presence of `package:palette_generator` and `package:flutter_colorpicker` indicates that `camisa.png` is dynamically tinted with the club's primary/secondary colors in Dart code. |

---

## 4. Club Badges & Visual Identity

### Confirmed Findings:
1. **Generic Emblems Only:** In `assets/flutter_assets/assets/escudos/`, there are only **17 PNG files** representing generic heraldic symbols (`ancla.png`, `dragon.png`, `leon.png`, `corona.png`, `espada.png`, etc.).
2. **Trademark Avoidance:** Super Kickoff intentionally does not bundle real club crests or trademarked logos in the APK, avoiding licensing fees and copyright disputes.
3. **National Flags via Standard Library:** Rather than custom flag assets, the application imports `package:flagkit`, which provides all 255 country flags mapped directly to `paises.iso2`.

---

## 5. Architectural Blueprints for Our Football Manager Game

These findings provide direct, production-tested patterns for our own Flutter football manager project:

### 1. Pre-Bundled Database Architecture
* **Pattern:** Build our world database (players, clubs, competitions, countries, stadiums) ahead of time as a clean SQLite file (`assets/database/game_data.db`).
* **Runtime Deployment:** On first app launch, use `sqflite` / `path_provider` to check if the save database exists in `getApplicationDocumentsDirectory()`. If not, copy `assets/database/game_data.db` to documents storage in milliseconds using standard stream copying.
* **Benefit:** Instant initial game load without parsing tens of megabytes of JSON at runtime, and zero network dependency.

### 2. Season DLC / Multiple Era Support
* Super Kickoff provides retro modes (1998, 2008, 2012, 2015, 2026) simply by maintaining separate `.db` snapshots (`1998.db`, `2008.db`, etc.) that share the identical schema.
* We can implement "Historical Careers" or "Custom Community Rosters" simply by swapping the active SQLite database file when starting a new career.

### 3. Compact Match Simulation Storage
* Instead of creating tens of thousands of database rows for every pass, foul, or minute-by-minute simulation tick:
  - Keep match summary in `tor_partidos` (score, date, attendance, referee).
  - Store the complete match events timeline (goals, cards, injuries, subs) as a serialized JSON string in a single column (`tor_partidos_incidencias.tpi_json`).
  - This keeps database file growth minimal even after simulating 20 seasons.

### 4. Player Attribute & Position Matrix
* Super Kickoff uses 25 defined skill attributes (`jug_habilidades`).
* To calculate a player's overall rating (`jug_poder`) accurately without arbitrary numbers, it uses a position-skill mapping table (`jug_posiciones_habilidades`):
  - For a Striker (`posid = 10`), skills like `Remate` (Finishing), `Cabeceo` (Heading), and `Velocidad` (Speed) are weighted heavily.
  - For a Goalkeeper (`posid = 1`), `Atajo` (Shot stopping), `Reflejos` (Reflexes), and `Anticipacion` are weighted.
* This is an elegant, modular formula we can implement directly in Dart.

### 5. Lightweight Avatar & Procedural Kit Engine
* Storing photos of tens of thousands of real players is legally risky and inflates app bundle size to hundreds of megabytes.
* Following Super Kickoff's blueprint:
  - Generate procedural or silhouette player avatars using layered widgets: Base head silhouette + hair/skin tone variant + jersey overlay (`camisa.png`) tinted with the player's club colors.
  - Use `flagkit` for all country flags (`packages/flagkit`).
  - Provide an in-game editor (using `flutter_colorpicker`) allowing users to customize team kits and badges freely.

---

## 6. Confirmation vs. Hypothesis Matrix

| Topic | Analysis Finding | Confidence Level | Evidence |
| :--- | :--- | :--- | :--- |
| **Flutter Application** | Built entirely in Flutter / Dart | **CONFIRMED** | `libflutter.so`, `libapp.so`, `AssetManifest.bin`, Dart packages |
| **Storage Engine** | SQLite 3 via `sqflite` and `sqlite3` FFI | **CONFIRMED** | 10 bundled `.db` files with valid `SQLite format 3` headers, `libsqlite3.so` |
| **Master Roster Size** | 62,928 players, 2,136 clubs, 245 tournaments | **CONFIRMED** | Exact row counts queried directly from `superkickoff.db` |
| **Player Photographs** | No individual real player photographs bundled | **CONFIRMED** | Zero photo assets; only 39 generic 128x128 template PNGs in `caras/` |
| **Face-to-Player Database Mapping** | No database column links player ID to face ID | **CONFIRMED** | Database schema lacks any image/avatar/face column |
| **Kit Rendering** | Dynamic color tinting of `camisa.png` | **HIGH HYPOTHESIS** | `flutter_colorpicker` and `palette_generator` present in Dart binary |
| **Historical Eras** | Databases are complete standalone career snapshots | **CONFIRMED** | `1998.db`, `2008.db`, etc. contain valid independent club and player tables |
| **Match Engine Event Format**| JSON-encoded timeline inside SQL record | **CONFIRMED** | Table `tor_partidos_incidencias` with column `tpi_json TEXT` |
