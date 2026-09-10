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
- **Windows:** nur CI, manuell — `gh workflow run windows-export.yml` (bei Release).

## Design-Entscheidungen

- **Canvas** 480×800 Portrait, Zelle 32 px, Well bei (80,120). HUD-Band oben
  (Score/Level/Lines, Hold links, Next rechts).
- **Steuerung**: Tastatur (Pfeile/WASD, X/Z drehen, Space Hard-Drop, C/End
  Hold, Esc/P Pause) · Gamepad · **Maus**: Cursor-Spalte = Ziel, das Spiel
  fittet Drehung+Landung dorthin (BFS + Heuristik, tuckt unter Überhänge),
  Ghost zeigt es; Mausrad = Drehung erzwingen, Linksklick Hard-Drop,
  Rechtsklick Hold.
- **Scoring**: 100/300/500/800 ×Level, Soft-Drop +1/Zeile, Hard-Drop +2/Zeile,
  Level alle 10 Zeilen, Gravity `pow(0.8-(l-1)*0.007, l-1)`.
- **Settings** (`user://settings.cfg`, Abschnitt `game`): `start_level` 1–15,
  `ghost` on/off. Abschnitt `sound` reserviert (Sounds kommen später).
- **Hall of Fame** (`user://hall_of_fame.cfg`): Top 10 nach Score, Namenseingabe
  bei Qualifikation am Ende jedes Durchlaufs.
- **Splash**: `splash-screen.png` (Wurzel) als Boot-Splash und Start-Screen-
  Hintergrund.

## Touch / mobile (fertig, Commit 573d4e9)

- Auto-Erkennung (`OS.has_feature("mobile")` / `DisplayServer.is_touchscreen_available()`,
  gecacht) + retroaktiver Flip beim ersten echten Screen-Touch.
- `content_scale_aspect` = **KEEP für alle Geräte** (nicht KEEP_WIDTH): eine
  480×800-Canvas würde unter KEEP_WIDTH auf 3:4-Tablets abgeschnitten; das
  breitere HUD-Band trägt die Touch-Buttons, also braucht es keinen Extraraum.
  Bewusste Abweichung von der pacman-Design-Regel.
- Swipe: h-Drag = Bewegen (1 Zelle / 26 px), gedrückt-nach-unten = Soft-Drop,
  schneller Flick nach unten = Hard-Drop, kurzer Tipp = Drehen.
- On-screen **PAUSE** (links oben) und **HOLD** (rechts oben) im festen Band,
  ausgeblendet bei offenem Menü / Game Over.

## Hilfe-Screen (bildbasiert)

Vollbild-Blättern in `ui.gd` (`show_help` / `_build_help_overlay` / `_help_go`):
- Untere Leiste `‹  Done  ›` + Seitenpunkte; Weiter/zurück per Pfeiltasten, A/D,
  Mausrad, den Pfeil-Buttons, Touch-Swipe. `Esc`/`Space`/`Done` → zurück ins
  aufrufende Menü (Start **oder** Pause). Umlauf an.
- Zwei Seitensätze, `main.set_help_context()` schaltet um:
  - **Maus:** `mouse` · `aim-mouse` · `hud` · `keyboard` · `goal`
  - **Touch:** `swipe` · `aim-touch` · `hud` · `goal`
- Bilder: `assets/graphics/help/<name>.png` (aus `assets/help_src/<name>.svg`,
  `render.sh`). Fehlt eine PNG → Text-Platzhalter, Seiten kommen einzeln.
- Fertig: `mouse`, `aim-mouse`. Offen: `hud`, `keyboard`, `goal`, `swipe`,
  `aim-touch`. Text durchgängig Englisch.

## Sounds (`assets/sounds/`, alle vorhanden)

`SoundManager`-Autoload wie pacman (`sound_manager.gd`): `SOUNDS`-Map
`key -> [Anzeigename, Default-%]`, `_BASE_DB`-Kalibrierung je Sound (100 % klingt
ausgewogen), Vorhör bei Reglerwechsel, Persistenz `user://settings.cfg`
Abschnitt `sound`, `_CALIB_VERSION`.

| Datei | Event | Hinweis |
|---|---|---|
| `tetris-theme.ogg` | Hintergrund-Loop | an/aus über **allgemeine** Settings (nicht Sound-Settings — die regeln nur Lautstärke) |
| `click-sound.ogg` | jede Horizontalbewegung: Maus links/rechts, jede Rasterposition beim Swipen, jeder Tap / Mausklick | **leisester** Sound |
| `drop-sound.ogg` | Hard-Drop bzw. wenn ein Stein gesetzt/gelockt wurde | |
| `hold-sound.ogg` | Hold | |
| `one-line-cleared.ogg` | genau 1 Zeile gecleared | |
| `line-cleared.ogg` | 2+ Zeilen gecleared | |
| `game-over-sound.ogg` | Game Over | |

Sound-Settings-Unterseite: pro Sound ein 0–100-%-Regler. Allgemeine Settings:
Schalter „Music" (Theme-Loop an/aus).

## Offen / später

- Einstellungen: Tastenbelegung im Spiel anpassbar machen.
- Restliche Hilfe-Bilder: `hud`, `keyboard`, `goal`, `swipe`, `aim-touch`
  (dann `aim` wieder maus-spezifisch).
- Politur: Line-Clear-Animation, T-Spin/Combo, Level-Up-Feedback.
- Politur: Line-Clear-Animation, T-Spin/Combo-Scoring, Level-Up-Feedback.

## Aseprite MCP Pro

Bei Nutzung der Aseprite-MCP-Pro-Tools (`mcp__aseprite-mcp-pro__*`) dem
Pixel-Art-Skill-Guide folgen:
@/home/bernd/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/aseprite-mcp-pro-server/skills.md
