# CLAUDE.md — Tetris

Ergänzt die übergeordnete `CLAUDE.md` unter
`~/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/`.

## Aufbau

- Godot 4.7, fast alles im Code. Eine winzige `main.tscn` (nur `Main`/Node2D).
- `pieces.gd` — statische Tetromino-Daten (4 SRS-Zustände, Kick-Tabellen, Farben).
- `playfield.gd` — 10×20-Well, aktiver Stein, Gravity/Lock, Line-Clear,
  Ghost, Rendering, **Maus-Platzierungs-Suche** (`suggest_placement`).
- `main.gd` — Score/Level/Lines/Fall-Speed, State-Machine, Input-Routing, HUD.
- `ui.gd` — alle Menü-Screens (CanvasLayer, im Code): Start / Pause /
  Settings (+ Sound-Unterseite) / How to Play / Game Over + Hall of Fame.
- `_selftest.gd` — Headless-Checks: `godot --headless --path . --script res://_selftest.gd`
- `assets/help_src/` — SVG-Quellen der Hilfe-Bilder + `render.sh` (Inkscape → PNG).
  `.gdignore` drin, damit Godot die SVGs nicht importiert. Gerenderte PNGs liegen
  in `assets/graphics/help/`.

## Bauen & Testen (Editor bleibt zu)

Godot-Editor **nicht** öffnen. Alle drei lokalen Builds per Skript:

```
bash projects/tetris/build.sh            # Linux + Web + Android (+ adb install)
bash projects/tetris/build.sh web        # einzeln: linux | web | android
```

Aufrufen:
- **Linux:** `/home/bernd/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/projects/tetris-linux.x86_64`
- **Web:** `cd projects/web-release-tetris && python3 -m http.server 8099` → `http://localhost:8099/`
- **Android:** von `build.sh` direkt installiert; sonst
  `~/Android/Sdk/platform-tools/adb install -r projects/tetris-android.apk`
- **Windows:** CI. Release-Tag pushen → Build + GitHub-Release:
  `git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z` (oder manuell
  `gh workflow run windows-export.yml`). `config/version` in `project.godot`
  vorher passend setzen.

Browser-Test primär im Claude-In-App-Panel. Fällt das aus, ist
`chrome-devtools`-MCP (`-s local` für dieses Projekt registriert, `mcp__chrome-devtools__*`)
der Fallback — echtes Chrome, isoliertes Profil, läuft über Node 22 unter `~/opt/node22/`.

## Design-Entscheidungen

- **Design-Canvas** 480×640 (`project.godot`). Layout ist voll responsiv:
  `main._layout()` rechnet Zellgröße (14–60 px) und jede HUD-Position aus
  `get_viewport_rect()`, `content_scale_aspect = EXPAND`, neu bei `size_changed`.
  HUD-Band oben: Score/Level/Lines mittig, Hold-Button+Box links, Pause-Button+
  Next-Box rechts, jeweils ~35 px außerhalb der Brettkante.
- **Steuerung**: Tastatur (Pfeile/WASD, X + die Taste links davon zum Drehen —
  auf QWERTZ „Y", `physical_keycode`, Space Hard-Drop, C/End
  Hold, Esc/P Pause) · Gamepad · **Maus**: Cursor-Spalte = Ziel, das Spiel
  fittet Drehung+Landung dorthin (BFS + Heuristik, tuckt unter Überhänge),
  Ghost zeigt es; Mausrad = Drehung erzwingen, Linksklick Hard-Drop,
  Rechtsklick Hold.
- **Scoring**: 100/300/500/800 ×Level, Soft-Drop +1/Zeile, Hard-Drop +2/Zeile,
  Level alle 10 Zeilen, Gravity `pow(0.8-(l-1)*0.007, l-1)`.
- **Settings** (`user://settings.cfg` Abschnitt `game`): `start_level` 1–15,
  `ghost` on/off, `music` on/off. Abschnitt `sound` = Pro-Sound-Lautstärken
  (siehe unten).
- **Hall of Fame** (`user://hall_of_fame.cfg`): Top 10 nach Score, Namenseingabe
  bei Qualifikation am Ende jedes Durchlaufs.
- **Splash**: `splash-screen.png` (Wurzel) als Boot-Splash, In-Game-Ladescreen
  und Start-Screen-Hintergrund — überall vollständig, letterboxed auf Schwarz.

