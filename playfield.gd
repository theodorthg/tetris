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
signal piece_spawned           ## a new active piece is in play

const COLS := 10
const ROWS := 20
var cell := 27
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const SOFT_DROP_FACTOR := 20.0   ## soft drop is this many times normal gravity
const _DOWN := Vector2i(0, 1)

var fall_interval: float = 1.0   ## seconds per row; set by main per level
var soft_drop_active := false
var playing := false
var ghost_enabled := true

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

## Mouse-assist: the suggested landing {rot,x,y} that the ghost shows and that
## a hard drop snaps to. Empty when the player is on keyboard/touch.
var _suggest: Dictionary = {}
## -1 = let the assist choose the rotation; 0..3 = rotation locked by the
## player (mouse wheel). Reset on every new piece.
var _rot_lock := -1


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
	_suggest = {}
	_rot_lock = -1
	if not _valid(_type, _rot, _pos):
		# try nudging up one (piece pokes above ceiling on spawn)
		if _valid(_type, _rot, _pos + Vector2i(0, -1)):
			_pos += Vector2i(0, -1)
		else:
			playing = false
			topped_out.emit()
			queue_redraw()
			return
	piece_spawned.emit()
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


## Resulting [new_rot, new_pos] after an SRS rotation with wall kicks, or []
## if every kick is blocked. Pure — does not mutate the piece.
func _rotated_state(type: int, rot: int, pos: Vector2i, dir: int) -> Array:
	var nr := (rot + dir) % 4
	if nr < 0:
		nr += 4
	var table = Pieces.KICKS[Pieces.kick_kind(type)]
	var kicks: Array = table.get(rot, {}).get(nr, [Vector2i.ZERO])
	for k in kicks:
		var np: Vector2i = pos + Vector2i(k.x, k.y)
		if _valid(type, nr, np):
			return [nr, np]
	return []


func rotate_piece(dir: int) -> bool:
	if not playing or _type < 0:
		return false
	var st := _rotated_state(_type, _rot, _pos, dir)
	if st.is_empty():
		return false
	_rot = st[0]
	_pos = st[1]
	_touch_lock_reset()
	queue_redraw()
	return true


func hard_drop() -> void:
	if not playing or _type < 0:
		return
	var from_y := _pos.y
	if _suggest.has("y") and _valid(_type, _suggest.rot, Vector2i(_suggest.x, _suggest.y)):
		# snap to the mouse-assisted placement (may tuck under an overhang)
		_rot = _suggest.rot
		_pos = Vector2i(_suggest.x, _suggest.y)
	else:
		_pos = _ghost_pos()
	var dist: int = maxi(_pos.y - from_y, 0)
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


## Width in cells of the active piece at its current rotation (1 if none).
func piece_width() -> int:
	if _type < 0:
		return 1
	var minx := COLS
	var maxx := -COLS
	for c in Pieces.CELLS[_type][_rot]:
		minx = mini(minx, c.x)
		maxx = maxi(maxx, c.x)
	return maxx - minx + 1


# --- mouse placement assist -------------------------------------------

func set_suggestion(s: Dictionary) -> void:
	if s == _suggest:
		return
	_suggest = s
	queue_redraw()


func clear_suggestion() -> void:
	_rot_lock = -1
	if not _suggest.is_empty():
		_suggest = {}
		queue_redraw()


func has_suggestion() -> bool:
	return not _suggest.is_empty()


## Rotate the active piece toward an absolute state (0..3) by the shorter path,
## one legal SRS step at a time. Best-effort — stops when a step is blocked.
func rotate_to(target: int) -> void:
	if not playing or _type < 0:
		return
	target = posmod(target, 4)
	var guard := 0
	while _rot != target and guard < 3:
		var diff := posmod(target - _rot, 4)
		if not rotate_piece(1 if diff <= 2 else -1):
			return
		guard += 1


## Slide the active piece so its bounding box sits at column `target_x`,
## best-effort (stops at a wall / the stack).
func slide_to_box_x(target_x: int) -> void:
	if not playing or _type < 0:
		return
	var guard := 0
	while _pos.x != target_x and guard < COLS + 4:
		if not move(signi(target_x - _pos.x)):
			return
		guard += 1


