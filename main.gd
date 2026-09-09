class_name Main
extends Node2D

## Round coordinator: owns score / level / lines / fall speed and the game
## state machine, wires the playfield to the HUD and the menu screens (ui.gd),
## and routes keyboard + mouse + gamepad input to the playfield. Touch: later.

enum State { START, PLAYING, PAUSED, OVER }

const DESIGN := Vector2(480, 800)
const WELL_ORIGIN := Vector2(80, 150)
const HOLD_BOX := Rect2(10, 80, 66, 62)
const NEXT_BOX := Rect2(404, 80, 66, 62)
const PREVIEW_CELL := 14
const PAUSE_BTN := Rect2(10, 10, 88, 42)
const HOLD_BTN := Rect2(382, 10, 88, 42)

const DAS := 0.16
const ARR := 0.03
const LINE_SCORE := [0, 100, 300, 500, 800]

# touch tuning
const SWIPE_CELL := 26.0     ## horizontal drag px per one-cell move
const TAP_MAX_MOVE := 18.0   ## a touch that moved less than this is a tap (rotate)
const TAP_MAX_TIME := 0.22
const FLICK_SPEED := 1100.0  ## downward px/s that counts as a hard-drop flick

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

var _das_dir := 0
var _das_time := 0.0
var _arr_time := 0.0
var _mouse_control := true
var _mouse_active := false
var _last_mouse_pos := Vector2.ZERO

var _pause_btn: Button
var _hold_btn: Button

var _touch_mode := false
var _touch_id := -1
var _touch_start := Vector2.ZERO
var _touch_time := 0.0
var _touch_axis := 0          ## 0 undecided, 1 horizontal, 2 vertical
var _touch_moved_cells := 0
var _touch_is_tap := true
var _touch_soft_drop := false


func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_build()
	_state = State.START
	_ui.show_start()
	if _detect_touch():
		_enter_touch_mode()


func _build() -> void:
	_field = Playfield.new()
	_field.position = WELL_ORIGIN
	add_child(_field)
	_field.lines_cleared.connect(_on_lines_cleared)
	_field.hard_dropped.connect(func(rows): _add_score(rows * 2))
	_field.soft_drop_cell.connect(func(): _add_score(1))
	_field.topped_out.connect(_on_top_out)
	_field.next_changed.connect(func(_q): queue_redraw())
	_field.hold_changed.connect(func(_t): queue_redraw())

	_score_label = _mk_label(24)
	_score_label.position = Vector2(110, 12)
	_score_label.size = Vector2(260, 34)
	add_child(_score_label)
	_level_label = _mk_label(14)
	_level_label.position = Vector2(108, 50)
	_level_label.size = Vector2(130, 20)
	add_child(_level_label)
	_lines_label = _mk_label(14)
	_lines_label.position = Vector2(242, 50)
	_lines_label.size = Vector2(130, 20)
	add_child(_lines_label)

	_pause_btn = _hud_button("PAUSE", PAUSE_BTN, func(): _pause())
	_hold_btn = _hud_button("HOLD", HOLD_BTN, func(): _field.hold())
	_pause_btn.visible = false
	_hold_btn.visible = false

	_ui = Ui.new()
	add_child(_ui)
	_ui.play_pressed.connect(_start_game)
	_ui.resume_pressed.connect(_resume)
	_ui.restart_pressed.connect(_start_game)
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


func _hud_button(text: String, rect: Rect2, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
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
	if _field:
		_field.clear_suggestion()


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
	_hud_buttons(false)
	_ui.show_pause()
	queue_redraw()


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
	elif e is InputEventMouseButton and e.pressed:
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
	elif e is InputEventMouseMotion and _mouse_control:
		_mouse_active = true
		_last_mouse_pos = e.position
		_mouse_update(e.position)


func _use_keyboard() -> void:
	_mouse_active = false
	_field.clear_suggestion()


## Touch: swipe left/right to move (one cell per SWIPE_CELL px), swipe/hold
## down for soft drop, a fast downward flick for hard drop, a quick tap to
## rotate. The Pause and Hold buttons sit in the top band.
func _handle_touch(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touch_id = e.index
			_touch_start = e.position
			_touch_time = 0.0
			_touch_axis = 0
			_touch_moved_cells = 0
			_touch_is_tap = true
			_touch_soft_drop = false
		elif e.index == _touch_id:
			var moved: float = (e.position - _touch_start).length()
			if _touch_is_tap and moved < TAP_MAX_MOVE and _touch_time < TAP_MAX_TIME:
				_field.rotate_piece(1)
			_touch_id = -1
			_touch_soft_drop = false
	elif e is InputEventScreenDrag and e.index == _touch_id:
		var d: Vector2 = e.position - _touch_start
		if d.length() > TAP_MAX_MOVE:
			_touch_is_tap = false
		if _touch_axis == 0:
			if absf(d.x) > 14.0 and absf(d.x) >= absf(d.y):
				_touch_axis = 1
			elif absf(d.y) > 14.0 and absf(d.y) > absf(d.x):
				_touch_axis = 2
		if _touch_axis == 1:
			var want := int(d.x / SWIPE_CELL)
			while _touch_moved_cells < want and _field.move(1):
				_touch_moved_cells += 1
			while _touch_moved_cells > want and _field.move(-1):
				_touch_moved_cells -= 1
			_touch_soft_drop = false
		elif _touch_axis == 2:
			if d.y > 24.0 and e.velocity.y > FLICK_SPEED:
				_field.hard_drop()
				_touch_id = -1
				_touch_soft_drop = false
			else:
				_touch_soft_drop = d.y > 12.0


## Mouse scheme: the cursor column picks where the piece should go; the field
## finds the best-fitting rotation + landing there (tuck under overhangs) and
## shows it as the ghost. Wheel forces a rotation; left-click hard-drops into
## the placement; right-click holds.
func _mouse_update(screen_pos: Vector2) -> void:
	if _field.piece_left_col() < 0:
		return
	var col := (screen_pos.x - WELL_ORIGIN.x) / float(Playfield.CELL) - 0.5
	_field.set_suggestion(_field.suggest_placement(col))


func _process(dt: float) -> void:
	if _state != State.PLAYING:
		return
	if _touch_id >= 0:
		_touch_time += dt
	_field.soft_drop_active = _touch_soft_drop or Input.is_action_pressed("soft_drop")

	var dir := 0
	if Input.is_action_pressed("move_right"):
		dir += 1
	if Input.is_action_pressed("move_left"):
		dir -= 1

	if dir == 0:
		_das_dir = 0
		if _mouse_active:
			_mouse_update(_last_mouse_pos)
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
	_draw_preview_frame(HOLD_BOX)
	_draw_preview_frame(NEXT_BOX)
	if _field == null:
		return
	if _field.hold_type() >= 0:
		_draw_piece_in_box(_field.hold_type(), HOLD_BOX)
	var q := _field.queue_types()
	if q.size() > 0:
		_draw_piece_in_box(q[0], NEXT_BOX)


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
