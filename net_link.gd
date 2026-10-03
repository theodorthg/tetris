class_name NetLink
extends RefCounted

## Online versus (v1.1): a WebSocket to the relay that the series shares
## (mario-clone/server/relay.js on broesel.net). One player opens a room and
## gets a 4-letter code, the other joins with it; from then on the relay
## passes the binary messages between the two. Taken over from mario-clone's
## NetLink. Works in the browser too.
## v1.2 LAN / Wi-Fi (no server): ENet (UDP) like mario-clone's Wi-Fi co-op,
## on the SAME ports (so a PC firewall rule made for mario-clone covers
## tetris too) but its own discovery tag, so Mario hosts never show up here.
## Native builds only — a browser can't do UDP.
## Control frames from the relay are JSON text (room, joined, left, error);
## game messages are binary frames: var_to_bytes([type, payload]).

const GAME := "tetris"            ## the relay keeps rooms of different games apart
const PORT := 47111               ## LAN game port (ENet)
const DISCOVERY_PORT := 47110     ## the host listens here for "FIND"
const GUEST_PORT := 47112         ## the guest listens here for beacons
const MAGIC := "TETRIS-LAN-1"
## no digits that look like letters (5/S, 2/Z, 8/B, 6/G, 0/O, 1/I)
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ3479"

var ws: WebSocketPeer
var enet: ENetConnection          ## LAN instead of the relay
var peer: ENetPacketPeer          ## guest: the host; host: the one guest
var ever_connected := false
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
	if enet:
		return _poll_enet()
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
					ever_connected = true
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
	if enet:
		if connected and peer:
			peer.send(0, var_to_bytes([type, payload]), ENetPacketPeer.FLAG_RELIABLE)
		return
	if ws and connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(var_to_bytes([type, payload]))

# --- LAN (ENet) -------------------------------------------------------------

func host_lan() -> int:
	is_host = true
	enet = ENetConnection.new()
	return enet.create_host_bound("*", PORT, 1, 1)

func join_lan(ip: String) -> int:
	is_host = false
	enet = ENetConnection.new()
	var err := enet.create_host(1, 1)
	if err != OK:
		return err
	peer = enet.connect_to_host(ip.strip_edges(), PORT, 1)
	if peer:
		peer.set_timeout(0, 4000, 8000)    # no answer -> "disconnect" after ~8 s
	return OK if peer else ERR_CANT_CONNECT

func _poll_enet() -> Array:
	var out := []
	while enet:
		var ev: Array = enet.service(0)
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var p: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				if is_host and connected and p != peer:
					p.peer_disconnect()            # one opponent only
					continue
				peer = p
				peer.set_timeout(0, 4000, 8000)
				connected = true
				ever_connected = true
				out.append(["connect"])
			ENetConnection.EVENT_DISCONNECT:
				if p == peer:
					connected = false
					peer = null
					out.append(["disconnect"])
			ENetConnection.EVENT_RECEIVE:
				var raw := p.get_packet()
				if p != peer:
					continue
				var m = bytes_to_var(raw)
				if m is Array and m.size() == 2:
					out.append(["msg", m[0], m[1]])
	return out

## This device's addresses in the local network (shown on the host).
static func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if (a.begins_with("192.168.") and not a.begins_with("192.168.122.")) or a.begins_with("10."):
			out.append(a)
	return out

static func lan_possible() -> bool:
	return not OS.has_feature("web")

static func device_name() -> String:
	var n := OS.get_model_name()
	if n == "" or n == "GenericDevice":
		n = OS.get_environment("HOSTNAME")
	if n == "":
		n = {"Windows": "Windows PC", "Linux": "Linux PC", "macOS": "Mac"}.get(OS.get_name(), "PC")
	return n

func close() -> void:
	if enet:
		if peer and connected:
			enet.flush()                  # peer_disconnect() drops what is still queued
			peer.peer_disconnect_later()
			enet.flush()
		enet.destroy()
		enet = null
		peer = null
		connected = false
		return
	if ws:
		ws.poll()                         # hand queued messages ("bye") to the socket first
		ws.close()
		ws.poll()
	ws = null
	connected = false


