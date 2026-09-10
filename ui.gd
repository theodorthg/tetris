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

## the "Snd" autoload — via preload for its consts, via /root for its methods
## (autoload identifiers aren't visible when the project runs under --script)
const SoundManager := preload("res://sound_manager.gd")


func _snd() -> Node:
	return get_node_or_null(^"/root/Snd")

enum Screen { NONE, SPLASH, START, PAUSE, SETTINGS, SOUND, CONTROLS, HELP, GAMEOVER }

## Remappable keyboard actions — display name + default physical keycode.
## Saved overrides live in user://settings.cfg [keys]; the gamepad bindings
## from project.godot are left untouched.
const KEY_ACTIONS := [
	["move_left",  "Move left",   KEY_LEFT],
	["move_right", "Move right",  KEY_RIGHT],
	["soft_drop",  "Soft drop",   KEY_DOWN],
	["hard_drop",  "Hard drop",   KEY_SPACE],
	["rotate_cw",  "Rotate right", KEY_UP],
	["rotate_ccw", "Rotate left", KEY_Z],
	["hold_piece", "Hold",        KEY_C],
	["pause_game", "Pause",       KEY_ESCAPE],
]

const SPLASH_TIME := 2.6

## Image-based How-to-Play. Two page sets — the mouse/keyboard set on desktop,
## the touch set on a touchscreen. Page art is load()ed on demand (only the
## current page stays resident); export_filter is "all_resources" so every PNG
## is packed on every platform.
const HELP_DIR := "res://assets/graphics/help/"
const HELP_MOUSE := [
	{"file": "mouse",     "title": "Mouse controls"},
	{"file": "aim",       "title": "Aim & auto-rotate"},
	{"file": "hud",       "title": "The buttons"},
	{"file": "keyboard",  "title": "Keyboard"},
	{"file": "goal",      "title": "Goal & scoring"},
]
const HELP_TOUCH := [
	{"file": "swipe",     "title": "Swipe & tap"},
	{"file": "aim-touch", "title": "Aim & auto-rotate"},
	{"file": "hud",       "title": "The buttons"},
	{"file": "goal",      "title": "Goal & scoring"},
]
const HELP_SWIPE_MIN := 60.0

var settings := {
	"start_level": 1,
	"ghost": true,
	"music": true,
}

var _screen: int = Screen.NONE
var _return_to: int = Screen.START     ## where "Back" goes from settings/help
var _hof: Array = []                    ## [{name,score,lines,level}], score-desc
var _pending: Dictionary = {}           ## last run's result while on the game-over screen

var _bg: TextureRect
var _backdrop: ColorRect
var _scrim: ColorRect
var _root: MarginContainer
var _box: VBoxContainer
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _splash_bar: ProgressBar
var _splash_tween: Tween

var _help_touch := false
var _help_page := 0
var _help_overlay: Control
var _help_tex: TextureRect
var _help_ph: Label
var _help_dots: HBoxContainer
var _help_swipe_id := -1
var _help_swipe_x := 0.0

var _capturing := ""     ## action currently waiting for a key press, or ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_load_hof()
	_apply_keys()

	# black backdrop so the artwork can be shown whole (letterboxed) on it;
	# only visible on the screens that show the artwork (start / gameover / splash)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.03, 0.035, 0.05, 1.0)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_bg = TextureRect.new()
	_bg.texture = load("res://splash-screen.png")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0.6, 0.6, 0.66)
	add_child(_bg)

	_scrim = ColorRect.new()
	_scrim.color = Color(0.035, 0.045, 0.065, 0.74)
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_scrim)

	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("margin_left", 14)
	_root.add_theme_constant_override("margin_right", 14)
	_root.add_theme_constant_override("margin_top", 30)
	_root.add_theme_constant_override("margin_bottom", 30)
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
	_box.custom_minimum_size = Vector2(360, 0)
	_panel.add_child(_box)

	hide_all()


# --- public API --------------------------------------------------------

func hide_all() -> void:
	_screen = Screen.NONE
	visible = false
	if _help_overlay:
		_help_overlay.queue_free()
		_help_overlay = null
	_help_swipe_id = -1


