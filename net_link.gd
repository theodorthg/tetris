class_name NetLink
extends RefCounted

## Online versus (v1.1): a WebSocket to the relay that the series shares
## (mario-clone/server/relay.js on broesel.net). One player opens a room and
## gets a 4-letter code, the other joins with it; from then on the relay
## passes the binary messages between the two. Taken over from mario-clone's
## NetLink (online part only — no LAN here). Works in the browser too.
## Control frames from the relay are JSON text (room, joined, left, error);
## game messages are binary frames: var_to_bytes([type, payload]).

const GAME := "tetris"            ## the relay keeps rooms of different games apart
## no digits that look like letters (5/S, 2/Z, 8/B, 6/G, 0/O, 1/I)
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ3479"

var ws: WebSocketPeer
var is_host := false
var connected := false
var room_code := ""
var _ws_open := false
var _hello := {}
var _url := ""
## the first connection after the app starts sometimes fails (Wi-Fi power
## saving, cold DNS, TLS) — try again quietly while the server was never reached
var _tries := 0
const TRIES := 3

## Relay address: project setting application/config/relay_url, overridden by
## settings.cfg [game] relay_url or the environment variable TETRIS_RELAY
## (tests: ws://127.0.0.1:8765).
static func relay_url() -> String:
	var cfg := ConfigFile.new()
	var u := OS.get_environment("TETRIS_RELAY")      # tools/vstest.gd
	if u == "" and cfg.load("user://settings.cfg") == OK:
		u = str(cfg.get_value("game", "relay_url", ""))
	if u == "":
		u = str(ProjectSettings.get_setting("application/config/relay_url", ""))
	return u

## A typed code: upper case, look-alike digits to the letters the relay uses.
static func clean_code(s: String) -> String:
	var out := ""
	var map := {"5": "S", "2": "Z", "8": "B", "6": "G", "0": "O", "1": "I"}
	for ch in s.strip_edges().to_upper():
		out += map.get(ch, ch)
	return out

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

func host_online(url: String) -> int:
	is_host = true
	return _open(url, {"op": "host", "g": GAME, "v": version()})

func join_online(url: String, code: String) -> int:
	is_host = false
	return _open(url, {"op": "join", "g": GAME, "code": clean_code(code), "v": version()})

func _open(url: String, hello: Dictionary) -> int:
	if url == "":
		return ERR_UNCONFIGURED
	_url = url
	_hello = hello
	_ws_open = false
	ws = WebSocketPeer.new()
	return ws.connect_to_url(url)

## Pumps the socket. Events: ["room", code], ["connect"], ["disconnect"],
## ["error", text], ["closed", text], ["msg", type, payload].
func poll() -> Array:
	var out := []
	if ws == null:
		return out
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _ws_open:
		_ws_open = true
		ws.send_text(JSON.stringify(_hello))
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		if ws.was_string_packet():
			var m = JSON.parse_string(pkt.get_string_from_utf8())
			if not (m is Dictionary):
				continue
			match str(m.get("op", "")):
				"room":
					room_code = str(m.get("code", ""))
					out.append(["room", room_code])
				"joined":
					connected = true
					out.append(["connect"])
				"left":
					connected = false
					out.append(["disconnect"])
				"error":
					out.append(["error", str(m.get("msg", "error"))])
		else:
			var msg = bytes_to_var(pkt)
			if msg is Array and msg.size() == 2:
				out.append(["msg", msg[0], msg[1]])
	if st == WebSocketPeer.STATE_CLOSED and not _ws_open and _tries + 1 < TRIES:
		_tries += 1
		_open(_url, _hello)               # never reached the server: again
		return out
	if st == WebSocketPeer.STATE_CLOSED:
		var why := ws.get_close_reason()
		ws = null
		connected = false
		out.append(["closed", why if why != "" else ("No connection to the online server." if not _ws_open \
			else "The connection to the online server was lost.")])
	return out

func send(type: String, payload) -> void:
	if ws and connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(var_to_bytes([type, payload]))

func close() -> void:
	if ws:
		ws.poll()                         # hand queued messages ("bye") to the socket first
		ws.close()
		ws.poll()
	ws = null
	connected = false
