class_name Main
extends Node2D

## Round coordinator: owns score / level / lines / fall speed and the game
## state machine, wires the playfield to the HUD and the (milestone-2) menus,
## and routes keyboard + mouse + gamepad input to the playfield. Touch is added
## in milestone 2.

enum State { START, PLAYING, PAUSED, OVER }

const DESIGN := Vector2(480, 800)
const WELL_ORIGIN := Vector2(80, 120)
const HOLD_BOX := Rect2(12, 20, 84, 84)
const NEXT_BOX := Rect2(384, 20, 84, 84)
const PREVIEW_CELL := 16

const DAS := 0.16
const ARR := 0.03
const LINE_SCORE := [0, 100, 300, 500, 800]

var _state: int = State.START
var _score := 0
var _lines := 0
var _level := 1
var _start_level := 1

var _field: Playfield
var _score_label: Label
var _level_label: Label
var _lines_label: Label
var _msg_title: Label
var _msg_sub: Label
var _overlay: ColorRect

var _das_dir := 0
var _das_time := 0.0
var _arr_time := 0.0
var _mouse_control := true


func _ready() -> void:
	_build()
	_show_start()


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

	_score_label = _mk_label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.position = Vector2(110, 14)
	_score_label.size = Vector2(260, 34)
	add_child(_score_label)
	_level_label = _mk_label(15, HORIZONTAL_ALIGNMENT_CENTER)
	_level_label.position = Vector2(108, 54)
	_level_label.size = Vector2(130, 22)
	add_child(_level_label)
	_lines_label = _mk_label(15, HORIZONTAL_ALIGNMENT_CENTER)
	_lines_label.position = Vector2(242, 54)
	_lines_label.size = Vector2(130, 22)
	add_child(_lines_label)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.04, 0.06, 0.82)
	_overlay.size = DESIGN
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_msg_title = _mk_label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_msg_title.position = Vector2(0, 292)
	_msg_title.size = Vector2(DESIGN.x, 56)
	_overlay.add_child(_msg_title)
	_msg_sub = _mk_label(16, HORIZONTAL_ALIGNMENT_CENTER)
	_msg_sub.position = Vector2(24, 366)
	_msg_sub.size = Vector2(DESIGN.x - 48, 200)
	_overlay.add_child(_msg_sub)

	_update_hud()


func _mk_label(font_size: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- state --------------------------------------------------------------

func _show_start() -> void:
	_state = State.START
	_overlay.visible = true
	_msg_title.text = "TETRIS"
	_msg_sub.text = "Press any key, click or tap to start\n\nMove:  Arrows / A D / mouse\nRotate:  Up / X / Z / left-click\nSoft drop:  Down / S\nHard drop:  Space / right-click\nHold:  C     Pause:  Esc / P"
	queue_redraw()


func _start_game() -> void:
	_score = 0
	_lines = 0
	_level = _start_level
	_state = State.PLAYING
	_overlay.visible = false
	_field.fall_interval = _fall_interval_for(_level)
	_field.start()
	_update_hud()
	queue_redraw()


func _on_top_out() -> void:
	_state = State.OVER
	_field.stop()
	_overlay.visible = true
	_msg_title.text = "GAME OVER"
	_msg_sub.text = "Score %d   ·   Lines %d   ·   Level %d\n\nPress any key, click or tap to continue" % [_score, _lines, _level]
	queue_redraw()


func _toggle_pause() -> void:
	if _state == State.PLAYING:
		_state = State.PAUSED
		_field.set_process(false)
		_overlay.visible = true
		_msg_title.text = "PAUSED"
		_msg_sub.text = "Press Esc or click to resume"
	elif _state == State.PAUSED:
		_state = State.PLAYING
		_field.set_process(true)
		_overlay.visible = false
	queue_redraw()


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
	if _state == State.START or _state == State.OVER:
		if (e is InputEventKey and e.pressed and not e.echo) \
		or (e is InputEventMouseButton and e.pressed) \
		or (e is InputEventScreenTouch and e.pressed) \
		or (e is InputEventJoypadButton and e.pressed):
			if _state == State.OVER:
				_show_start()
			else:
				_start_game()
			get_viewport().set_input_as_handled()
		return

	if e.is_action_pressed("pause_game"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _state != State.PLAYING:
		if e is InputEventMouseButton and e.pressed:
			_toggle_pause()
		return

	if e.is_action_pressed("rotate_cw"):
		_field.rotate_piece(1)
	elif e.is_action_pressed("rotate_ccw"):
		_field.rotate_piece(-1)
	elif e.is_action_pressed("hard_drop"):
		_field.hard_drop()
	elif e.is_action_pressed("hold_piece"):
		_field.hold()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_field.rotate_piece(1)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_field.hard_drop()
	elif e is InputEventMouseMotion and _mouse_control:
		_mouse_follow(e.position)


func _mouse_follow(screen_pos: Vector2) -> void:
	# map the mouse to a target column and step the piece toward it
	var local_x := screen_pos.x - WELL_ORIGIN.x
	var target_col := int(floor(local_x / float(Playfield.CELL))) - 1
	var cur := _field.piece_left_col()
	if cur < 0:
		return
	var guard := 0
	while cur != target_col and guard < Playfield.COLS:
		var dir: int = signi(target_col - cur)
		if not _field.move(dir):
			break
		cur += dir
		guard += 1


func _process(dt: float) -> void:
	if _state != State.PLAYING:
		return
	_field.soft_drop_active = Input.is_action_pressed("soft_drop")

	var dir := 0
	if Input.is_action_pressed("move_right"):
		dir += 1
	if Input.is_action_pressed("move_left"):
		dir -= 1

	if dir == 0:
		_das_dir = 0
		return
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
	_draw_preview_frame(HOLD_BOX, "HOLD")
	_draw_preview_frame(NEXT_BOX, "NEXT")
	if _field == null:
		return
	if _field.hold_type() >= 0:
		_draw_piece_in_box(_field.hold_type(), HOLD_BOX)
	var q := _field.queue_types()
	if q.size() > 0:
		_draw_piece_in_box(q[0], NEXT_BOX)


func _draw_preview_frame(box: Rect2, _title: String) -> void:
	draw_rect(box, Color(0.06, 0.07, 0.10, 1.0))
	draw_rect(box, Color(1, 1, 1, 0.18), false, 1.0)


func _draw_piece_in_box(type: int, box: Rect2) -> void:
	var cells: Array = Pieces.CELLS[type][0]
	var minx := 99; var maxx := -99; var miny := 99; var maxy := -99
	for c in cells:
		minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	var w := (maxx - minx + 1) * PREVIEW_CELL
	var h := (maxy - miny + 1) * PREVIEW_CELL
	var origin := box.position + (box.size - Vector2(w, h)) * 0.5
	var col: Color = Pieces.COLORS[type]
	for c in cells:
		var p: Vector2 = origin + Vector2((c.x - minx) * PREVIEW_CELL, (c.y - miny) * PREVIEW_CELL)
		var r := Rect2(p + Vector2(1, 1), Vector2(PREVIEW_CELL - 2, PREVIEW_CELL - 2))
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)