var _splash_overlay: Control
var _splash_then_play := false


func show_splash(then_play := false) -> void:
	_screen = Screen.SPLASH
	_splash_then_play = then_play
	visible = true
	_clear_box()
	_panel.visible = false
	_bg.visible = true
	_backdrop.visible = true
	_bg.modulate = Color(1, 1, 1)
	_scrim.color = Color(0.03, 0.04, 0.06, 0.18)

	if _splash_overlay:
		_splash_overlay.queue_free()
	var vp := get_viewport().get_visible_rect().size
	_splash_overlay = Control.new()
	_splash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_splash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_splash_overlay)

	var w := 260.0
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.size = Vector2(w, 48)
	stack.position = Vector2((vp.x - w) * 0.5, vp.y - 104)
	_splash_overlay.add_child(stack)

	var loading := Label.new()
	loading.text = "Loading…"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 16)
	loading.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	stack.add_child(loading)
	_splash_bar = ProgressBar.new()
	_splash_bar.custom_minimum_size = Vector2(w, 8)
	_splash_bar.min_value = 0
	_splash_bar.max_value = 100
	_splash_bar.value = 0
	_splash_bar.show_percentage = false
	stack.add_child(_splash_bar)

	_splash_tween = create_tween()
	_splash_tween.tween_property(_splash_bar, "value", 100.0, SPLASH_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_splash_tween.tween_callback(_end_splash)


func _end_splash() -> void:
	if _splash_overlay:
		_splash_overlay.queue_free()
		_splash_overlay = null
	if _splash_then_play:
		_splash_then_play = false
		play_pressed.emit()
	else:
		show_start()


func _finish_splash() -> void:
	if _screen != Screen.SPLASH:
		return
	if _splash_tween and _splash_tween.is_valid():
		_splash_tween.kill()
	_end_splash()


func _unhandled_input(event: InputEvent) -> void:
	if _screen == Screen.SPLASH:
		var go: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
		if go:
			_finish_splash()
			get_viewport().set_input_as_handled()
		return

	if _screen == Screen.HELP:
		_help_input(event)

	if _capturing != "" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var kc: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if kc != KEY_ESCAPE:                       # Esc cancels the capture
			_rebind(_capturing, kc)
			_save_key(_capturing, kc)
		_capturing = ""
		_build()


func _help_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_help_go(-1); get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_help_go(1); get_viewport().set_input_as_handled()
			KEY_SPACE, KEY_ESCAPE:
				_help_close(); get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				_help_go(1); get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				_help_go(-1); get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_help_swipe_id = event.index
			_help_swipe_x = event.position.x
		elif event.index == _help_swipe_id:
			_help_swipe_id = -1
			var dx: float = event.position.x - _help_swipe_x
			if absf(dx) > HELP_SWIPE_MIN:
				_help_go(-1 if dx > 0.0 else 1)   # swipe right -> previous page
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
	_help_page = 0
	visible = true
	_clear_box()
	_panel.visible = false
	_bg.visible = false
	_backdrop.visible = true
	_backdrop.color = Color(0.05, 0.06, 0.09, 1.0)
	_scrim.visible = false
	if _splash_overlay:
		_splash_overlay.queue_free()
		_splash_overlay = null
	# drop focus from whatever button opened this, so the arrow keys reach
	# _unhandled_input instead of being eaten as UI focus navigation
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	_build_help_overlay()
	_help_go(0)


## main.gd calls this so the right page set (mouse vs touch) is shown.
func set_help_context(touch: bool) -> void:
	_help_touch = touch


func _help_pages() -> Array:
	return HELP_TOUCH if _help_touch else HELP_MOUSE


func _build_help_overlay() -> void:
	if _help_overlay:
		_help_overlay.queue_free()
	_help_overlay = Control.new()
	_help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE so the mouse wheel reaches _unhandled_input; the nav buttons keep
	# their own hit test, and stray clicks fall through to a non-playing main.gd.
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help_overlay)

	_help_tex = TextureRect.new()
	_help_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_tex.offset_left = 10
	_help_tex.offset_right = -10
	_help_tex.offset_top = 10
	_help_tex.offset_bottom = -120
	_help_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_help_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_help_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_overlay.add_child(_help_tex)

	_help_ph = Label.new()
	_help_ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_ph.offset_bottom = -120
	_help_ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_ph.add_theme_font_size_override("font_size", 20)
	_help_ph.add_theme_color_override("font_color", Color(0.7, 0.78, 0.92))
	_help_ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_overlay.add_child(_help_ph)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -112
	bottom.offset_bottom = -14
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_overlay.add_child(bottom)

	_help_dots = HBoxContainer.new()
	_help_dots.add_theme_constant_override("separation", 8)
	_help_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_help_dots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_help_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_help_dots)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bar)
	var prev := _nav_button("‹", Vector2(88, 58))
	prev.pressed.connect(func(): _help_go(-1))
	var done := _nav_button("Done", Vector2(132, 58))
	done.pressed.connect(_help_close)
	var next := _nav_button("›", Vector2(88, 58))
	next.pressed.connect(func(): _help_go(1))
	bar.add_child(prev)
	bar.add_child(done)
	bar.add_child(next)