## Touch / mobile (fertig)

- Auto-Erkennung (`OS.has_feature("mobile")` / `DisplayServer.is_touchscreen_available()`,
  gecacht) + retroaktiver Flip beim ersten echten Screen-Touch
  (`main._enter_touch_mode`).
- Swipe irgendwo = Ziel-Spalte setzen (Ghost fittet, wie Maus). **1× tippen =
  Hard-Drop, 2× tippen = drehen** (const `TAP_DROPS`), gedrückt-nach-unten-
  ziehen = optionaler Soft-Drop.
- On-screen **HOLD** (links oben) und **PAUSE** (rechts oben) im HUD-Band,
  ausgeblendet bei offenem Menü / Game Over.

## Hilfe-Screen (bildbasiert)

Vollbild-Blättern in `ui.gd` (`show_help` / `_build_help_overlay` / `_help_go`):
- Untere Leiste `‹  Done  ›` + Seitenpunkte; Weiter/zurück per Pfeiltasten, A/D,
  Mausrad, den Pfeil-Buttons, Touch-Swipe. `Esc`/`Space`/`Done` → zurück ins
  aufrufende Menü (Start **oder** Pause). Umlauf an.
- Zwei Seitensätze, `main.set_help_context()` schaltet um:
  - **Maus:** `mouse` · `aim` · `hud` · `keyboard` · `goal`
  - **Touch:** `swipe` · `aim-touch` · `hud` · `goal`
- Bilder: `assets/graphics/help/<name>.png` (aus `assets/help_src/<name>.svg`,
  `render.sh`, Inkscape → PNG; `ui.gd` lädt sie on-demand per `load()`, **nicht**
  über `ResourceLoader.exists()` — das ist bei importierten Ressourcen in nativen
  Exports unzuverlässig). Fehlt eine PNG → Text-Platzhalter.
- Alle 7 Seiten fertig, Text durchgängig Englisch.

## Sounds (fertig — `sound_manager.gd`, Autoload `Snd`)

Autoload in `project.godot [autoload]`. Ein `AudioStreamPlayer` je Clip + Musik-
Loop. `SOUNDS`-Map mit `base_db` je Key (Kalibrierung, Klick am leisesten −7 dB),
Lautstärken 0–100 in `user://settings.cfg [sound]` + `calib_version`.
**Zugriff aus `class_name`-Skripten über `get_node_or_null("/root/Snd")` +
`preload("res://sound_manager.gd")` für Konstanten** — der blanke `Snd`-Bezeichner
löst unter `--script` nicht auf (bricht `_selftest.gd`).

| Key / Datei | Event |
|---|---|
| `music` / `tetris-theme.ogg` | Loop, an/aus über **allgemeine** Settings (`game/music`), läuft dann durchgehend |
| `move` / `click-sound.ogg` | jede Bewegung/Drehung/Tap/Wheel/Swipe-Rasterschritt/Mausklick (DAS-Repeat auf 50 ms gedrosselt) — leisester |
| `drop` / `drop-sound.ogg` | `piece_locked` (Hard-Drop **und** normales Lock) |
| `hold` / `hold-sound.ogg` | `hold_changed` |
| `line1` / `one-line-cleared.ogg` | genau 1 Zeile |
| `lines` / `line-cleared.ogg` | 2+ Zeilen |
| `over` / `game-over-sound.ogg` | `topped_out` |

Sound-Settings-Unterseite: pro Sound ein 0–100-Regler, Loslassen = Vorhören.

## Offen / später

- Einstellungen: Tastenbelegung im Spiel anpassbar machen.
- Eigene Sounds für 4 Reihen (Tetris) und 2 Reihen (Doppel) — hat der Nutzer
  noch nicht; Code routet aktuell 1 → `line1`, 2+ → `lines`.
- Politur: Line-Clear-Animation, T-Spin/Combo-Scoring, Level-Up-Feedback.

## Aseprite MCP Pro

Bei Nutzung der Aseprite-MCP-Pro-Tools (`mcp__aseprite-mcp-pro__*`) dem
Pixel-Art-Skill-Guide folgen:
@/home/bernd/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/aseprite-mcp-pro-server/skills.md
