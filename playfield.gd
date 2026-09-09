class_name Playfield
extends Node2D

## The 10x20 well: owns the locked-cell grid, the active piece, the ghost, and
## all fall / lock timing. Emits gameplay events; scoring, level and fall speed
## live in main.gd. Drawn in local space with (0,0) at the top-left of the well.

signal lines_cleared(rows: int)
signal piece_locked
signal hold_changed(type: int)
signal next_changed(queue: Array)
signal topped_out
signal soft_drop_cell          ## one row gained by holding soft-drop (score +1)
signal hard_dropped(rows: int) ## distance of a hard drop (score +2 per row)

const COLS := 10
const ROWS := 20
const CELL := 32
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const SOFT_DROP_FACTOR := 20.0   ## soft drop is this many times normal gravity

var fall_interval: float = 1.0   ## seconds per row; set by main per level
var soft_drop_active := false
var playing := false

var _grid: Array = []            ## _grid[row][col] -> -1 empty, else piece type
var _bag: Array = []
var _queue: Array = []           ## upcoming piece types
var _type := -1
var _rot := 0
var _pos := Vector2i.ZERO        ## piece bounding-box origin, grid coords
var _hold := -1
var _hold_used := false
var _fall_accum := 0.0
var _lock_accum := 0.0
var _lock_resets := 0
var _on_floor := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_reset_grid()
	set_process(true)


func _reset_grid() -> void:
	_grid.clear()
	for r in ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill(-1)
		_grid.append(row)


func start() -> void:
	_reset_grid()
	_bag.clear()
	_queue.clear()
	_hold = -1
	_hold_used = false
	_type = -1
	for i in 5:
		_queue.append(_bag_next())
	playing = true
	set_process(true)
	next_changed.emit(_queue.duplicate())
	hold_changed.emit(_hold)
	_spawn_from_queue()
	queue_redraw()


func stop() -> void:
	playing = false
	set_process(false)
	queue_redraw()


func _bag_next() -> int:
	if _bag.is_empty():
		_bag = [Pieces.I, Pieces.O, Pieces.T, Pieces.S, Pieces.Z, Pieces.J, Pieces.L]
		for i in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = _bag[i]; _bag[i] = _bag[j]; _bag[j] = tmp
	return _bag.pop_front()


func _spawn_from_queue() -> void:
	_type = _queue.pop_front()
	_queue.append(_bag_next())
	next_changed.emit(_queue.duplicate())
	_spawn_current()


func _spawn_current() -> void:
	_rot = 0
	_pos = Vector2i(Pieces.SPAWN_X[_type], 0)
	_fall_accum = 0.0
	_reset_lock()
	if not _valid(_type, _rot, _pos):
		# try nudging up one (piece pokes above ceiling on spawn)
		if _valid(_type, _rot, _pos + Vector2i(0, -1)):
			_pos += Vector2i(0, -1)
		else:
			playing = false
			topped_out.emit()
			queue_redraw()
			return
	queue_redraw()


func _reset_lock() -> void:
	_lock_accum = 0.0
	_on_floor = false


# --- queries ---------------------------------------------------------------

func _cells(type: int, rot: int, pos: Vector2i) -> Array:
	var out: Array = []
	for c in Pieces.CELLS[type][rot]:
		out.append(pos + c)
	return out


func _valid(type: int, rot: int, pos: Vector2i) -> bool:
	for c in _cells(type, rot, pos):
		if c.x < 0 or c.x >= COLS or c.y >= ROWS:
			return false
		if c.y >= 0 and _grid[c.y][c.x] != -1:
			return false
	return true


func _ghost_pos() -> Vector2i:
	var p := _pos
	while _valid(_type, _rot, p + Vector2i(0, 1)):
		p += Vector2i(0, 1)
	return p


# --- player actions ------------------------------------------------------

func move(dx: int) -> bool:
	if not playing or _type < 0:
		return false
	var np := _pos + Vector2i(dx, 0)
	if _valid(_type, _rot, np):
		_pos = np
		_touch_lock_reset()
		queue_redraw()
		return true
	return false


func rotate_piece(dir: int) -> bool:
	if not playing or _type < 0:
		return false
	var nr := (_rot + dir) % 4
	if nr < 0:
		nr += 4
	var table = Pieces.KICKS[Pieces.kick_kind(_type)]
	var kicks: Array = table.get(_rot, {}).get(nr, [Vector2i.ZERO])
	for k in kicks:
		# kick x is column (+ right), y is row-down already
		var np := _pos + Vector2i(k.x, k.y)
		if _valid(_type, nr, np):
			_rot = nr
			_pos = np
			_touch_lock_reset()
			queue_redraw()
			return true
	return false