func _nav_button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 22 if text == "Done" else 30)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var a: float = {"normal": 0.18, "hover": 0.28, "pressed": 0.12}[state]
		sb.bg_color = Color(0.30, 0.42, 0.62, a)
		sb.set_corner_radius_all(8)
		if state == "hover":
			sb.border_color = Color(0.6, 0.75, 1.0, 0.5)
			sb.set_border_width_all(1)
		b.add_theme_stylebox_override(state, sb)
	return b


func _help_go(delta: int) -> void:
	var pages := _help_pages()
	if pages.is_empty():
		return
	_help_page = wrapi(_help_page + delta, 0, pages.size())
	var entry: Dictionary = pages[_help_page]
	# load() directly (not gated by ResourceLoader.exists(), which is unreliable
	# for imported resources in native exports — that hid the images on Linux /
	# Android while the web build was fine)
	var path := HELP_DIR + str(entry.get("file", "")) + ".png"
	var tex := load(path) as Texture2D
	_help_tex.texture = tex
	_help_tex.visible = tex != null
	_help_ph.visible = tex == null
	_help_ph.text = "%s\n\n( illustration coming )" % str(entry.get("title", ""))
	_refresh_help_dots()


func _refresh_help_dots() -> void:
	for c in _help_dots.get_children():
		c.queue_free()
	var n := _help_pages().size()
	for i in n:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(9, 9)
		d.color = Color(0.95, 0.80, 0.25) if i == _help_page else Color(1, 1, 1, 0.22)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_help_dots.add_child(d)


func _help_close() -> void:
	if _help_overlay:
		_help_overlay.queue_free()
		_help_overlay = null
	_help_swipe_id = -1
	_scrim.visible = true
	_screen = _return_to
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
		Screen.HELP:
			_help_close()
			return true
		Screen.SETTINGS:
			_screen = _return_to
			_build()
			return true
		Screen.SOUND:
			_screen = Screen.SETTINGS
			_build()
			return true
		Screen.CONTROLS:
			if _capturing != "":
				_capturing = ""
				_build()
			else:
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
	_panel.visible = true
	if _splash_overlay:
		_splash_overlay.queue_free()
		_splash_overlay = null
	if _help_overlay:
		_help_overlay.queue_free()
		_help_overlay = null
	var splash_screens := [Screen.START, Screen.GAMEOVER]
	_bg.visible = _screen in splash_screens
	_backdrop.visible = _bg.visible
	_bg.modulate = Color(0.6, 0.6, 0.66)
	_scrim.visible = true
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
		Screen.SETTINGS:
			_settings_screen()
		Screen.SOUND:
			_sound_screen()
		Screen.CONTROLS:
			_controls_screen()
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
	_button("How to Play", func(): show_help(Screen.GAMEOVER))
	_button("Settings", func(): show_settings(Screen.GAMEOVER))
	_exit_button()


