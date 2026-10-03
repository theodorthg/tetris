# TODO — tetris

Offene Punkte sammeln und abhaken (gilt über Kontextwechsel hinaus; siehe
globale CLAUDE.md „TODO.md pro Projekt“). Neueste Einträge oben. Ältere
offene Punkte stehen ggf. noch in `CLAUDE.md`.

## Offen

- [ ] Alte, von Hand hochgeladene Dateien auf itch.io löschen (macht der Nutzer: https://itch.io/game/edit/…, Seite `tetris-clone`) und beim Upload des Channels `web` „This file will be played in the browser“ setzen.

Ideen für später (Einschätzung 2026-10-03, noch nicht beauftragt):
- [x] v1.1.0 Online-Versus (2026-10-03): wer Reihen löscht, schickt dem
      anderen Müllreihen (2→1, 3→2, Tetris→4, T-Spin 2/4/6; eigene
      Löschungen verrechnen erst wartenden Müll). Jedes Gerät behält sein
      Hochkant-Feld, vom Gegner ein Mini-Feld (~10 Updates/s), gleicher
      Zufalls-Seed → dieselben Teile. Über das gemeinsame Relay auf
      broesel.net (Spiel-Kennung „tetris“), auch im Browser. Revanche,
      Pause für beide, Stand „You 2 : 1 Opponent“. Getestet lokal (zwei
      Fenster) und RG552 ↔ Linux-PC über broesel.net.
- [x] v1.1.1: Versus-Hilfeseite `versus` (beide Hilfe-Folgen, vor „Goal“):
      eigenes Feld mit 2 Reihen → Pfeil → Gegner mit grauen Müllreihen +
      roter Leiste, Angriffstabelle, Host/Join.
- [ ] Versus im LAN (ohne Server, wie mario-clone v1.8) — bei Bedarf.
- [x] v1.1.1 Gamepad in allen Menüs (am RG552 mit echten Pad-Signalen
      geprüft): `ui_accept`/`ui_cancel` hatten keine Pad-Belegung (A/B
      ergänzt, device -1); jeder Bildschirm bekommt einen Startfokus
      (`Ui._focus_default`), Fokus kehrt auf den Knopf zurück, von dem man
      kam (`_last_btn`), hoch/runter laufen um, B = zurück, A bestätigt
      Eingabefelder, Hilfe blättert per Steuerkreuz, Pad-Knopf überspringt
      den Splash. „Start level“ ist ein Regler statt SpinBox (die SpinBox
      behielt hoch/runter für sich).
- [x] v1.1.2: eigene Hilfeseite „Gamepad“ (beide Hilfe-Folgen, nach
      Keyboard bzw. The buttons): gezeichnetes Pad mit Steuerkreuz, A/B/X/Y,
      Start und Belegung, Menü-Bedienung, Hinweis „Knöpfe nach Lage, nicht
      nach Aufdruck“ (Nintendo-Layout wie Anbernic: unten steht „B“).
      Tastaturseite verweist darauf.
- [ ] Versus lokal am PC: zwei Felder nebeneinander → braucht ein breites
      Fenster (globale Vorgabe 2: Splitscreen = Querformat).
- [ ] Zusätzliche Einzelspieler-Modi: Sprint (40 Reihen auf Zeit), Ultra
      (2 Minuten auf Punkte) — klein, eigene Bestenlisten.
- Coop auf einem Feld (zwei Teile gleichzeitig) gibt es, ist aber eher
  hakelig — nicht empfohlen.
- Empfehlung: Online-Versus zuerst, das ist der größte Spaßgewinn.

Gemeinsam für die Serie (Vorlage: mario-clone v1.6–v1.9):
- [ ] Bausteine aus mario-clone übernehmen statt neu erfinden: `CoopInput`
      + Beitreten-Bildschirm (jeder drückt A auf seinem Gerät),
      `NetLink`/`NetHost`/`NetClient` (Host rechnet, Gast zeigt; LAN +
      Online), Team-Eintrag in der Bestenliste, Spielstand/Continue,
      F12-Screenshot.
- [ ] Ein Relay für alle Spiele: `server/relay.js` um eine Spiel-Kennung
      in „host“/„join“ erweitern (sonst landet ein Galaga-Gast in einem
      Mario-Raum), Pfad bleibt `wss://broesel.net/mario-relay` oder ein
      neutraler Name.
- Hinweise: Hochkant-Spiele auf dem Handy zu zweit nur per Netz (zwei
  Leute an einem Handy-Bildschirm ist unpraktisch); lokal zu zweit am PC
  (geteilte Tastatur / zwei Pads) bzw. im Browser. Das RG552 kann wegen
  des kaputten Bluetooth kein zweites Pad.

## Erledigt

- [x] 2026-09-29 itch.io jetzt per `butler` in die Channels linux / android / windows / web (`theodorthg/tetris-clone`, wie bei mario-clone)
- [x] 2026-09-27 Android-System-Startbildschirm (vor dem Splash) einheitlich
      reines Weiß: `splash_screen/icon` = transparentes
      `assets/icon/android_splash_blank.png`, `branding_image` leer (Nutzer-
      wunsch, ohne Gradle-Build; Hintergrundfarbe ließe sich nur per Gradle
      ändern).
