# TODO — tetris

Offene Punkte sammeln und abhaken (gilt über Kontextwechsel hinaus; siehe
globale CLAUDE.md „TODO.md pro Projekt“). Neueste Einträge oben. Ältere
offene Punkte stehen ggf. noch in `CLAUDE.md`.

## Offen

- [ ] Alte, von Hand hochgeladene Dateien auf itch.io löschen (macht der Nutzer: https://itch.io/game/edit/…, Seite `tetris-clone`) und beim Upload des Channels `web` „This file will be played in the browser“ setzen.

Ideen für später (Einschätzung 2026-10-03, noch nicht beauftragt):
- [ ] Versus (der Tetris-Klassiker für zwei): wer Reihen löscht, schickt
      dem anderen Müllreihen (2→1, 3→2, Tetris→4, T-Spin mehr). Ideal
      per Netz: jedes Gerät behält sein eigenes Hochkant-Feld, vom Gegner
      nur eine kleine Vorschau — die Daten sind winzig (Feld + Teil),
      keine Snapshots nötig. Gleicher Zufalls-Seed → beide bekommen
      dieselben Teile (fair).
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