func _build_name_entry() -> void:
	visible = true
	_clear_box()
	_panel.visible = true
	_bg.visible = true
	_backdrop.visible = true
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

	# Background music on/off (volume lives on the Sound page)
	var music_row := _row("Music")
	var music := CheckButton.new()
	music.button_pressed = bool(settings.music)
	music_row.add_child(music)
	music.toggled.connect(func(on):
		settings.music = on
		var s := _snd()
		if s:
			s.set_music_enabled(on)
		_apply_settings())

	_gap(10)
	_button("Sound", func():
		_screen = Screen.SOUND
		_build())
	_button("Controls", func():
		_screen = Screen.CONTROLS
		_build())
	_button("Back", func(): handle_back())


func _controls_screen() -> void:
	_title("Controls", 30)
	_label("Tap a key to rebind it. Esc cancels.", 13)
	_gap(4)
	for entry in KEY_ACTIONS:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.custom_minimum_size = Vector2(0, 38)
		_box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = entry[1]
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)

		var key_btn := Button.new()
		key_btn.custom_minimum_size = Vector2(140, 34)
		key_btn.focus_mode = Control.FOCUS_NONE
		key_btn.add_theme_font_size_override("font_size", 16)
		if _capturing == action:
			key_btn.text = "press a key…"
			key_btn.add_theme_color_override("font_color", Color("f0c02a"))
		else:
			key_btn.text = _key_label(action)
		row.add_child(key_btn)
		key_btn.pressed.connect(func():
			_capturing = action
			_build())

	_gap(10)
	_button("Reset to defaults", func():
		_capturing = ""
		_reset_keys())
	_button("Back", func(): handle_back())


func _key_label(action: String) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			var lbl := DisplayServer.keyboard_get_label_from_physical(kc)
			return OS.get_keycode_string(lbl if lbl != 0 else kc)
	return "—"


func _rebind(action: String, phys_keycode: int) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var ev := InputEventKey.new()
	ev.physical_keycode = phys_keycode
	InputMap.action_add_event(action, ev)


func _apply_keys() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for entry in KEY_ACTIONS:
		var kc := int(cf.get_value("keys", entry[0], 0))
		if kc != 0:
			_rebind(entry[0], kc)


func _save_key(action: String, phys_keycode: int) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("keys", action, int(phys_keycode))
	cf.save(SETTINGS_PATH)


func _reset_keys() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK and cf.has_section("keys"):
		cf.erase_section("keys")
		cf.save(SETTINGS_PATH)
	InputMap.load_from_project_settings()
	_build()


func _sound_screen() -> void:
	_title("Sound", 30)
	_gap(2)
	_label("Volume of each sound (0 turns it off).", 13)
	_gap(6)
	for key in SoundManager.SFX_ORDER:
		_sound_row(str(key), str(SoundManager.SOUNDS[key]["name"]))
	_gap(10)
	_button("Back", func():
		_screen = Screen.SETTINGS
		_build())


func _sound_row(key: String, caption: String) -> void:
	var snd := _snd()
	var cur: int = snd.get_volume(key) if snd else int(SoundManager.SOUNDS[key]["def"])
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(0, 40)
	_box.add_child(h)

	var name_lbl := Label.new()
	name_lbl.text = caption
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.custom_minimum_size = Vector2(132, 0)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_lbl)

	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = cur
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sl)

	var val_lbl := Label.new()
	val_lbl.text = "%d" % cur
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_lbl.custom_minimum_size = Vector2(34, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(val_lbl)

	sl.value_changed.connect(func(v):
		val_lbl.text = "%d" % int(v)
		if snd:
			snd.set_volume(key, int(v)))
	sl.drag_ended.connect(func(_changed):
		if snd and key != "music":
			snd.play(key))


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
		settings.music = bool(cf.get_value("game", "music", true))


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)   # keep any [sound] section
	cf.set_value("game", "start_level", int(settings.start_level))
	cf.set_value("game", "ghost", bool(settings.ghost))
	cf.set_value("game", "music", bool(settings.music))
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
