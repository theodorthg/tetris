class_name Main
extends Node2D

## Round coordinator: score / level / lines / fall speed, the game state machine,
## the responsive layout, and routing keyboard + mouse + gamepad + touch input
## to the playfield and menus (ui.gd).

enum State { START, PLAYING, PAUSED, OVER }

const BASE := Vector2(480, 640)      ## content_scale base; the real area is read at runtime
const PREVIEW_CELL := 12
const HUD_H := 112.0                 ## top band that holds score / buttons / previews
const HUD_BTN := 64.0                ## HUD icon-button hit area (glyph drawn smaller)
const MARGIN := 6.0
const MIN_CELL := 14
const MAX_CELL := 60

const DAS := 0.16
const ARR := 0.03
const LINE_SCORE := [0, 100, 300, 500, 800]

# --- touch tuning ---
const TAP_MAX_MOVE := 18.0     ## a touch that moves less than this (px) is a tap
const TAP_MAX_TIME := 0.25     ## …and lasts less than this (s)
const DOUBLE_TAP_TIME := 0.26  ## second tap within this window = double tap
const DOUBLE_TAP_DIST := 60.0
## true  -> single tap drops, double tap rotates (the user's stated preference)
## false -> single tap rotates, double tap drops
const TAP_DROPS := true

var _state: int = State.START
var _score := 0
var _lines := 0
var _level := 1
var _start_level := 1

var _field: Playfield
var _ui: Ui
var _score_label: Label
var _level_label: Label
var _lines_label: Label
var _pause_btn: PauseButton
var _hold_btn: HoldButton

var _hold_box := Rect2()
var _next_box := Rect2()

var _das_dir := 0
var _das_time := 0.0
var _arr_time := 0.0
var _mouse_control := true
var _mouse_active := false
var _last_mouse_pos := Vector2.ZERO

var _touch_mode := false
var _touch_id := -1
var _touch_start := Vector2.ZERO
var _touch_time := 0.0
var _touch_axis := 0           ## 0 undecided, 1 horizontal, 2 vertical
var _touch_is_tap := true
var _touch_soft_drop := false
## Abstract 0..COLS-1 aim column for touch — decoupled from the piece footprint
## so a wide horizontal I can still be aimed at column 0 / 9 for a vertical drop.
var _touch_col := 4
var _touch_start_col := 4
var _last_tap_time := -1.0
var _last_tap_pos := Vector2.ZERO
var _pending_drop := false
var _pending_drop_t := 0.0


func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_build()
	_state = State.START
	_ui.show_splash()
	if _detect_touch():
		_enter_touch_mode()
	_layout()
	get_viewport().size_changed.connect(_layout)


# --- responsive layout ------------------------------------------------

## Safe-area insets (design units): keep the HUD clear of a notch / selfie
## camera / status bar / gesture bar. Falls back to a small fixed pad.
func _safe_insets() -> Dictionary:
	var vp := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var top := 8.0
	var bottom := 6.0
	var left := 0.0
	var right := 0.0
	if win.x > 0 and win.y > 0:
		var to_design := vp.x / win.x            # uniform under ASPECT_EXPAND
		var safe := DisplayServer.get_display_safe_area()
		top = maxf(top, float(safe.position.y) * to_design)
		bottom = maxf(bottom, float(win.y - safe.end.y) * to_design)
		left = maxf(left, float(safe.position.x) * to_design)
		right = maxf(right, float(win.x - safe.end.x) * to_design)
	if _touch_mode:
		top = maxf(top, 16.0)               # clear the top-edge gesture / pull-down
		bottom = maxf(bottom, 12.0)
	return {"top": top, "bottom": bottom, "left": left, "right": right}


