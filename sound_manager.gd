extends Node

## Autoload "Snd". Owns every sound: one AudioStreamPlayer per effect plus a
## looping music track. Per-sound volume (0..100 %) is stored in
## user://settings.cfg [sound]; `base_db` calibrates each clip so 100 % is
## balanced across them (the click is deliberately the quietest). The music
## on/off switch lives in the *general* settings, not here.

const CFG_PATH := "user://settings.cfg"
const CALIB_VERSION := 3   ## bump to re-apply the reference defaults below

## key -> { name, file, def (reference %), base_db (calibration so `def` is balanced) }
## music base_db is pulled ~8 dB lower than before so the reference sits at 40 %
## with plenty of slider room left below it.
const SOUNDS := {
	"move":  {"name": "Move / click",      "file": "click-sound.ogg",       "def": 55, "base_db": -7.0},
	"drop":  {"name": "Drop / lock",       "file": "drop-sound.ogg",        "def": 85, "base_db": -1.0},
	"hold":  {"name": "Hold",              "file": "hold-sound.ogg",        "def": 85, "base_db": -3.0},
	"line1": {"name": "Line clear",        "file": "one-line-cleared.ogg",  "def": 85, "base_db": -1.0},
	"lines": {"name": "Multi-line clear",  "file": "line-cleared.ogg",      "def": 90, "base_db":  0.0},
	"over":  {"name": "Game over",         "file": "game-over-sound.ogg",    "def": 90, "base_db": -3.0},
	"music": {"name": "Music",             "file": "tetris-theme.ogg",      "def": 40, "base_db": -14.0},
}
const SFX_ORDER := ["move", "drop", "hold", "line1", "lines", "over", "music"]

var _vol: Dictionary = {}          ## key -> int 0..100
var _players: Dictionary = {}      ## key -> AudioStreamPlayer
var _music_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/sounds/" + SOUNDS[key].file)
		if key == "music":
			var s := p.stream
			if s is AudioStreamOggVorbis or s is AudioStreamMP3:
				s.loop = true
		add_child(p)
		_players[key] = p
	_load()


# --- public ---------------------------------------------------------

func play(key: String) -> void:
	var p: AudioStreamPlayer = _players.get(key)
	if p == null:
		return
	var v: int = _vol.get(key, 0)
	if v <= 0:
		return
	p.volume_db = _db_for(key, v)
	p.play()


func set_volume(key: String, pct: int) -> void:
	_vol[key] = clampi(pct, 0, 100)
	if key == "music":
		_apply_music()
	_save()


func get_volume(key: String) -> int:
	return int(_vol.get(key, SOUNDS.get(key, {}).get("def", 0)))


func set_music_enabled(on: bool) -> void:
	_music_on = on
	_apply_music()


func is_music_enabled() -> bool:
	return _music_on


func stop_all() -> void:
	for p in _players.values():
		p.stop()


# --- internals -----------------------------------------------------

func _db_for(key: String, pct: int) -> float:
	var base: float = SOUNDS.get(key, {}).get("base_db", 0.0)
	return base + linear_to_db(clampf(float(pct) / 100.0, 0.0001, 1.0))


func _apply_music() -> void:
	var p: AudioStreamPlayer = _players.get("music")
	if p == null:
		return
	var want: bool = _music_on and _vol.get("music", 0) > 0
	if want:
		p.volume_db = _db_for("music", _vol.music)
		if not p.playing:
			p.play()
	else:
		p.stop()


func _load() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	var calib := int(cf.get_value("sound", "calib_version", 0))
	for key in SOUNDS:
		var d: int = SOUNDS[key].def
		if calib == CALIB_VERSION:
			_vol[key] = clampi(int(cf.get_value("sound", key, d)), 0, 100)
		else:
			_vol[key] = d
	# a calib bump also re-asserts the music default (on)
	if calib == CALIB_VERSION:
		_music_on = bool(cf.get_value("game", "music", true))
	else:
		_music_on = true
		var g := ConfigFile.new()
		g.load(CFG_PATH)
		g.set_value("game", "music", true)
		g.save(CFG_PATH)
	_apply_music()
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("sound", "calib_version", CALIB_VERSION)
	for key in SOUNDS:
		cf.set_value("sound", key, int(_vol.get(key, SOUNDS[key].def)))
	cf.save(CFG_PATH)