## Aim assist for mouse / touch: pick the best placement for `target_col`, show
## it as the ghost, AND bring the falling piece into that orientation and column
## so it stays consistent with the ghost (the keyboard already works this way).
func aim(target_col: float) -> void:
	if not playing or _type < 0:
		return
	var s := suggest_placement(target_col)
	if s.is_empty():
		set_suggestion({})
		return
	rotate_to(s.rot)
	slide_to_box_x(s.x)
	set_suggestion(s)


## Mouse wheel: lock the assist to the next / previous rotation for this piece
## (S/Z/I only have two distinct shapes but cycling 0..3 still feels right).
func cycle_rot_lock(dir: int) -> void:
	if not playing or _type < 0:
		return
	var base := _rot_lock if _rot_lock >= 0 else _rot
	_rot_lock = posmod(base + dir, 4)


func _occ(x: int, y: int) -> bool:
	if x < 0 or x >= COLS or y >= ROWS:
		return true
	if y < 0:
		return false
	return _grid[y][x] != -1


## Best landing for a piece aimed at `target_col`: a BFS over
## left / right / soft-drop / rotate collecting every resting position, then a
## heuristic pick (few holes, clears lines, lies low and flat, stays near the
## cursor column). Returns {rot,x,y} or {}.
## The BFS starts from the TOP (canonical spawn) — not the piece's current fall
## position — so the result depends only on the target column and the board,
## not on how far the piece has dropped (which would make the ghost jitter).
func suggest_placement(target_col: float) -> Dictionary:
	if not playing or _type < 0:
		return {}
	var start := Vector2i(Pieces.SPAWN_X[_type], 0)
	var start_ok := false
	for yy in [0, -1, -2]:
		if _valid(_type, 0, Vector2i(start.x, yy)):
			start.y = yy
			start_ok = true
			break
	if not start_ok:
		return {}
	var seen := {}
	seen[Vector3i(start.x, start.y, 0)] = true
	var frontier: Array = [[0, start]]
	var landed: Array = []
	var iterations := 0
	while not frontier.is_empty() and iterations < 4000:
		iterations += 1
		var s = frontier.pop_back()
		var r: int = s[0]
		var p: Vector2i = s[1]
		if not _valid(_type, r, p + _DOWN):
			landed.append([r, p])
		var moves: Array = [
			[r, p + Vector2i(-1, 0)],
			[r, p + Vector2i(1, 0)],
			[r, p + _DOWN],
		]
		var cw := _rotated_state(_type, r, p, 1)
		if not cw.is_empty():
			moves.append(cw)
		var ccw := _rotated_state(_type, r, p, -1)
		if not ccw.is_empty():
			moves.append(ccw)
		for m in moves:
			var key := Vector3i(m[1].x, m[1].y, m[0])
			if not seen.has(key) and _valid(_type, m[0], m[1]):
				seen[key] = true
				frontier.append([m[0], m[1]])

	if landed.is_empty():
		return {}

	# If the player locked a rotation with the wheel, only keep that one
	# (fall back to all if it can't be reached).
	if _rot_lock >= 0:
		var locked: Array = []
		for l in landed:
			if l[0] == _rot_lock:
				locked.append(l)
		if not locked.is_empty():
			landed = locked

	# The cursor column is honoured as WHERE the piece goes: keep only
	# placements that actually occupy that column (widen the tolerance only if
	# nothing does), then let the heuristic pick the ROTATION / exact fit.
	var tc := clampi(roundi(target_col), 0, COLS - 1)
	for tol in [0, 1, 2, COLS]:
		var pool: Array = []
		for l in landed:
			if _covers_column(l[0], l[1], tc, tol):
				pool.append(l)
		if not pool.is_empty():
			return _best_of(pool, target_col)
	return _best_of(landed, target_col)


func _covers_column(rot: int, pos: Vector2i, col: int, tol: int) -> bool:
	for c in Pieces.CELLS[_type][rot]:
		if absi(pos.x + c.x - col) <= tol:
			return true
	return false


func _best_of(pool: Array, target_col: float) -> Dictionary:
	var best := {}
	var best_score := -INF
	for l in pool:
		var sc := _placement_score(l[0], l[1], target_col)
		if sc > best_score:
			best_score = sc
			best = {"rot": l[0], "x": l[1].x, "y": l[1].y}
	return best