func hard_drop() -> void:
	if not playing or _type < 0:
		return
	var g := _ghost_pos()
	var dist := g.y - _pos.y
	_pos = g
	if dist > 0:
		hard_dropped.emit(dist)
	_lock_piece()


func hold() -> void:
	if not playing or _type < 0 or _hold_used:
		return
	var prev := _hold
	_hold = _type
	_hold_used = true
	hold_changed.emit(_hold)
	if prev == -1:
		_spawn_from_queue()
	else:
		_type = prev
		_spawn_current()


## Left-most column occupied by the active piece, or -1 if there is none.
func piece_left_col() -> int:
	if _type < 0:
		return -1
	var minx := COLS
	for c in Pieces.CELLS[_type][_rot]:
		minx = mini(minx, _pos.x + c.x)
	return minx


func _touch_lock_reset() -> void:
	if _on_floor and _lock_resets < MAX_LOCK_RESETS:
		_lock_accum = 0.0
		_lock_resets += 1


# --- timing --------------------------------------------------------------

func _process(dt: float) -> void:
	if not playing or _type < 0:
		return
	var interval := fall_interval
	if soft_drop_active:
		interval = minf(interval, fall_interval / SOFT_DROP_FACTOR)
		interval = maxf(interval, 0.001)

	var can_fall := _valid(_type, _rot, _pos + Vector2i(0, 1))
	if can_fall:
		_on_floor = false
		_fall_accum += dt
		while _fall_accum >= interval and _valid(_type, _rot, _pos + Vector2i(0, 1)):
			_fall_accum -= interval
			_pos += Vector2i(0, 1)
			if soft_drop_active:
				soft_drop_cell.emit()
			queue_redraw()
	else:
		_on_floor = true
		_fall_accum = 0.0
		_lock_accum += dt
		if _lock_accum >= LOCK_DELAY:
			_lock_piece()


func _lock_piece() -> void:
	var topped := true
	for c in _cells(_type, _rot, _pos):
		if c.y >= 0:
			topped = false
		if c.y >= 0 and c.y < ROWS and c.x >= 0 and c.x < COLS:
			_grid[c.y][c.x] = _type
	_lock_resets = 0
	_hold_used = false
	piece_locked.emit()
	if topped:
		playing = false
		topped_out.emit()
		queue_redraw()
		return
	var cleared := _clear_lines()
	if cleared > 0:
		lines_cleared.emit(cleared)
	_type = -1
	queue_redraw()
	_spawn_from_queue()


func _clear_lines() -> int:
	var kept: Array = []
	var cleared := 0
	for r in ROWS:
		if _grid[r].has(-1):
			kept.append(_grid[r])
		else:
			cleared += 1
	while kept.size() < ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill(-1)
		kept.push_front(row)
	_grid = kept
	return cleared


# --- rendering ----------------------------------------------------------

func _draw() -> void:
	var w := COLS * CELL
	var h := ROWS * CELL
	# well background + frame
	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.05, 0.08, 1.0))
	for x in range(1, COLS):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, h), Color(1, 1, 1, 0.04), 1.0)
	for y in range(1, ROWS):
		draw_line(Vector2(0, y * CELL), Vector2(w, y * CELL), Color(1, 1, 1, 0.04), 1.0)

	# locked cells
	for r in ROWS:
		for c in COLS:
			var t: int = _grid[r][c]
			if t != -1:
				_draw_cell(c, r, Pieces.COLORS[t], 1.0)

	if _type >= 0 and playing:
		# ghost
		var g := _ghost_pos()
		if g != _pos:
			for cc in Pieces.CELLS[_type][_rot]:
				var gc: Vector2i = g + cc
				if gc.y >= 0:
					_draw_cell(gc.x, gc.y, Pieces.COLORS[_type], 0.18)
		# active piece
		for cc in Pieces.CELLS[_type][_rot]:
			var pc: Vector2i = _pos + cc
			if pc.y >= 0:
				_draw_cell(pc.x, pc.y, Pieces.COLORS[_type], 1.0)

	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.22), false, 2.0)


func _draw_cell(col: int, row: int, color: Color, alpha: float) -> void:
	var p := Vector2(col * CELL, row * CELL)
	var inner := Rect2(p + Vector2(1, 1), Vector2(CELL - 2, CELL - 2))
	if alpha < 0.5:
		draw_rect(inner, Color(color, alpha), false, 2.0)
	else:
		draw_rect(inner, Color(color, alpha))
		draw_rect(inner, Color(1, 1, 1, 0.18), false, 1.0)
		draw_rect(Rect2(inner.position + Vector2(2, 2), Vector2(inner.size.x - 4, 4)),
			Color(1, 1, 1, 0.22))


# helpers for previews (used by the HUD) -------------------------------

func hold_type() -> int:
	return _hold


func queue_types() -> Array:
	return _queue.duplicate()