## Finding hosts in the local network (from mario-clone v1.8/v1.9.5): the
## host listens on DISCOVERY_PORT and broadcasts a beacon to GUEST_PORT every
## second; the guest listens on GUEST_PORT and broadcasts "FIND", which the
## host answers directly. A guest PC with a firewall drops the beacon and the
## answer to a broadcast — so the guest also asks every address of its /24
## network directly (in a thread: a full neighbour table makes single sends
## block for seconds); answers to a direct question pass any stateful
## firewall. The guest never needs a port rule, the host does.
class Discovery:
	var udp := PacketPeerUDP.new()
	var hosting := false
	var host_name := ""
	var _t := 0.0
	## guest: ip -> {name, seen (msec)}
	var found := {}
	var _sweep_t := 0
	var _thread: Thread
	var _mutex := Mutex.new()
	var _swept := {}
	var _stop := false
	static var _lingering: Array = []

	func start_host(name: String) -> int:
		hosting = true
		host_name = name
		udp.set_broadcast_enabled(true)
		return udp.bind(DISCOVERY_PORT)

	func start_search() -> int:
		hosting = false
		udp.set_broadcast_enabled(true)
		return udp.bind(GUEST_PORT)

	func poll(delta: float) -> void:
		_t -= delta
		if _t <= 0.0:
			_t = 1.0
			if hosting:
				_send_to("255.255.255.255", GUEST_PORT, "HOST|" + host_name)
			else:
				_send_to("255.255.255.255", DISCOVERY_PORT, "FIND")
				_send_to("127.0.0.1", DISCOVERY_PORT, "FIND")     # same device (tests)
				_sweep_t -= 1
				if _sweep_t <= 0 and (_thread == null or not _thread.is_alive()):
					_sweep_t = 5
					_sweep()
		_merge_sweep()
		while udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet()
			var ip := udp.get_packet_ip()
			var port := udp.get_packet_port()
			var txt := pkt.get_string_from_utf8()
			if not txt.begins_with(MAGIC + "|"):
				continue
			var body := txt.substr(MAGIC.length() + 1)
			if hosting and body == "FIND":
				_send_to(ip, port, "HOST|" + host_name)
			elif not hosting and body.begins_with("HOST|"):
				found[ip] = {"name": body.substr(5), "seen": Time.get_ticks_msec()}
		for ip in found.keys():
			if Time.get_ticks_msec() - int(found[ip].seen) > 12000:
				found.erase(ip)

	func _sweep() -> void:
		var targets := []
		for mine in NetLink.local_ips():
			var p: PackedStringArray = str(mine).split(".")
			var net := "%s.%s.%s." % [p[0], p[1], p[2]]
			for i in range(1, 255):
				if str(i) != p[3]:
					targets.append(net + str(i))
		if targets.is_empty():
			return
		if _thread and not _thread.is_alive():
			_thread.wait_to_finish()
		_thread = Thread.new()
		_thread.start(_sweep_worker.bind(targets))

	func _sweep_worker(targets: Array) -> void:
		var sock := PacketPeerUDP.new()
		if sock.bind(0) != OK:
			return
		var msg := (MAGIC + "|FIND").to_utf8_buffer()
		for ip in targets:
			if _stop:
				break
			sock.set_dest_address(ip, DISCOVERY_PORT)
			sock.put_packet(msg)
			_drain(sock)
		var until := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < until and not _stop:
			_drain(sock)
			OS.delay_msec(20)
		sock.close()

	func _drain(sock: PacketPeerUDP) -> void:
		while sock.get_available_packet_count() > 0:
			var txt := sock.get_packet().get_string_from_utf8()
			if txt.begins_with(MAGIC + "|HOST|"):
				_mutex.lock()
				_swept[sock.get_packet_ip()] = txt.substr(MAGIC.length() + 6)
				_mutex.unlock()

	func _merge_sweep() -> void:
		_mutex.lock()
		for ip in _swept:
			found[ip] = {"name": _swept[ip], "seen": Time.get_ticks_msec()}
		_swept.clear()
		_mutex.unlock()
		for t in _lingering.duplicate():
			if not t.is_alive():
				t.wait_to_finish()
				_lingering.erase(t)

	func _send_to(ip: String, port: int, body: String) -> void:
		udp.set_dest_address(ip, port)
		udp.put_packet((MAGIC + "|" + body).to_utf8_buffer())

	func stop() -> void:
		udp.close()
		_stop = true
		if _thread:
			if _thread.is_alive():
				_lingering.append(_thread)
			else:
				_thread.wait_to_finish()
			_thread = null
