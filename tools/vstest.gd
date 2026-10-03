extends SceneTree

## Online versus end to end (v1.1): two windows + a local relay.
##   cd ../mario-clone/server && PORT=8765 node relay.js
##   TETRIS_RELAY=ws://127.0.0.1:8765 godot --path . --script res://tools/vstest.gd -- host <dir>
##   TETRIS_RELAY=ws://127.0.0.1:8765 godot --path . --script res://tools/vstest.gd -- guest <dir>
## The host writes the room code to <dir>/room.txt; both take screenshots
## and print "VS ..." lines. Run with --audio-driver Dummy.

var role := "host"
var outdir := "/tmp"
var main: Main
var n := 0

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		role = a[0]
	if a.size() > 1:
		outdir = a[1]
	_run.call_deferred()

func _wait(t: float) -> void:
	await create_timer(t).timeout

func shot(label: String) -> void:
	await process_frame
	await process_frame
	n += 1
	var path := "%s/%s_%02d_%s.png" % [outdir, role, n, label]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

func until(cond: Callable, t := 10.0) -> bool:
	while t > 0.0:
		if cond.call():
			return true
		await _wait(0.1)
		t -= 0.1
	return false

func info(tag: String) -> void:
	print("VS %s %s: mode=%s state=%d incoming=%d wins=%d losses=%d opp_cells=%d ui=%d" % [role, tag,
		main._vs_mode, main._state, main._field.incoming, main._versus.wins, main._versus.losses,
		main._opp_cells.size(), main._ui._screen])

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.5)
	main._ui._finish_splash()
	await _wait(0.5)
	main._ui.show_versus()
	await shot("menu")
	if role == "host":
		await host()
	else:
		await guest()
	await _wait(1.0)
	quit()

func host() -> void:
	main._vs_host()
	await until(func(): return main._versus.link and main._versus.link.room_code != "")
	var code: String = main._versus.link.room_code
	FileAccess.open(outdir + "/room.txt", FileAccess.WRITE).store_string(code)
	await _wait(0.3)
	await shot("code")
	print("VS host code ", code)
	await until(func(): return main._vs_mode, 20.0)
	info("round 1")
	for i in 4:
		main._field.hard_drop()
		await _wait(0.5)
	main._on_lines_cleared(4, false)        # a Tetris: 4 rows for the guest
	await _wait(1.0)
	await shot("sent")
	info("sent 4")
	await until(func(): return main._state == Main.State.OVER, 20.0)
	await _wait(0.5)
	info("result")
	await shot("result")
	main._ui.versus_rematch.emit()
	await until(func(): return main._vs_mode and main._state == Main.State.PLAYING, 10.0)
	info("round 2")
	await _wait(1.0)
	main._pause()
	await _wait(1.0)
	await shot("paused")
	info("paused")
	main._resume()
	await _wait(1.0)
	info("resumed")
	await until(func(): return main._ui._screen == Ui.Screen.VS_INFO, 15.0)
	info("guest left")
	await shot("left")

func guest() -> void:
	await until(func(): return FileAccess.file_exists(outdir + "/room.txt"), 20.0)
	await _wait(0.3)
	var code := FileAccess.get_file_as_string(outdir + "/room.txt").to_lower()   # typed in lower case
	main._ui._screen = Ui.Screen.VS_JOIN
	main._ui._build()
	await _wait(0.3)
	await shot("join")
	main._vs_join(code)
	await until(func(): return main._vs_mode, 10.0)
	info("round 1")
	await until(func(): return main._field.incoming > 0, 15.0)
	await _wait(0.4)
	info("attacked")
	await shot("incoming")
	main._field.hard_drop()                  # lock without a clear: garbage comes up
	await _wait(1.0)
	await shot("garbage")
	info("after garbage")
	main._field.topped_out.emit()           # lose round 1
	await _wait(1.0)
	info("result")
	await shot("result")
	main._ui.versus_rematch.emit()
	await until(func(): return main._vs_mode and main._state == Main.State.PLAYING, 10.0)
	info("round 2")
	await until(func(): return main._state == Main.State.PAUSED, 10.0)
	await _wait(0.5)
	await shot("paused_by_host")
	info("paused by host")
	await until(func(): return main._state == Main.State.PLAYING, 10.0)
	info("resumed")
	await _wait(0.8)
	main._ui.versus_leave.emit()
	await _wait(0.5)
	info("left")