func _layout() -> void:
	if _field == null:
		return
	var vp := get_viewport_rect().size
	var s := _safe_insets()
	var top: float = s.top
	var bottom: float = s.bottom
	var left: float = s.left
	var right: float = s.right
	var area_x := left + MARGIN
	var area_w := vp.x - left - right - 2.0 * MARGIN
	var hud_top := top + MARGIN
	var board_top := hud_top + HUD_H

	var bh := vp.y - board_top - bottom - MARGIN
	var cell := int(clampf(floorf(minf(area_w / Playfield.COLS, bh / Playfield.ROWS)), MIN_CELL, MAX_CELL))
	_field.cell = cell
	var board_w := cell * Playfield.COLS
	var board_h := cell * Playfield.ROWS
	var wx := roundf(left + (vp.x - left - right - board_w) * 0.5)
	var wy := roundf(board_top + maxf(0.0, vp.y - board_top - bottom - board_h) * 0.42)
	_field.position = Vector2(wx, wy)
	_field.queue_redraw()

	# HUD band: hug the board (so a wide window doesn't fling the buttons to the
	# screen edges), but never narrower than needed for the text, and clamped
	# on-screen. Sits just above the board — moved down with it when the board is
	# vertically centred on a wide screen.
	var hud_w := clampf(maxf(board_w, 300.0), 0.0, area_w)
	var hud_x := clampf(wx + board_w * 0.5 - hud_w * 0.5, area_x, area_x + area_w - hud_w)
	var hud_y := maxf(hud_top, wy - HUD_H)
	var pb := HUD_BTN
	_hold_btn.size = Vector2(pb, pb)
	_hold_btn.position = Vector2(hud_x - 4, hud_y)
	_pause_btn.size = Vector2(pb, pb)
	_pause_btn.position = Vector2(hud_x + hud_w - pb + 4, hud_y)
	var sx := hud_x + hud_w * 0.5
	_score_label.position = Vector2(sx - 150, hud_y + 4)
	_score_label.size = Vector2(300, 36)
	_level_label.position = Vector2(sx - 148, hud_y + 46)
	_level_label.size = Vector2(140, 20)
	_lines_label.position = Vector2(sx + 8, hud_y + 46)
	_lines_label.size = Vector2(140, 20)
	_hold_box = Rect2(hud_x + (pb - 52) * 0.5, hud_y + pb - 2, 52, 40)
	_next_box = Rect2(hud_x + hud_w - pb + (pb - 52) * 0.5, hud_y + pb - 2, 52, 40)
	queue_redraw()


func _build() -> void:
	_field = Playfield.new()
	add_child(_field)
	_field.lines_cleared.connect(_on_lines_cleared)
	_field.hard_dropped.connect(func(rows): _add_score(rows * 2))
	_field.soft_drop_cell.connect(func(): _add_score(1))
	_field.topped_out.connect(_on_top_out)
	_field.next_changed.connect(func(_q): queue_redraw())
	_field.hold_changed.connect(func(_t): queue_redraw())
	_field.piece_spawned.connect(_on_piece_spawned)

	_score_label = _mk_label(27)
	add_child(_score_label)
	_level_label = _mk_label(15)
	add_child(_level_label)
	_lines_label = _mk_label(15)
	add_child(_lines_label)

	_pause_btn = PauseButton.new()
	_pause_btn.tapped.connect(func(): _pause())
	add_child(_pause_btn)
	_hold_btn = HoldButton.new()
	_hold_btn.tapped.connect(func(): _field.hold())
	add_child(_hold_btn)
	_pause_btn.visible = false
	_hold_btn.visible = false

	_ui = Ui.new()
	add_child(_ui)
	_ui.play_pressed.connect(_start_game)
	_ui.resume_pressed.connect(_resume)
	_ui.restart_pressed.connect(_on_restart)
	_ui.quit_pressed.connect(func(): get_tree().quit())
	_ui.settings_changed.connect(_on_settings_changed)

	_update_hud()


func _mk_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hud_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var a: float = {"normal": 0.16, "hover": 0.24, "pressed": 0.34}[state]
		sb.bg_color = Color(0.30, 0.42, 0.62, a)
		sb.set_corner_radius_all(7)
		b.add_theme_stylebox_override(state, sb)
	add_child(b)
	b.pressed.connect(on_press)
	return b


# --- touch detection (device-independent, like pacman) ----------------

static var _touch_checked := false
static var _touch_result := false


func _detect_touch() -> bool:
	if not _touch_checked:
		_touch_checked = true
		_touch_result = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	return _touch_result


func _enter_touch_mode() -> void:
	if _touch_mode:
		return
	_touch_mode = true
	_mouse_control = false
	_mouse_active = false


# --- state --------------------------------------------------------------

func _hud_buttons(vis: bool) -> void:
	_pause_btn.visible = vis
	_hold_btn.visible = vis


func _start_game() -> void:
	_start_level = int(_ui.settings.start_level)
	_field.ghost_enabled = bool(_ui.settings.ghost)
	_score = 0
	_lines = 0
	_level = _start_level
	_state = State.PLAYING
	_mouse_active = false
	_touch_id = -1
	_pending_drop = false
	_ui.hide_all()
	_hud_buttons(true)
	_field.fall_interval = _fall_interval_for(_level)
	_field.start()
	_update_hud()
	queue_redraw()


func _on_top_out() -> void:
	_state = State.OVER
	_field.stop()
	_field.clear_suggestion()
	_pending_drop = false
	_hud_buttons(false)
	_ui.show_game_over({"score": _score, "lines": _lines, "level": _level})
	queue_redraw()


