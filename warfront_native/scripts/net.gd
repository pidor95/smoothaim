extends Node
## PvP over the local network (same Wi-Fi or hotspot) with ENet. One phone hosts, the others join by
## picking it from the list (found by UDP broadcast) or by typing its IP address. Every player simulates
## their own vehicle; positions are exchanged 15 times a second and shots are sent as events, so each
## player takes damage from the projectiles they see — the same model as the browser version.

const D := preload("res://scripts/data.gd")
const PORT := 27015
const DISCOVERY_PORT := 27016
const MAGIC := "BOEVOY1"

signal status(text: String)
signal hosts_changed
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


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Не удалось подключиться"); close())
	multiplayer.server_disconnected.connect(func(): game.add_feed(null, null, "Связь с хостом потеряна"); close(); disconnected.emit())


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


func join(ip: String) -> void:
	close()
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip.strip_edges(), PORT) != OK:
		status.emit("Неверный адрес")
		return
	multiplayer.multiplayer_peer = p
	status.emit("Подключение к %s…" % ip)


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
		v.dead = true
		v.visible = false
	elif not dead and v.dead:
		v.dead = false
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
			if wname != "aam" and wname != "atgm":
				return
			game.spawn_missile(o, m["p"], m["d"], wname, tg if tg != null and not tg.dead else null)
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
				o.dead = true
				o.visible = false
				game.explosion(o.pos, 2.4)
			game.add_feed(a, o, str(m.get("w", "")))
			if a == game.player:
				game.kills += 1
