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

	print("SELFTEST: %s (%d failure(s))" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  ok   ", msg)
		return 0
	print("  FAIL ", msg)
	return 1