func _placement_score(rot: int, pos: Vector2i, target_col: float) -> float:
	var new_cells := {}
	var sum_x := 0.0
	var pmin_y := ROWS
	var pmax_y := -ROWS
	for c in Pieces.CELLS[_type][rot]:
		var pc: Vector2i = pos + c
		new_cells[pc] = true
		sum_x += pc.x
		pmin_y = mini(pmin_y, pc.y)
		pmax_y = maxi(pmax_y, pc.y)
	var center := sum_x / 4.0
	var piece_span_y := pmax_y - pmin_y   # 0 for a flat I, 3 for a vertical I

	var heights: Array = []
	var aggregate := 0
	var holes := 0
	for x in COLS:
		var top := ROWS
		var seen_block := false
		var col_holes := 0
		for y in ROWS:
			var occ: bool = _occ(x, y) or new_cells.has(Vector2i(x, y))
			if occ:
				if not seen_block:
					top = y
				seen_block = true
			elif seen_block:
				col_holes += 1
		heights.append(ROWS - top)
		aggregate += ROWS - top
		holes += col_holes

	var bumpiness := 0
	for x in range(COLS - 1):
		bumpiness += absi(heights[x] - heights[x + 1])

	var lines := 0
	for y in ROWS:
		var full := true
		for x in COLS:
			if not (_occ(x, y) or new_cells.has(Vector2i(x, y))):
				full = false
				break
		if full:
			lines += 1

	# holes dominate; lines are good; filling wells (lower bumpiness) is good.
	# a small "lie flat" nudge (piece_span_y) keeps long pieces horizontal
	# unless a vertical fit clearly wins on holes/bumpiness; height stays a
	# gentle nudge so deep gap-fills against a wall aren't rejected for height.
	return 4.0 * float(lines) \
		- 6.0 * float(holes) \
		- 0.55 * float(bumpiness) \
		- 0.16 * float(aggregate) \
		- 0.45 * float(piece_span_y) \
		- 0.8 * absf(center - target_col)


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
	var w := COLS * cell
	var h := ROWS * cell
	# well background + frame
	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.05, 0.08, 1.0))
	for x in range(1, COLS):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, h), Color(1, 1, 1, 0.04), 1.0)
	for y in range(1, ROWS):
		draw_line(Vector2(0, y * cell), Vector2(w, y * cell), Color(1, 1, 1, 0.04), 1.0)

	# locked cells
	for r in ROWS:
		for c in COLS:
			var t: int = _grid[r][c]
			if t != -1:
				_draw_cell(c, r, Pieces.COLORS[t], 1.0)

	if _type >= 0 and playing:
		# ghost — mouse-suggested placement if any, else straight down
		var g_rot := _rot
		var g_pos := _ghost_pos()
		if _suggest.has("y"):
			g_rot = _suggest.rot
			g_pos = Vector2i(_suggest.x, _suggest.y)
		var show_ghost := ghost_enabled or _suggest.has("y")
		if show_ghost and (g_rot != _rot or g_pos != _pos):
			for cc in Pieces.CELLS[_type][g_rot]:
				var gc: Vector2i = g_pos + cc
				if gc.y >= 0:
					_draw_ghost_cell(gc.x, gc.y, Pieces.COLORS[_type])
		# active piece
		for cc in Pieces.CELLS[_type][_rot]:
			var pc: Vector2i = _pos + cc
			if pc.y >= 0:
				_draw_cell(pc.x, pc.y, Pieces.COLORS[_type], 1.0)

	draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, 0.22), false, 2.0)


func _draw_cell(col: int, row: int, color: Color, alpha: float) -> void:
	var p := Vector2(col * cell, row * cell)
	var inner := Rect2(p + Vector2(1, 1), Vector2(cell - 2, cell - 2))
	draw_rect(inner, Color(color, alpha))
	draw_rect(inner, Color(1, 1, 1, 0.18), false, 1.0)
	draw_rect(Rect2(inner.position + Vector2(2, 2), Vector2(inner.size.x - 4, 4)),
		Color(1, 1, 1, 0.22))


## Ghost outline: a lightened frame plus a very faint fill so it reads clearly
## against the well without being mistaken for a locked cell.
func _draw_ghost_cell(col: int, row: int, color: Color) -> void:
	var p := Vector2(col * cell, row * cell)
	var inner := Rect2(p + Vector2(1.5, 1.5), Vector2(cell - 3, cell - 3))
	var glow := color.lightened(0.18)
	glow.a = 0.8
	draw_rect(inner, Color(color, 0.07))
	draw_rect(inner, glow, false, 2.0)


# helpers for previews (used by the HUD) -------------------------------

func hold_type() -> int:
	return _hold


func queue_types() -> Array:
	return _queue.duplicate()
