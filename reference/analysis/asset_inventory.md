# Super Kickoff — Asset Inventory & Archive Inspection

**Date of Analysis:** 2026-10-25  
**Target Package:** `app.superkickoff` (Version `4.3.4`, Build `119`)  
**Source Archive:** `Superkickoff+-+Soccer+manager_4.3.4_APKPure.xapk`  
**Inspection Workspace:** `reference/superkickoff/`

---

## 1. Archive & APK Architecture Overview

The application is distributed as a multi-split Android App Bundle (`.xapk`), consisting of 4 distinct APK files and package metadata:

| File Name | File Size | Internal File Count | Role / Architecture Component |
| :--- | :--- | :--- | :--- |
| **`app.superkickoff.apk`** | 83,546,788 B (~83.5 MB) | 1,182 files | Base APK containing Flutter runtime assets, bundled SQLite databases, fonts, UI graphics, and Android DEX bytecode. |
| **`config.arm64_v8a.apk`** | 34,878,500 B (~34.9 MB) | 14 files | Architecture split containing 64-bit ARM native binaries (`libflutter.so`, `libapp.so`, `libsqlite3.so`, third-party SDKs). |
| **`config.en.apk`** | 45,266 B (~45.3 KB) | 3 files | Localization split for English Android resources (`resources.arsc`). |
| **`config.mdpi.apk`** | 60,332 B (~60.3 KB) | 70 files | Density split containing standard medium-density Android framework icons and drawables. |
| **`icon.png`** | 433,249 B (~433 KB) | N/A | High-resolution application launcher icon. |
| **`manifest.json`** | 1,115 B | N/A | APKPure bundle configuration specifying split IDs (`base`, `config.arm64_v8a`, `config.en`, `config.mdpi`). |

---

## 2. Bundled Database Files

Ten pre-compiled SQLite 3 database files are bundled directly in the Flutter asset tree under `assets/flutter_assets/assets/`. They represent different football eras, seasons, and competition formats:

| Database File | Uncompressed Size | Compressed Size | Player Count | Club Count | Tournaments | Scope / Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`superkickoff.db`** | 11,735,040 B (~11.7 MB) | 4,175,988 B | 62,928 | 2,136 | 245 | **Active Master Database** (Current full world database) |
| **`2026.db`** | 10,477,568 B (~10.5 MB) | 3,777,502 B | 56,207 | 2,023 | 228 | 2026 Modern Season snapshot |
| **`2025.db`** | 10,342,400 B (~10.3 MB) | 3,673,937 B | 55,624 | 2,014 | 225 | 2025 Modern Season snapshot |
| **`2022.db`** | 7,340,032 B (~7.3 MB) | 2,571,008 B | 39,346 | 1,399 | 162 | 2022 Season snapshot |
| **`2021.db`** | 5,111,808 B (~5.1 MB) | 1,864,800 B | 26,966 | 954 | 115 | 2021 Season snapshot |
| **`2015.db`** | 7,938,048 B (~7.9 MB) | 2,850,875 B | 42,483 | 1,420 | 228 | 2015 Historical Era snapshot |
| **`2012.db`** | 7,069,696 B (~7.1 MB) | 2,544,454 B | 37,767 | 1,360 | 192 | 2012 Historical Era snapshot |
| **`2008.db`** | 5,251,072 B (~5.3 MB) | 1,850,555 B | 27,669 | 1,040 | 225 | 2008 Historical Era snapshot |
| **`1998.db`** | 3,506,176 B (~3.5 MB) | 1,224,613 B | 17,461 | 700 | 225 | 1998 Historical Era snapshot |
| **`2026_w_.db`** | 1,355,776 B (~1.4 MB) | 423,558 B | 5,366 | 200 | 228 | Women's Football League database |

---

## 3. Graphics & Visual Assets

All game graphic assets are stored inside `assets/flutter_assets/assets/` and registered in Flutter's `AssetManifest.bin` (385 total asset keys):

### 3.1 Player Face & Portrait System (`assets/caras/` — 39 files)
All image files are 128x128 PNG images. There are **no individual real photographs of players**:
- **Nationality Templates (14 files):** `ar.png`, `br.png`, `de.png`, `en.png`, `fr.png`, `gb.png`, `id.png`, `it.png`, `ko.png`, `mx.png`, `pt.png`, `ru.png`, `th.png`, `tr.png`.
- **Era-Specific Nationality Templates (22 files):**
  - 1998 Era: `1998_br.png`, `1998_fr.png`, `1998_mx.png`, `1998_ru.png`, `1998_tr.png`
  - 2008 Era: `2008_ar.png`, `2008_br.png`, `2008_de.png`, `2008_fr.png`, `2008_gb.png`, `2008_it.png`, `2008_mx.png`, `2008_ru.png`, `2008_tr.png`
  - 2012 Era: `2012.png`
  - 2021 Era: `2021_ar.png`, `2021_br.png`, `2021_mx.png`, `2021_pt.png`, `2021_tr.png`
  - 2025/2026: `2025.png`, `2026.png`, `2026_w.png`
- **Composite Layering Assets:**
  - `camisa.png` (3,843 B, 128x128): Kit/Jersey overlay rendered beneath the face/head.
  - `animada.png` (2,056 B): Cartoon / animated base face outline.

### 3.2 Club Badges / Shields (`assets/escudos/` — 17 files)
Generic heraldic icons used to procedurally represent football clubs without infringing official trademarks:
- `ancla.png` (anchor)
- `balon.png` (football)
- `calaca.png` (calavera skull)
- `chuparrosa.png` (hummingbird)
- `conejo.png` (rabbit)
- `corona.png` (crown)
- `craneo.png` (skull)
- `demonio.png` (demon/devil)
- `dragon.png` (dragon)
- `espada.png` (sword)
- `hacha.png` (axe)
- `leon.png` (lion)
- `panal.png` (honeycomb)
- `pollo.png` (rooster/chicken)
- `rosa.png` (rose)

