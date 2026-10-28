extends Node
## PvP with ENet, two ways: dedicated servers on the internet (a headless copy of the game started with
## "-- server", listed in servers.json) or a game hosted by one phone on the local Wi-Fi, found by UDP
## broadcast or typed in by IP. Servers answer a small UDP query with their name and player count. Every player simulates
## their own vehicle; positions are exchanged 15 times a second and shots are sent as events, so each
## player takes damage from the projectiles they see — the same model as the browser version.

const D := preload("res://scripts/data.gd")
const PORT := 27015
const DISCOVERY_PORT := 27016
const MAGIC := "BOEVOY1"

signal status(text: String)
signal hosts_changed
signal servers_changed
signal connected
signal disconnected

var game: Node
var active := false
var is_host := false
var hosts := {}                  # ip -> {"name": String, "seen": float}
var remotes := {}                # peer id -> vehicle
var net_state := {}              # peer id -> last received state
var _send_t := 0.0
var _udp := PacketPeerUDP.new()
var _listen := PacketPeerUDP.new()
var _bcast_t := 0.0
var _clock := 0.0
var dedicated := false            # this process is a headless server
var server_name := ""
var max_players := 10
var servers := {}                 # "host:port" -> {"name", "host", "port", "players", "max", "ping", "sent"}
var _query := PacketPeerUDP.new()
const LIST_URL := "https://raw.githubusercontent.com/pidor95/smoothaim/claude/military-vehicles-pvp-game-wm8y3e/warfront_native/servers.json"


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Не удалось подключиться"); close())
	multiplayer.server_disconnected.connect(func(): game.add_feed(null, null, "Связь с сервером потеряна"); close(); disconnected.emit())
	multiplayer.peer_connected.connect(func(id): if dedicated: print("player ", id, " joined, online ", players()))
	multiplayer.peer_disconnected.connect(func(id): if dedicated: print("player ", id, " left, online ", players()))


func my_id() -> int:
	return multiplayer.get_unique_id() if active else 0


static func local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


func host(nick: String) -> bool:
	close()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(PORT, 8) != OK:
		status.emit("Порт %d занят" % PORT)
		return false
	multiplayer.multiplayer_peer = p
	active = true
	is_host = true
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_bcast_name = nick
	status.emit("Сервер создан: " + ", ".join(local_ips()))
	return true


var _bcast_name := ""


func join(ip: String, port := PORT) -> void:
	close()
	ip = ip.strip_edges()
	if ip.contains(":"):
		port = int(ip.get_slice(":", 1))
		ip = ip.get_slice(":", 0)
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip, port) != OK:
		status.emit("Неверный адрес")
		return
	multiplayer.multiplayer_peer = p
	status.emit("Подключение к %s…" % ip)


# ---------------------------------------------------------------- dedicated server
## Headless relay server: no world, no vehicle of its own, just passes players' messages along.
func start_server(sname: String, port: int, maxp: int) -> bool:
	close()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(port, maxp) != OK:
		print("cannot open UDP port ", port)
		return false
	multiplayer.multiplayer_peer = p
	dedicated = true
	active = true
	is_host = true
	server_name = sname
	max_players = maxp
	_listen.bind(port + 1)
	print("server '%s' listening on UDP %d (queries on %d), max %d players" % [sname, port, port + 1, maxp])
	return true


func players() -> int:
	return multiplayer.get_peers().size() if active else 0