func _pause() -> void:
	if _state != State.PLAYING:
		return
	_state = State.PAUSED
	_field.set_process(false)
	_field.clear_suggestion()
	_mouse_active = false
	_touch_id = -1
	_pending_drop = false
	_hud_buttons(false)
	_ui.show_pause()
	queue_redraw()


func _on_restart() -> void:
	_state = State.START
	_field.stop()
	_field.clear_suggestion()
	_hud_buttons(false)
	_pending_drop = false
	_ui.show_splash(true)   # show the loading screen again, then start


func _resume() -> void:
	if _state != State.PAUSED:
		return
	_state = State.PLAYING
	_ui.hide_all()
	_hud_buttons(true)
	_field.set_process(true)
	queue_redraw()


func _on_settings_changed(cfg: Dictionary) -> void:
	_field.ghost_enabled = bool(cfg.get("ghost", true))
	if _state != State.PLAYING:
		_start_level = int(cfg.get("start_level", 1))


# --- scoring -----------------------------------------------------------

func _on_lines_cleared(rows: int) -> void:
	_add_score(LINE_SCORE[clampi(rows, 0, 4)] * _level)
	_lines += rows
	var new_level: int = _start_level + int(_lines / 10.0)
	if new_level != _level:
		_level = new_level
		_field.fall_interval = _fall_interval_for(_level)
	_update_hud()


func _add_score(pts: int) -> void:
	_score += pts
	_update_hud()


func _fall_interval_for(level: int) -> float:
	var l := clampi(level, 1, 20)
	return maxf(pow(0.8 - (l - 1) * 0.007, l - 1), 0.016)


func _update_hud() -> void:
	_score_label.text = "%d" % _score
	_level_label.text = "LEVEL  %d" % _level
	_lines_label.text = "LINES  %d" % _lines


# --- input -------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch or e is InputEventScreenDrag) and not _touch_mode:
		_enter_touch_mode()

	if e.is_action_pressed("pause_game"):
		if _state == State.PLAYING:
			_pause()
		elif _ui.is_open():
			_ui.handle_back()
		get_viewport().set_input_as_handled()
		return

	if _state != State.PLAYING:
		return

	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		_handle_touch(e)
		return

	if e.is_action_pressed("rotate_cw"):
		_use_keyboard()
		_field.rotate_piece(1)
	elif e.is_action_pressed("rotate_ccw"):
		_use_keyboard()
		_field.rotate_piece(-1)
	elif e.is_action_pressed("hard_drop"):
		_field.hard_drop()
	elif e.is_action_pressed("hold_piece"):
		_field.hold()
	elif e is InputEventMouseButton and e.pressed and not _touch_mode:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				_field.hard_drop()
			MOUSE_BUTTON_RIGHT:
				_field.hold()
			MOUSE_BUTTON_WHEEL_UP:
				_mouse_active = true
				_field.cycle_rot_lock(1)
				_mouse_update(_last_mouse_pos)
			MOUSE_BUTTON_WHEEL_DOWN:
				_mouse_active = true
				_field.cycle_rot_lock(-1)
				_mouse_update(_last_mouse_pos)
	elif e is InputEventMouseMotion and _mouse_control and not _touch_mode:
		_mouse_active = true
		_last_mouse_pos = e.position
		_mouse_update(e.position)


func _use_keyboard() -> void:
	_mouse_active = false
	_field.clear_suggestion()


# --- touch scheme ----------------------------------------------------
#
# Swipe left/right to slide the piece (one cell per ~0.8 cell of travel); the
# ghost auto-fits the best rotation for that column, exactly like the mouse.
# A single tap and a double tap map to "drop" / "rotate" (see TAP_DROPS).
# A held downward drag is an optional soft drop.

func _swipe_px() -> float:
	return maxf(_field.cell * 0.8, 14.0)


func _on_piece_spawned() -> void:
	if _touch_mode:
		_touch_col = clampi(_field.piece_left_col() + int(_field.piece_width() / 2.0), 0, Playfield.COLS - 1)
		_touch_refresh_suggest()
	elif _mouse_active:
		_mouse_update(_last_mouse_pos)


func _touch_refresh_suggest() -> void:
	if _field.piece_left_col() < 0:
		_field.set_suggestion({})
		return
	_field.aim(float(_touch_col))