### 3.3 Stadium Illustrations (`assets/estadios/` — 2 files)
- `estadioA.jpg`: Day stadium rendering.
- `estadioC.jpg`: Night/floodlit stadium rendering.

### 3.4 Country Flags (`packages/flagkit/assets/flags/` — 255 files)
Standardized 3x high-resolution PNG country flags keyed by ISO 3166-1 alpha-2 code (e.g. `AR@3x.png`, `BR@3x.png`, `ES@3x.png`, `GB@3x.png`, `US@3x.png`), mapping 1-to-1 with `paises.iso2`.

### 3.5 UI, Award, & Trophy Art (`assets/` root — 29 files)
- **Trophies & Awards:** `balon_oro.png` (Ballon d'Or), `bota_oro.png` (Golden Boot), `guante_oro.png` (Golden Glove), `joven_oro.png` (Golden Boy / Best Young Player), `pichichi.png` (Top Scorer trophy), `estrella-del-trofeo.png`, `icono-de-trofeo.png`.
- **Match & Economy UI:** `balonA.png`, `pergamino.png`, `ticket.png`, `callese_icon.png`, `eye_close.png`, `splash.png`, `art.png`.
- **Icons (`assets/iconos/`):** `left-foot.png`, `right-foot.png`, `zapato.png`, `cortadoraPapel.png`.

---

## 4. Audio Assets (`assets/sonidos/` — 7 files)

The game includes 7 compact MP3 sound effects used during match simulation and UI interaction:

| Sound File | File Size | In-Game Trigger Event |
| :--- | :--- | :--- |
| `silbato.mp3` | 39,980 B | Referee whistle (match start, half-time, full-time) |
| `gol.mp3` | 35,245 B | User team scores a goal (cheer / stadium reaction) |
| `gol_contra.mp3` | 63,457 B | Opponent scores a goal |
| `penalty.mp3` | 16,896 B | Penalty awarded |
| `lesion.mp3` | 15,508 B | Player injury event |
| `success.mp3` | 19,140 B | Action completed / transfer signed / trophy won |
| `error.mp3` | 6,288 B | Failed action / rejection |

---

## 5. Typography & Fonts (33 files)

Super Kickoff includes a rich collection of custom fonts specified in `FontManifest.json`:

1. **Proprietary Game Font:** `SuperkickoffIcons.ttf` (`assets/iconos/SuperkickoffIcons.ttf`) — Custom icon font containing football-specific icons (cards, boots, pitch positions).
2. **Standard Flutter Icon Fonts:** `MaterialIcons-Regular.otf`, `CupertinoIcons.ttf`, `Font-Awesome-7` (Brands, Free Regular, Free Solid).
3. **Display & Header Fonts (27 Google Fonts):**
   - Sans & UI: `Inter-VariableFont.ttf`, `Roboto-Regular.ttf`, `Montserrat-Regular.ttf`, `WorkSans-Regular.ttf`, `IBMPlexSans-VariableFont.ttf`, `Prompt-Regular.ttf`.
   - Athletic & Display: `AlumniSansRegular.ttf`, `BungeeInline-Regular.ttf`, `CarroisGothicSCRegular.ttf`, `DiplomataSCRegular.ttf`, `MonotonRegular.ttf`, `NewRockerRegular.ttf`, `RoadRageRegular.ttf`, `RubikBubblesRegular.ttf`, `ArbutusRegular.ttf`, `CaesarDressingRegular.ttf`, `ComingSoon-Regular.ttf`, `FrederickatheGreatRegular.ttf`, `HanaleiFillRegular.ttf`.

---

## 6. Native Dynamic Libraries (`config.arm64_v8a.apk`)

The native binary split contains 12 shared libraries (`.so`):

| Library | File Size | Description & Role |
| :--- | :--- | :--- |
| **`libapp.so`** | 20,054,920 B (~20.1 MB) | AOT-compiled Dart application logic for the entire game. |
| **`libflutter.so`** | 11,747,864 B (~11.7 MB) | Core Flutter engine runtime (Skia/Impeller renderer, shell, Dart VM runtime). |
| **`libsqlite3.so`** | 1,732,360 B (~1.7 MB) | Pre-compiled native SQLite library accessed via Dart FFI (`package:sqlite3`). |
| **`libdartjni.so`** | 131,400 B | JNI bindings bridging Dart and native Android runtime. |
| **`libtt_ugen_layout.so`** | 440,672 B | TikTok / Pangle ad layout engine. |
| **`libnms.so`** | 302,248 B | Network / mediation security library. |
| **`libapminsighta.so`** | 102,256 B | Performance monitoring SDK. |
| **`libapminsightb.so`** | 124,352 B | Performance monitoring SDK companion. |
| **`libpglarmor.so`** | 68,776 B | Anti-tamper / security binary wrapper. |
| **`libbuffer_pgl.so`** | 9,000 B | Buffer utility for PGL SDK. |
| **`libdatastore_shared_counter.so`**| 7,112 B | Inter-process counter utility. |
| **`libfile_lock_pgl.so`** | 6,312 B | File lock utility for ad caching. |

---

## 7. Security & Certificate Files

- `assets/flutter_assets/assets/isrgrootx1.pem` (1,970 B)
- `assets/flutter_assets/assets/lets-encrypt-r3.pem` (1,856 B)
These are root CA certificates packaged for HTTPS pinning and secure API communications with game servers.
