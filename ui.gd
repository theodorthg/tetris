class_name Ui
extends CanvasLayer

## All front-of-game screens, built in code on one CanvasLayer:
##   start · pause · settings (+ sound sub-page) · how-to-play · game over / hall of fame
## main.gd drives it via show_*(), and listens to the signals below.
## Settings persist to user://settings.cfg, the hall of fame to user://hall_of_fame.cfg.

signal play_pressed
signal resume_pressed
signal restart_pressed
signal quit_pressed
signal settings_changed(cfg: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"
const HOF_PATH := "user://hall_of_fame.cfg"
const HOF_MAX := 10

enum Screen { NONE, SPLASH, START, PAUSE, SETTINGS, SOUND, HELP, GAMEOVER }

const SPLASH_TIME := 2.6

var settings := {
	"start_level": 1,
	"ghost": true,
}

var _screen: int = Screen.NONE
var _return_to: int = Screen.START     ## where "Back" goes from settings/help
var _hof: Array = []                    ## [{name,score,lines,level}], score-desc
var _pending: Dictionary = {}           ## last run's result while on the game-over screen

var _bg: TextureRect
var _scrim: ColorRect
var _root: MarginContainer
var _box: VBoxContainer
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _splash_bar: ProgressBar
var _splash_tween: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_load_hof()

	_bg = TextureRect.new()
	_bg.texture = load("res://splash-screen.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0.6, 0.6, 0.66)
	add_child(_bg)

	_scrim = ColorRect.new()
	_scrim.color = Color(0.035, 0.045, 0.065, 0.74)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("margin_left", 30)
	_root.add_theme_constant_override("margin_right", 30)
	_root.add_theme_constant_override("margin_top", 40)
	_root.add_theme_constant_override("margin_bottom", 40)
	add_child(_root)

	var center := CenterContainer.new()
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	_panel_style.border_color = Color(1, 1, 1, 0.10)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(10)
	_panel_style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", _panel_style)
	center.add_child(_panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.custom_minimum_size = Vector2(372, 0)
	_panel.add_child(_box)

	hide_all()


# --- public API --------------------------------------------------------

func hide_all() -> void:
	_screen = Screen.NONE
	visible = false


func show_splash() -> void:
	_screen = Screen.SPLASH
	visible = true
	_clear_box()
	_bg.visible = true
	_bg.modulate = Color(1, 1, 1)
	_scrim.color = Color(0.03, 0.04, 0.06, 0.28)
	_panel_style.bg_color = Color(0, 0, 0, 0)          # no panel box on the splash
	_panel_style.border_color = Color(0, 0, 0, 0)

	_gap(360)
	var loading := Label.new()
	loading.text = "Loading…"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 15)
	loading.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_box.add_child(loading)
	_splash_bar = ProgressBar.new()
	_splash_bar.custom_minimum_size = Vector2(300, 8)
	_splash_bar.min_value = 0
	_splash_bar.max_value = 100
	_splash_bar.value = 0
	_splash_bar.show_percentage = false
	_box.add_child(_splash_bar)

	_splash_tween = create_tween()
	_splash_tween.tween_property(_splash_bar, "value", 100.0, SPLASH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_splash_tween.tween_callback(show_start)


func _finish_splash() -> void:
	if _screen != Screen.SPLASH:
		return
	if _splash_tween and _splash_tween.is_valid():
		_splash_tween.kill()
	show_start()


func _unhandled_input(event: InputEvent) -> void:
	if _screen == Screen.SPLASH:
		var go: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
		if go:
			_finish_splash()
			get_viewport().set_input_as_handled()


func show_start() -> void:
	_screen = Screen.START
	_return_to = Screen.START
	_scrim.color = Color(0.035, 0.045, 0.065, 0.74)
	_build()


func show_pause() -> void:
	_screen = Screen.PAUSE
	_return_to = Screen.PAUSE
	_build()


func show_help(from: int = Screen.START) -> void:
	_return_to = from
	_screen = Screen.HELP
	_build()


func show_settings(from: int = Screen.START) -> void:
	_return_to = from
	_screen = Screen.SETTINGS
	_build()


func show_game_over(result: Dictionary) -> void:
	_pending = result
	if _qualifies(int(result.get("score", 0))):
		_screen = Screen.GAMEOVER
		_build_name_entry()
	else:
		_screen = Screen.GAMEOVER
		_build()


func is_open() -> bool:
	return visible


## Esc / pause key while a screen is up. Returns true if it was consumed.
func handle_back() -> bool:
	match _screen:
		Screen.SETTINGS, Screen.HELP:
			_screen = _return_to
			_build()
			return true
		Screen.SOUND:
			_screen = Screen.SETTINGS
			_build()
			return true
		Screen.PAUSE:
			resume_pressed.emit()
			return true
	return false


# --- screen construction ---------------------------------------------

func _clear_box() -> void:
	for c in _box.get_children():
		c.queue_free()


func _build() -> void:
	visible = true
	_clear_box()
	var splash_screens := [Screen.START, Screen.GAMEOVER]
	_bg.visible = _screen in splash_screens
	_bg.modulate = Color(0.6, 0.6, 0.66)
	_scrim.color = Color(0.035, 0.045, 0.065, 0.74)
	_panel_style.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	_panel_style.border_color = Color(1, 1, 1, 0.10)

	match _screen:
		Screen.START:
			_title("TETRIS", 52)
			_gap(10)
			_button("Play", play_pressed.emit)
			_button("How to Play", func(): show_help(Screen.START))
			_button("Settings", func(): show_settings(Screen.START))
			_exit_button()
		Screen.PAUSE:
			_title("PAUSED", 40)
			_gap(6)
			_button("Resume", resume_pressed.emit)
			_button("Settings", func(): show_settings(Screen.PAUSE))
			_button("How to Play", func(): show_help(Screen.PAUSE))
			_button("Restart", restart_pressed.emit)
			_exit_button()
		Screen.HELP:
			_help_screen()
		Screen.SETTINGS:
			_settings_screen()
		Screen.SOUND:
			_sound_screen()
		Screen.GAMEOVER:
			_game_over_screen()


func _game_over_screen() -> void:
	_title("GAME OVER", 38)
	var r := _pending
	_label("Score  %d      Lines  %d      Level  %d" %
		[int(r.get("score", 0)), int(r.get("lines", 0)), int(r.get("level", 1))], 16)
	_gap(6)
	_hall_of_fame_list(int(r.get("score", 0)))
	_gap(10)
	_button("Play Again", restart_pressed.emit)
	_exit_button()


func _build_name_entry() -> void:
	visible = true
	_clear_box()
	_bg.visible = true
	_bg.modulate = Color(0.6, 0.6, 0.66)
	_scrim.color = Color(0.035, 0.045, 0.065, 0.74)
	_panel_style.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	_panel_style.border_color = Color(1, 1, 1, 0.10)
	_title("NEW HIGH SCORE!", 30)
	_label("Score  %d" % int(_pending.get("score", 0)), 18)
	_gap(8)
	var edit := LineEdit.new()
	edit.max_length = 12
	edit.placeholder_text = "Your name"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 20)
	_box.add_child(edit)
	edit.text_submitted.connect(func(_t): _commit_name(edit.text))
	_button("OK", func(): _commit_name(edit.text))
	edit.call_deferred("grab_focus")


func _commit_name(name: String) -> void:
	var clean := name.strip_edges()
	if clean.is_empty():
		clean = "PLAYER"
	_insert_hof({
		"name": clean.to_upper().substr(0, 12),
		"score": int(_pending.get("score", 0)),
		"lines": int(_pending.get("lines", 0)),
		"level": int(_pending.get("level", 1)),
	})
	_save_hof()
	_screen = Screen.GAMEOVER
	_build()


func _help_screen() -> void:
	_title("How to Play", 30)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(372, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.custom_minimum_size = Vector2(360, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = _help_text()
	scroll.add_child(body)
	_gap(6)
	_button("Back", func(): handle_back())


func _help_text() -> String:
	# Placeholder — final wording is written once the game is done.
	return "Clear lines by filling every cell in a row.\n\n" \
		+ "Keyboard:\n" \
		+ "  Move: Arrows or A / D\n" \
		+ "  Rotate: Up / X (cw), Z (ccw)\n" \
		+ "  Soft drop: Down / S\n" \
		+ "  Hard drop: Space\n" \
		+ "  Hold: C / End\n" \
		+ "  Pause: Esc / P\n\n" \
		+ "Mouse:\n" \
		+ "  Move left/right to aim the column; the ghost shows the best fit.\n" \
		+ "  Wheel: force a rotation. Left-click: hard drop. Right-click: hold.\n\n" \
		+ "(This text is a placeholder and will be finalised later.)"


func _settings_screen() -> void:
	_title("Settings", 30)
	_gap(4)

	# Start level 1..15
	var lvl_row := _row("Start level")
	var lvl := SpinBox.new()
	lvl.min_value = 1
	lvl.max_value = 15
	lvl.value = int(settings.start_level)
	lvl.custom_minimum_size = Vector2(96, 40)
	lvl_row.add_child(lvl)
	lvl.value_changed.connect(func(v):
		settings.start_level = int(v)
		_apply_settings())

	# Ghost piece on/off
	var ghost_row := _row("Ghost piece")
	var ghost := CheckButton.new()
	ghost.button_pressed = bool(settings.ghost)
	ghost_row.add_child(ghost)
	ghost.toggled.connect(func(on):
		settings.ghost = on
		_apply_settings())

	_gap(10)
	_button("Sound", func():
		_screen = Screen.SOUND
		_build())
	_button("Back", func(): handle_back())


func _sound_screen() -> void:
	_title("Sound", 30)
	_gap(4)
	_label("No sounds yet — this screen will get a master volume and a\nper-sound slider once the game has audio.", 14)
	_gap(12)
	_button("Back", func():
		_screen = Screen.SETTINGS
		_build())


# --- small widget helpers -------------------------------------------

func _title(text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	_box.add_child(l)


func _label(text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	_box.add_child(l)


func _gap(h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	_box.add_child(s)


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var shades := {"normal": 0.16, "hover": 0.24, "pressed": 0.12, "focus": 0.20}
		sb.bg_color = Color(0.30, 0.42, 0.62, shades[state])
		sb.set_corner_radius_all(7)
		sb.set_content_margin_all(8)
		if state == "focus" or state == "hover":
			sb.border_color = Color(0.6, 0.75, 1.0, 0.5)
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override(state, sb)
	_box.add_child(b)
	b.pressed.connect(on_press)
	return b


func _exit_button() -> void:
	if OS.has_feature("web"):
		return   # a browser tab cannot close itself
	_button("Exit", quit_pressed.emit)


func _row(caption: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size = Vector2(0, 44)
	var l := Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", 17)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	_box.add_child(h)
	return h


func _hall_of_fame_list(highlight_score: int) -> void:
	_label("— Hall of Fame —", 16)
	if _hof.is_empty():
		_label("(no scores yet)", 13)
		return
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	_box.add_child(grid)
	var highlighted := false
	for i in _hof.size():
		var e: Dictionary = _hof[i]
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 15)
		row.text = "%2d.  %-12s  %7d" % [i + 1, str(e.get("name", "?")), int(e.get("score", 0))]
		if not highlighted and int(e.get("score", 0)) == highlight_score:
			row.add_theme_color_override("font_color", Color("f0c02a"))
			highlighted = true
		grid.add_child(row)


# --- persistence -----------------------------------------------------

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		settings.start_level = clampi(int(cf.get_value("game", "start_level", 1)), 1, 15)
		settings.ghost = bool(cf.get_value("game", "ghost", true))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)   # keep any [sound] section
	cf.set_value("game", "start_level", int(settings.start_level))
	cf.set_value("game", "ghost", bool(settings.ghost))
	cf.save(SETTINGS_PATH)


func _apply_settings() -> void:
	_save_settings()
	settings_changed.emit(settings.duplicate())


func _load_hof() -> void:
	_hof.clear()
	var cf := ConfigFile.new()
	if cf.load(HOF_PATH) == OK:
		var raw = cf.get_value("hof", "entries", [])
		if raw is Array:
			for e in raw:
				if e is Dictionary:
					_hof.append(e)
	_sort_hof()


func _save_hof() -> void:
	var cf := ConfigFile.new()
	cf.set_value("hof", "entries", _hof)
	cf.save(HOF_PATH)


func _sort_hof() -> void:
	_hof.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	if _hof.size() > HOF_MAX:
		_hof.resize(HOF_MAX)


func _qualifies(score: int) -> bool:
	if score <= 0:
		return false
	if _hof.size() < HOF_MAX:
		return true
	return score > int(_hof[_hof.size() - 1].get("score", 0))


func _insert_hof(entry: Dictionary) -> void:
	_hof.append(entry)
	_sort_hof()