# ---------------------------------------------------------------- server list (client side)
## Load the bundled list, the custom entries from settings and the online list, then ask each server for its status.
func refresh_servers(custom: Array) -> void:
	var list: Array = []
	if FileAccess.file_exists("res://servers.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://servers.json"))
		if d is Dictionary and d.get("servers") is Array:
			list.append_array(d["servers"])
	for c in custom:
		var hp := str(c)
		list.append({"name": hp, "host": hp.get_slice(":", 0), "port": int(hp.get_slice(":", 1)) if hp.contains(":") else PORT})
	_merge(list)
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 8.0
	req.request_completed.connect(func(result, code, _h, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var d = JSON.parse_string(body.get_string_from_utf8())
			if d is Dictionary and d.get("servers") is Array:
				_merge(d["servers"])
		req.queue_free())
	req.request(LIST_URL)


func _merge(list: Array) -> void:
	if not _query.is_bound():
		_query.bind(0)
	for e in list:
		if not (e is Dictionary) or str(e.get("host", "")) == "":
			continue
		var host := str(e["host"])
		var port := int(e.get("port", PORT))
		var key := "%s:%d" % [host, port]
		if not servers.has(key):
			servers[key] = {"name": str(e.get("name", host)), "host": host, "port": port, "players": -1, "max": 0, "ping": -1, "sent": 0.0, "ip": ""}
		_ask(key)
	servers_changed.emit()


func _ask(key: String) -> void:
	var s: Dictionary = servers[key]
	var ip: String = s["ip"]
	if ip == "":
		ip = s["host"] if s["host"].is_valid_ip_address() else IP.resolve_hostname(s["host"], IP.TYPE_IPV4)
		s["ip"] = ip
	if ip == "":
		return
	_query.set_dest_address(ip, int(s["port"]) + 1)
	_query.put_packet((MAGIC + "?").to_utf8_buffer())
	s["sent"] = _clock


func start_discovery() -> void:
	if not _listen.is_bound():
		_listen.bind(DISCOVERY_PORT)


func stop_discovery() -> void:
	_listen.close()


func close() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	is_host = false
	for id in remotes:
		_drop(id)
	remotes.clear()
	net_state.clear()


func _process(dt: float) -> void:
	_clock += dt
	if dedicated:
		while _listen.get_available_packet_count() > 0:
			var q := _listen.get_packet().get_string_from_utf8()
			if q == MAGIC + "?":
				_listen.set_dest_address(_listen.get_packet_ip(), _listen.get_packet_port())
				_listen.put_packet(("%s|%s|%d|%d" % [MAGIC, server_name, players(), max_players]).to_utf8_buffer())
		return
	if _query.is_bound():
		var got := false
		while _query.get_available_packet_count() > 0:
			var r := _query.get_packet().get_string_from_utf8().split("|")
			var ip := _query.get_packet_ip()
			if r.size() >= 4 and r[0] == MAGIC:
				for key in servers:
					var s: Dictionary = servers[key]
					if s["ip"] == ip:
						s["name"] = r[1]
						s["players"] = int(r[2])
						s["max"] = int(r[3])
						s["ping"] = int((_clock - s["sent"]) * 1000.0)
						got = true
		if got:
			servers_changed.emit()
	if is_host and active:
		_bcast_t -= dt
		if _bcast_t <= 0.0:
			_bcast_t = 1.0
			_udp.put_packet(("%s|%s" % [MAGIC, _bcast_name]).to_utf8_buffer())
	if _listen.is_bound():
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var pkt := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			if pkt.begins_with(MAGIC + "|"):
				changed = changed or not hosts.has(ip)
				hosts[ip] = {"name": pkt.substr(MAGIC.length() + 1), "seen": _clock}
		for ip in hosts.keys():
			if _clock - hosts[ip]["seen"] > 4.0:
				hosts.erase(ip)
				changed = true
		if changed:
			hosts_changed.emit()


func _on_connected() -> void:
	active = true
	is_host = false
	connected.emit()


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	_drop(id)


func _drop(id: int) -> void:
	if game == null:
		return
	if remotes.has(id):
		var v = remotes[id]
		if is_instance_valid(v):
			for m in game.missiles:
				if m["target"] == v:
					m["target"] = null
			game.vehicles.erase(v)
			v.queue_free()
		remotes.erase(id)
	net_state.erase(id)


# ---------------------------------------------------------------- sending
func tick(dt: float) -> void:
	var p = game.player
	if p == null:
		return
	for id in remotes:
		var v = remotes[id]
		var s: Dictionary = net_state.get(id, {})
		if v.dead or s.is_empty():
			continue
		v.remote_update(dt, _clock - float(s["at"]), s["p"], s["u"], s["q"])
		v.sync()
		# remote players' automatic guns fire locally so their bullets can hit us
		if s.get("f", false):
			v.inp["fire"] = true
			v.slot = int(s["s"])
			v.aim_dir = s["g"]
			game.remote_fire(v, dt)
	_send_t -= dt
	if _send_t > 0.0:
		return
	_send_t = 1.0 / 15.0
	var wname: String = p.weapon()
	var W: Dictionary = D.WEAP[wname]
	var firing: bool = p.inp["fire"] and W["auto"] and wname != "rkt" and wname != "flare" and p.ammo[p.slot] > 0
	_state.rpc({"n": p.nick, "v": p.type, "p": p.pos, "u": p.vel, "q": p.rot, "h": p.hp, "ty": p.turret_yaw, "gp": p.gun_pitch,
		"g": p.aim_dir, "s": p.slot, "f": firing, "d": p.dead, "k": game.kills})


func event(m: Dictionary) -> void:
	if active:
		_event.rpc(m)


# ---------------------------------------------------------------- receiving
@rpc("any_peer", "unreliable_ordered")
func _state(m: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if game == null or not game.playing or not (m.get("p") is Vector3) or not (m.get("q") is Basis):
		return
	var t: String = str(m.get("v", ""))
	if not D.TYPES.has(t):
		return
	var v = remotes.get(id)
	if v == null or v.type != t:
		if v != null:
			_drop(id)
		v = game.add_remote(t, id, str(m.get("n", "Игрок")).left(20))
		remotes[id] = v
		v.pos = m["p"]
		v.rot = m["q"]
	m["at"] = _clock
	net_state[id] = m
	v.nick = str(m.get("n", "Игрок")).left(20)
	v.hp = float(m.get("h", 100.0))
	v.turret_yaw = float(m.get("ty", 0.0))
	v.gun_pitch = float(m.get("gp", 0.0))
	v.kills = int(m.get("k", 0))
	var dead: bool = m.get("d", false)
	if dead and not v.dead:
		game.remote_destroyed(v)
	elif not dead and v.dead:
		v.dead = false
		v.end_wreck()
		v.visible = true
		v.pos = m["p"]
		v.rot = m["q"]


@rpc("any_peer", "reliable")
func _event(m: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if game == null or not game.playing:
		return
	var o = remotes.get(id)
	match str(m.get("t", "")):
		"m":
			if o == null or not (m.get("p") is Vector3) or not (m.get("d") is Vector3):
				return
			var tid := int(m.get("tid", -1))
			var tg = null
			if tid == my_id():
				tg = game.player
			elif remotes.has(tid):
				tg = remotes[tid]
			var wname := str(m.get("w", "aam"))
			if not D.WEAP.has(wname) or not D.WEAP[wname].get("homing", false):
				return
			game.spawn_missile(o, m["p"], m["d"], wname, tg if tg != null and not tg.dead else null, m.get("ap") if m.get("ap") is Vector3 else null)
		"b":
			var bw := str(m.get("w", ""))
			if o and (bw == "fab250" or bw == "fab500") and m.get("p") is Vector3 and m.get("u") is Vector3:
				game.spawn_bomb(o, m["p"], m["u"], bw)
		"r":
			if o and m.get("p") is Vector3 and m.get("d") is Vector3:
				game.spawn_rocket(o, m["p"], m["d"])
		"c":
			if o and m.get("p") is Vector3 and m.get("d") is Vector3:
				game.remote_cannon(o, m["p"], m["d"])
		"fl":
			if o:
				game.drop_flares(o)
		"sm":
			if o and m.get("p") is Vector3:
				game.deploy_smoke(o, m["p"])
		"l":
			if int(m.get("tid", 0)) == my_id():
				game.lock_warn_t = 0.7
		"k":
			if o == null:
				return
			var kid := int(m.get("killer", 0))
			var a = game.player if kid == my_id() else remotes.get(kid)
			if not o.dead:
				game.remote_destroyed(o)
			game.add_feed(a, o, str(m.get("w", "")))
			if a == game.player:
				game.kills += 1
