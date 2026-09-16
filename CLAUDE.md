# CLAUDE.md — Tetris

Ergänzt die übergeordnete `CLAUDE.md` unter
`~/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/`.

**Stand: v1.0.4** (`config/version`), Tag `v1.0.4` — Windows-CI grün, GitHub-Release
mit `tetris-windows-v1.0.4.zip`. Neu seit v1.0.3: Tastenbelegung (Settings →
Controls), Line-Clear-Flash, T-Spin (Erkennung + Scoring + Flash-Text), Web-PWA
entfernt, Hilfe-Bilder vergrößert (grau 40 px / Zwischenüberschriften 42 px) &
vertikal entzerrt. Danach (noch ungetaggt): eigenes Android-App-Icon (siehe
„App-Icon" unten) — bei Bedarf mit dem nächsten Release taggen.

## App-Icon (kein Godot-Standard-Icon mehr)

Wie bei pacman/galaga: drei Dateien im Projekt-Wurzelverzeichnis nach dem
`<name>-icon *.png`-Schema, SVG-Quelle in `assets/icon_src/tetris-icon.svg`
(`.gdignore` daneben, damit Godot die SVG nicht importiert) — Motiv: T-, S-
und L-Tetromino in den echten Spielfarben (`pieces.gd::COLORS`), gleicher
Zell-Look wie `playfield.gd::_draw_cell` (Fläche + heller Rand + Top-Highlight),
dunkler Verlaufshintergrund + abgerundeter Cyan-Rahmen.
- `tetris-icon 432x432.png` — voller Hintergrund, scharfe Bild-Ecken (Android
  übernimmt das adaptive Masking selbst).
- `tetris-icon 192x192.png` — auf den Rahmen zugeschnitten, transparent
  außerhalb (für Launcher-Vorschauen, die nicht selbst maskieren).
- `tetris-icon 432x432 mono.png` — entsättigte Graustufen-Variante fürs
  Android-13+-„Themed Icon" (keine echte Alpha-Silhouette, nur Graustufen).

`export_presets.cfg`: `launcher_icons/main_192x192`,
`adaptive_foreground_432x432`, `adaptive_background_432x432` (bewusst dieselbe
432er-Datei für Vorder- und Hintergrund — kein Foreground/Background-Splitting
nötig bei einem schon opaken Vollbild) und `adaptive_monochrome_432x432`
zeigen auf die drei Dateien statt auf `res://icon.svg`. `config/icon` selbst
(Editor/Desktop-Fensterleiste/Web-Favicon) bleibt bewusst der Godot-Standard —
nur der Android-Launcher bekam ein echtes Icon.

## Architektur-Dossier (`docs/architecture-dossier/`, 2026-09-16)

Technisches Dossier als druckbares Claude-Artifact, nach demselben Muster wie
bei Galaga (siehe die globale CLAUDE.md, „Technische Dokumentation als
Claude-Artifact (druckbar/PDF-fähig)", und `projects/galaga/docs/
architecture-dossier/` als Referenz). Inhalt hier speziell für Tetris statt
Galagas Formationen/Kollisionen: Steuerung (Tastatur DAS/ARR, Maus-Aim, Touch-
Swipe), 7-Bag-Spawn + SRS-Rotation mit Wandkicks, Line-Clear-Erkennung +
T-Spin, Ghost-Piece + die BFS-Maus-Platzierungssuche (`suggest_placement()`),
Scoring/Leveling. `index.html` (Artifact-Quelle), `build_standalone.py`
(Base64-Inline-Export für den PDF-Druck), `prepare_assets.py`
(Diagramm-Regeneration), `diagrams/scenetree.dot`+`uml.dot` (Graphviz-Quellen).
Vier echte Screenshots (`assets/fig-gameplay.png`, `fig-rebind.png`,
`fig-aim.png`, `fig-goal.png`) — aus einem live laufenden, nicht-Editor
`godot --path projects/tetris`-Fenster auf demselben X-Display der Session,
gesteuert per `xdotool` (Mausklicks/-rad zum Stack-Aufbauen bzw. Hilfe-Blättern)
und mit `import -window <id>` eingefangen, nicht per Skript reproduzierbar
(siehe `prepare_assets.py`-Docstring).

Bietet wie bei Galaga den „Dossier ⇄ Godot-Editor"-Farbumschalter für die
Code-Panels, inklusive Druck-Unterstützung (Umschalter-Zustand bleibt auch im
PDF erhalten, fällt nicht auf den Blueprint-Print-Look zurück).

**Eigener Fund, über Galagas Stand hinaus**: die beiden Graphviz-Diagramme
(Szenenbaum, UML) sind hier bewusst als **SVG** eingebettet, nicht als PNG wie
bei Galaga. Grund: ein als PNG eingebettetes Diagramm (selbst nur ~60–160&nbsp;KB,
mit reduziertem DPI/Farbpalette) hat reproduzierbar Chromes
`--print-to-pdf`-Pipeline für das GESAMTE restliche Dokument kaputt gemacht —
jeder `body.godot-syntax`-Print-Selektor (der Umschalter) wurde für JEDE Seite
NACH dem PNG stillschweigend ignoriert, unabhängig von Spezifität/`!important`/
Regel-Reihenfolge (per Bisektion bestätigt: mit Platzhalter-Bildchen statt der
echten PNGs griff der Umschalter wieder; das Szenenbaum-Diagramm — vor dem
Code-Modul im Dokument — war der eigentliche Übeltäter, das spät im Dokument
sitzende UML-Diagramm war unschädlich, weil danach kein `.code`-Block mehr
kommt). Als Graphviz-**SVG** (`dot -Tsvg`, ~14–17&nbsp;KB, verlustfrei skalierbar)
tritt der Bug nicht auf. **Falls hier je wieder auf PNG zurückgewechselt
werden soll: den Umschalter über das GANZE Dokument (nicht nur die erste
Codezeile) neu gegenprüfen, `pdftoppm`-Sichtprüfung inklusive** — der Bug
zeigt sich erst auf Folgeseiten, ein Blick auf Seite&nbsp;1 reicht nicht.

Verifiziert wie bei Galaga per `google-chrome --headless --print-to-pdf`
gegen die tatsächliche `Tetris-Architektur-Dossier.html` (nicht nur eine über
`python3 -m http.server` servierte Rohdatei) + `pdftoppm`-Sichtprüfung aller
19 Seiten, in BEIDEN Umschalter-Zuständen.

## Aufbau

- Godot 4.7, fast alles im Code. Eine winzige `main.tscn` (nur `Main`/Node2D).
- `pieces.gd` — statische Tetromino-Daten (4 SRS-Zustände, Kick-Tabellen, Farben).
- `playfield.gd` — 10×20-Well, aktiver Stein, Gravity/Lock, Line-Clear,
  Ghost, Rendering, **Maus-Platzierungs-Suche** (`suggest_placement`).
- `main.gd` — Score/Level/Lines/Fall-Speed, State-Machine, Input-Routing, HUD.
- `ui.gd` — alle Menü-Screens (CanvasLayer, im Code): Start / Pause /
  Settings (+ Sound-Unterseite) / How to Play / Game Over + Hall of Fame.
- `_selftest.gd` — Headless-Checks: `godot --headless --path . --script res://_selftest.gd`.
  **Achtung:** fängt nur Parse-Fehler in `playfield.gd`/`pieces.gd` (harte
  Abhängigkeiten). `main.gd`/`ui.gd` zusätzlich prüfen mit
  `timeout 10 godot --headless 2>&1 | grep -iE "parse error|script error"`
  (bootet die echte Main-Scene).
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

## Controls / Tastenbelegung (fertig)

Settings → **Controls** (`ui.gd::_controls_screen`): 8 Aktionen, „tap a key"
fängt den nächsten Tastendruck (`_capturing`), Esc bricht ab. Layout-bewusste
Beschriftung via `DisplayServer.keyboard_get_label_from_physical`. Persistenz
`user://settings.cfg [keys]` als `physical_keycode`, angewandt in `_ready` über
`_apply_keys` → `InputMap`. „Reset to defaults" = `InputMap.load_from_project_settings()`.
Gamepad-Bindings bleiben unberührt.

## Line-Clear + T-Spin (fertig)

- **Line-Clear-Flash:** `playfield._lock_piece` friert bei vollen Reihen ein
  (`_clearing`), `_process` zeigt `CLEAR_TIME` (0.26 s) einen weißen Wash +
  Squash, dann `_collapse_cleared` → Reihen fallen. Sync-Version für den Test:
  `clear_full_rows()`.
- **T-Spin:** `_last_rot` (war der letzte Move eine Drehung?) + `_tspin_corners()`
  ≥ 3 blockierte Diagonalen. Signal `lines_cleared(rows, tspin)`. Scoring in
  `main`: `TSPIN_SCORE` 400/800/1200/1600 ×Level; auch T-Spin ohne Reihe zählt.
- **Flash-Text** (`main._flash`): „T-SPIN …" bzw. „LEVEL n" kurz übers Brett,
  `ThemeDB.fallback_font`.

## Offen / später

- Eigene Sounds für 4 Reihen (Tetris) und 2 Reihen (Doppel) — hat der Nutzer
  noch nicht; Code routet aktuell 1 → `line1`, 2+ → `lines`.
- Politur: Combo-Scoring.

## Aseprite MCP Pro

Bei Nutzung der Aseprite-MCP-Pro-Tools (`mcp__aseprite-mcp-pro__*`) dem
Pixel-Art-Skill-Guide folgen:
@/home/bernd/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/aseprite-mcp-pro-server/skills.md