func _handle_touch(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if _touch_id < 0:
				_touch_id = e.index
				_touch_start = e.position
				_touch_time = 0.0
				_touch_axis = 0
				_touch_start_col = _touch_col
				_touch_is_tap = true
				_touch_soft_drop = false
		elif e.index == _touch_id:
			_touch_soft_drop = false
			var moved: float = (e.position - _touch_start).length()
			if _touch_is_tap and moved < TAP_MAX_MOVE and _touch_time < TAP_MAX_TIME:
				_register_tap(e.position)
			_touch_id = -1
	elif e is InputEventScreenDrag and e.index == _touch_id:
		var d: Vector2 = e.position - _touch_start
		if d.length() > TAP_MAX_MOVE:
			_touch_is_tap = false
		if _touch_axis == 0:
			if absf(d.x) > 12.0 and absf(d.x) >= absf(d.y):
				_touch_axis = 1
			elif absf(d.y) > 16.0 and absf(d.y) > absf(d.x):
				_touch_axis = 2
		if _touch_axis == 1:
			var want := int(d.x / _swipe_px())
			var new_col := clampi(_touch_start_col + want, 0, Playfield.COLS - 1)
			if new_col != _touch_col:
				_touch_col = new_col
				_touch_refresh_suggest()
			_touch_soft_drop = false
		elif _touch_axis == 2:
			_touch_soft_drop = d.y > 14.0


func _register_tap(pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var is_double := (now - _last_tap_time) < DOUBLE_TAP_TIME \
		and pos.distance_to(_last_tap_pos) < DOUBLE_TAP_DIST
	if is_double:
		_last_tap_time = -1.0
		_pending_drop = false
		if TAP_DROPS:
			_field.cycle_rot_lock(1)
			_touch_refresh_suggest()
		else:
			_field.hard_drop()
	else:
		_last_tap_time = now
		_last_tap_pos = pos
		if TAP_DROPS:
			_pending_drop = true
			_pending_drop_t = DOUBLE_TAP_TIME
		else:
			_field.cycle_rot_lock(1)
			_touch_refresh_suggest()


func _mouse_update(screen_pos: Vector2) -> void:
	if _field.piece_left_col() < 0:
		return
	var col := (screen_pos.x - _field.position.x) / float(_field.cell) - 0.5
	_field.aim(col)


func _process(dt: float) -> void:
	if _state != State.PLAYING:
		return
	if _touch_id >= 0:
		_touch_time += dt
	if _pending_drop:
		_pending_drop_t -= dt
		if _pending_drop_t <= 0.0:
			_pending_drop = false
			if TAP_DROPS:
				_field.hard_drop()
			else:
				_field.cycle_rot_lock(1)
				_touch_refresh_suggest()

	_field.soft_drop_active = _touch_soft_drop or Input.is_action_pressed("soft_drop")

	var dir := 0
	if Input.is_action_pressed("move_right"):
		dir += 1
	if Input.is_action_pressed("move_left"):
		dir -= 1

	if dir == 0:
		_das_dir = 0
		return

	_use_keyboard()
	if dir != _das_dir:
		_das_dir = dir
		_das_time = 0.0
		_arr_time = 0.0
		_field.move(dir)
		return
	_das_time += dt
	if _das_time >= DAS:
		_arr_time += dt
		while _arr_time >= ARR:
			_arr_time -= ARR
			if not _field.move(dir):
				break


# --- HUD previews -----------------------------------------------------

func _draw() -> void:
	_draw_preview_frame(_hold_box)
	_draw_preview_frame(_next_box)
	if _field == null:
		return
	if _field.hold_type() >= 0:
		_draw_piece_in_box(_field.hold_type(), _hold_box)
	var q := _field.queue_types()
	if q.size() > 0:
		_draw_piece_in_box(q[0], _next_box)


func _draw_preview_frame(box: Rect2) -> void:
	draw_rect(box, Color(0.06, 0.07, 0.10, 1.0))
	draw_rect(box, Color(1, 1, 1, 0.18), false, 1.0)


func _draw_piece_in_box(type: int, box: Rect2) -> void:
	var cells: Array = Pieces.CELLS[type][0]
	var minx := 99
	var maxx := -99
	var miny := 99
	var maxy := -99
	for c in cells:
		minx = mini(minx, c.x)
		maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y)
		maxy = maxi(maxy, c.y)
	var w := (maxx - minx + 1) * PREVIEW_CELL
	var h := (maxy - miny + 1) * PREVIEW_CELL
	var origin := box.position + (box.size - Vector2(w, h)) * 0.5
	var col: Color = Pieces.COLORS[type]
	for c in cells:
		var p: Vector2 = origin + Vector2((c.x - minx) * PREVIEW_CELL, (c.y - miny) * PREVIEW_CELL)
		var r := Rect2(p + Vector2(1, 1), Vector2(PREVIEW_CELL - 2, PREVIEW_CELL - 2))
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)
