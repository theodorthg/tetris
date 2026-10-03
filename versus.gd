class_name Versus
extends Node

## Online versus (v1.1) and LAN / Wi-Fi versus (v1.2, ENet + discovery,
## see NetLink): two players, each on their own device, each runs
## their own well — nothing is simulated for the other side. What goes over
## the line (NetLink, via the relay):
##   hello {v}          both, on connect — major.minor must match
##   start {seed, lv}   the host starts a round: same piece sequence for both
##   bd    {g, l, s}    my well (Playfield.snapshot) + lines + incoming, ~10/s
##   atk   n            garbage rows for the other one (cleared lines)
##   over               I topped out — the other one wins the round
##   again              I want a rematch (the host starts when both want one)
##   pause / resume     pauses both
##   bye                I leave
## Garbage (guideline-like): 2 lines → 1, 3 → 2, 4 → 4; T-spin single 2,
## double 4, triple 6. Own clears first cancel garbage that is still waiting.

signal room_ready(code: String)
signal round_started(seed: int, level: int)
signal opponent_board(cells: PackedByteArray, lines: int, incoming: int)
signal attacked(rows: int)
signal round_won                    ## the opponent topped out
signal paused_changed(paused: bool, by_me: bool)
signal rematch_changed(mine: bool, theirs: bool)
signal ended(text: String)          ## connection gone / refused: back to the menu
signal lan_hosts_changed(hosts: Dictionary)   ## LAN guest: ip -> name

const ATTACK := [0, 0, 1, 2, 4]
const TSPIN_ATTACK := [0, 2, 4, 6]
const BOARD_EVERY := 0.1

var link: NetLink
var wins := 0
var losses := 0
var in_round := false
var _hello_ok := false
var _again_mine := false
var _again_theirs := false
var _board_t := 0.0
var _board_dirty := false
var _start_level := 1
var discovery: NetLink.Discovery   ## LAN: host beacon / guest search
var _lan_ip := ""
var _hosts_seen := {}
const FIREWALL_HINT := "Same network? A host PC with a firewall must allow UDP 47110-47111 — or play Online, that always works."


static func attack_for(rows: int, tspin: bool) -> int:
	if tspin:
		return TSPIN_ATTACK[clampi(rows, 0, 3)]
	return ATTACK[clampi(rows, 0, 4)]


func is_active() -> bool:
	return link != null


func host(level: int) -> int:
	_reset()
	_start_level = level
	link = NetLink.new()
	return link.host_online(NetLink.relay_url())


func join(code: String) -> int:
	_reset()
	link = NetLink.new()
	return link.join_online(NetLink.relay_url(), code)


## LAN host: open the game port and answer searches.
func host_lan(level: int) -> int:
	_reset()
	_start_level = level
	link = NetLink.new()
	var err := link.host_lan()
	if err != OK:
		link = null
		return err
	discovery = NetLink.Discovery.new()
	discovery.start_host(NetLink.device_name())
	return OK


## LAN guest, step 1: look for hosts (lan_hosts_changed while searching).
func search_lan() -> void:
	_reset()
	_hosts_seen = {}
	discovery = NetLink.Discovery.new()
	discovery.start_search()


## LAN guest, step 2: connect to a host.
func join_lan(ip: String) -> int:
	_stop_discovery()
	if link:
		link.close()
	link = NetLink.new()
	_lan_ip = ip
	return link.join_lan(ip)


func _stop_discovery() -> void:
	if discovery:
		discovery.stop()
	discovery = null


func _reset() -> void:
	_stop_discovery()
	if link:
		link.close()
	link = null
	wins = 0
	losses = 0
	in_round = false
	_hello_ok = false
	_again_mine = false
	_again_theirs = false


## Leave on purpose (menu "Leave"): tell the other side, close.
func leave() -> void:
	_stop_discovery()
	if link:
		link.send("bye", 0)
		link.close()
	link = null
	in_round = false


func _process(delta: float) -> void:
	if discovery:
		discovery.poll(delta)
		if not discovery.hosting:
			var now := {}
			for ip in discovery.found:
				now[ip] = str(discovery.found[ip].name)
			if now != _hosts_seen:
				_hosts_seen = now
				lan_hosts_changed.emit(now)
	if link == null:
		return
	for ev in link.poll():
		match ev[0]:
			"room":
				room_ready.emit(ev[1])
			"connect":
				_stop_discovery()
				link.send("hello", {"v": NetLink.version()})
			"disconnect":
				if link.ever_connected:
					_end("Your opponent left the game.")
				else:
					_end("No answer from %s.\n%s" % [_lan_ip, FIREWALL_HINT])
				return
			"error", "closed":
				_end(ev[1])
				return
			"msg":
				_on_msg(str(ev[1]), ev[2])
				if link == null:
					return
	if in_round and _board_dirty:
		_board_t -= delta
		if _board_t <= 0.0:
			_board_dirty = false
			_board_t = BOARD_EVERY
			var main := get_parent() as Main
			if main:
				link.send("bd", main.versus_board())


func _end(text: String) -> void:
	_stop_discovery()
	if link:
		link.close()
	link = null
	in_round = false
	ended.emit(text)


static func _major_minor(v: String) -> String:
	var p := v.split(".")
	return ".".join(p.slice(0, 2))


func _on_msg(type: String, d) -> void:
	match type:
		"hello":
			var theirs := str((d as Dictionary).get("v", "")) if d is Dictionary else ""
			if _major_minor(theirs) != _major_minor(NetLink.version()):
				link.send("bye", 0)
				_end("Different game versions (%s here, %s there) — please update both." \
					% [NetLink.version(), theirs])
				return
			_hello_ok = true
			if link.is_host:
				_start_round()
		"start":
			if d is Dictionary:
				_again_mine = false
				_again_theirs = false
				in_round = true
				_board_dirty = true
				round_started.emit(int(d.seed), int(d.lv))
		"bd":
			if d is Dictionary:
				opponent_board.emit(d.get("g", PackedByteArray()), int(d.get("l", 0)), int(d.get("i", 0)))
		"atk":
			if in_round:
				attacked.emit(int(d))
		"over":
			if in_round:
				in_round = false
				wins += 1
				round_won.emit()
		"again":
			_again_theirs = true
			rematch_changed.emit(_again_mine, _again_theirs)
			_maybe_rematch()
		"pause":
			paused_changed.emit(true, false)
		"resume":
			paused_changed.emit(false, false)
		"bye":
			_end("Your opponent left the game.")


func _start_round() -> void:
	var seed := randi() & 0x7fffffff
	_again_mine = false
	_again_theirs = false
	in_round = true
	_board_dirty = true
	link.send("start", {"seed": seed, "lv": _start_level})
	round_started.emit(seed, _start_level)


# --- called by Main ------------------------------------------------------

func board_changed() -> void:
	_board_dirty = true


func send_attack(rows: int) -> void:
	if rows > 0 and link:
		link.send("atk", rows)


## I topped out.
func lost() -> void:
	if not in_round:
		return
	in_round = false
	losses += 1
	if link:
		link.send("bd", (get_parent() as Main).versus_board())
		link.send("over", 0)


func want_rematch() -> void:
	_again_mine = true
	if link:
		link.send("again", 0)
	rematch_changed.emit(_again_mine, _again_theirs)
	_maybe_rematch()


func _maybe_rematch() -> void:
	if link and link.is_host and _again_mine and _again_theirs and _hello_ok:
		_start_round()


func set_paused(p: bool) -> void:
	if link:
		link.send("pause" if p else "resume", 0)
	paused_changed.emit(p, true)
