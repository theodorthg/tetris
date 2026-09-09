extends SceneTree

## Throwaway headless checks for the board rules. Run:
##   godot --headless --path . --script res://_selftest.gd
## Not shipped (see .gitignore-style note) — delete or keep out of exports.

func _init() -> void:
	var pf := Playfield.new()
	pf._reset_grid()
	var fails := 0

	# fill the bottom two rows except column 0 -> two line clears when col 0 fills
	for r in [Playfield.ROWS - 1, Playfield.ROWS - 2]:
		for c in range(1, Playfield.COLS):
			pf._grid[r][c] = Pieces.O
	pf._grid[Playfield.ROWS - 1][0] = Pieces.O
	pf._grid[Playfield.ROWS - 2][0] = Pieces.O
	var cleared := pf._clear_lines()
	fails += _expect(cleared == 2, "clear 2 full rows, got %d" % cleared)
	fails += _expect(pf._grid[Playfield.ROWS - 1].count(-1) == Playfield.COLS,
		"bottom row empty after clear")

	# SRS: T spawn must be valid on an empty well
	pf._reset_grid()
	fails += _expect(pf._valid(Pieces.T, 0, Vector2i(Pieces.SPAWN_X[Pieces.T], 0)),
		"T spawn valid on empty well")

	# 7-bag: every 7 draws contain each piece once
	pf._bag.clear()
	var seen := {}
	for i in 7:
		seen[pf._bag_next()] = true
	fails += _expect(seen.size() == 7, "7-bag yields all 7 distinct, got %d" % seen.size())

	# wall kick: T against the left wall — state L has a cell in box column 0, so
	# rotating there from spawn must kick +1 to stay inside the well.
	pf._reset_grid()
	pf.playing = true
	pf._type = Pieces.T
	pf._rot = 0
	pf._pos = Vector2i(-1, 5)         # box origin off the left edge
	fails += _expect(not pf._valid(Pieces.T, 3, pf._pos), "T-L at x=-1 pokes out of the well")
	var ok := pf.rotate_piece(-1)     # 0 -> L, needs an x+1 kick
	fails += _expect(ok, "T piece kicks off the left wall when rotating to L")
	fails += _expect(pf._valid(pf._type, pf._rot, pf._pos), "T ended in a legal spot")

	# mouse assist: an overhang with a one-wide gap under it — the suggestion
	# must tuck the piece into the gap (y at the floor), not rest on the lip.
	pf._reset_grid()
	pf.playing = true
	var floor_row := Playfield.ROWS - 1
	for c in Playfield.COLS:
		if c != 2:
			pf._grid[floor_row][c] = Pieces.L        # floor with a hole at col 2
	pf._grid[floor_row - 1][3] = Pieces.L            # overhang lip next to the hole
	pf._grid[floor_row - 1][4] = Pieces.L
	pf._type = Pieces.I
	pf._rot = 1                                       # vertical I, high up
	pf._pos = Vector2i(1, 0)
	var sug := pf.suggest_placement(2.0)
	fails += _expect(not sug.is_empty(), "suggestion found for the gap column")
	if not sug.is_empty():
		var cells := pf._cells(pf._type, sug.rot, Vector2i(sug.x, sug.y))
		var fills_gap := false
		for cc in cells:
			if cc.x == 2 and cc.y == floor_row:
				fills_gap = true
		fails += _expect(fills_gap, "suggested placement fills the floor gap at col 2")

	# edge columns must be selectable by the assist (L and the wide I piece —
	# the I from its horizontal spawn must reach a vertical drop at col 0 / 9)
	for pt in [Pieces.L, Pieces.I]:
		for want_col in [0, Playfield.COLS - 1]:
			pf._reset_grid()
			pf.playing = true
			pf._type = pt
			pf._rot = 0
			pf._pos = Vector2i(Pieces.SPAWN_X[pt], 0)
			var e := pf.suggest_placement(float(want_col))
			var covers := false
			if not e.is_empty():
				for cc in pf._cells(pf._type, e.rot, Vector2i(e.x, e.y)):
					if cc.x == want_col:
						covers = true
			fails += _expect(covers, "%s piece can be aimed at edge column %d" % [Pieces.NAMES[pt], want_col])

	# deep 1-wide well: pointing at it should pick a vertical fill, not a flat rest
	pf._reset_grid()
	pf.playing = true
	for c in Playfield.COLS:
		if c != 6:
			for yy in range(Playfield.ROWS - 4, Playfield.ROWS):
				pf._grid[yy][c] = Pieces.J
	pf._type = Pieces.I
	pf._rot = 0
	pf._pos = Vector2i(3, 0)
	var w := pf.suggest_placement(6.0)
	fails += _expect(not w.is_empty() and w.rot in [1, 3],
		"I piece fills a deep well vertically (rot=%s)" % (w.get("rot", "none")))

	# mouse wheel locks the rotation the assist may use
	pf._reset_grid()
	pf.playing = true
	pf._type = Pieces.I
	pf._rot = 0
	pf._pos = Vector2i(3, 0)
	pf.cycle_rot_lock(1)                     # -> lock rotation 1 (vertical I)
	var lk := pf.suggest_placement(4.0)
	fails += _expect(not lk.is_empty() and lk.rot == 1,
		"wheel-locked rotation is honoured (rot=%s)" % lk.get("rot", "none"))
	pf.clear_suggestion()
	fails += _expect(pf._rot_lock == -1, "rotation lock clears with the suggestion")

	# hall of fame: keeps the top 10 by score, qualification check
	var ui := Ui.new()
	ui._hof = []
	for i in 12:
		ui._insert_hof({"name": "P%d" % i, "score": i * 100, "lines": 0, "level": 1})
	fails += _expect(ui._hof.size() == Ui.HOF_MAX, "hall of fame capped at 10")
	fails += _expect(int(ui._hof[0].score) == 1100, "hall of fame sorted desc (top=%d)" % int(ui._hof[0].score))
	fails += _expect(ui._qualifies(5000), "a big score qualifies")
	fails += _expect(not ui._qualifies(50), "a tiny score does not qualify once the board is full")
	fails += _expect(not ui._qualifies(0), "score 0 never qualifies")
	ui.free()

	print("SELFTEST: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  ok   ", msg)
		return 0
	print("  FAIL ", msg)
	return 1
