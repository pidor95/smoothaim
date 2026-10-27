extends Node
## Multiplayer over the local network (same Wi-Fi). One pilot hosts, the others
## join: found automatically by a UDP broadcast, or by typing the host's address.
## Every pilot sends its drone state about 20 times a second; everyone draws the
## others. Phones and PCs can play together.

signal status_changed
signal lap_announced(text: String)

const GAME_PORT := 47800
const DISCOVERY_PORT := 47801
const MAGIC := "DOLINAFPV1"
const SEND_INTERVAL := 0.05
const RemoteScript := preload("res://scripts/remote_drone.gd")

var status := "Не в сети"
## Found games: ip -> {"name": String, "players": int, "seen": float}
var hosts := {}
## Other pilots: peer id -> remote drone node
var pilots := {}

# Filled by the game every frame.
var local_pos := Vector3.ZERO
var local_rot := Quaternion.IDENTITY
var local_type := 0
var local_gate := 0
var local_flying := false

var _peer: ENetMultiplayerPeer
var _broadcast := PacketPeerUDP.new()
var _listen := PacketPeerUDP.new()
var _listening := false
var _send_t := 0.0
var _beacon_t := 0.0
var _time := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_closed)


func _on_connected() -> void:
	_set_status("Подключено! Жми «Летать».")


func _on_connection_failed() -> void:
	leave()
	_set_status("Не удалось подключиться. Проверь адрес и что вы в одной Wi-Fi сети.")


func _on_server_closed() -> void:
	leave()
	_set_status("Хост закрыл игру")


func is_online() -> bool:
	return _peer != null


func is_connected_to_game() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host() -> void:
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(GAME_PORT, 8) != OK:
		_peer = null
		_set_status("Не удалось создать игру: порт %d занят" % GAME_PORT)
		return
	multiplayer.multiplayer_peer = _peer
	_broadcast = PacketPeerUDP.new()
	_broadcast.set_broadcast_enabled(true)
	_broadcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	var ips := local_ips()
	_set_status("Игра создана. Адрес для друзей: %s" % (", ".join(ips) if not ips.is_empty() else "нет Wi-Fi"))


func join(address: String) -> void:
	address = address.strip_edges()
	if address == "":
		_set_status("Введи адрес хоста, например 192.168.0.5")
		return
	leave()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(address, GAME_PORT) != OK:
		_peer = null
		_set_status("Неверный адрес: %s" % address)
		return
	multiplayer.multiplayer_peer = _peer
	_set_status("Подключение к %s…" % address)


func leave() -> void:
	for id: int in pilots.keys():
		_on_peer_disconnected(id)
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_broadcast.close()
	_set_status("Не в сети")


func start_discovery() -> void:
	if not _listening:
		_listening = _listen.bind(DISCOVERY_PORT) == OK


func stop_discovery() -> void:
	_listen.close()
	_listening = false
	hosts.clear()


func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out


## Names and gate progress of everyone in the game, for the HUD.
func scoreboard() -> PackedStringArray:
	var lines := PackedStringArray()
	if not is_connected_to_game():
		return lines
	lines.append("%s · ворота %d" % [Settings.player_name, local_gate + 1])
	for id: int in pilots:
		var r: RemoteScript = pilots[id]
		if r.pilot_name != "":
			lines.append("%s · ворота %d" % [r.pilot_name, r.gate + 1])
	return lines


func announce_lap(time: float, record: bool) -> void:
	if is_connected_to_game():
		_lap.rpc(Settings.player_name, time, record)


func _process(delta: float) -> void:
	_time += delta
	if _peer != null and multiplayer.is_server():
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "%s|%s|%d" % [MAGIC, Settings.player_name.replace("|", " "), pilots.size() + 1]
			_broadcast.put_packet(msg.to_utf8_buffer())
	if _listening:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var data := _listen.get_packet().get_string_from_utf8()
			var ip := _listen.get_packet_ip()
			var parts := data.split("|")
			if parts.size() == 3 and parts[0] == MAGIC:
				if not hosts.has(ip):
					changed = true
				hosts[ip] = {"name": parts[1], "players": parts[2].to_int(), "seen": _time}
		for ip: String in hosts.keys():
			if _time - float(hosts[ip]["seen"]) > 4.0:
				hosts.erase(ip)
				changed = true
		if changed:
			status_changed.emit()
	if is_connected_to_game():
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = SEND_INTERVAL
			_state.rpc(local_pos, local_rot, local_type, local_gate, local_flying, Settings.player_name)


@rpc("any_peer", "unreliable_ordered")
func _state(pos: Vector3, rot: Quaternion, type: int, gate: int, flying: bool, pilot_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not pilots.has(id):
		_on_peer_connected(id)
	var r: RemoteScript = pilots[id]
	r.apply_state(pos, rot, type, flying, pilot_name.substr(0, 20), gate)


@rpc("any_peer", "reliable")
func _lap(pilot_name: String, time: float, record: bool) -> void:
	var minutes := int(time / 60.0)
	var text := "%s: круг %02d:%05.2f" % [pilot_name.substr(0, 20), minutes, time - minutes * 60.0]
	if record:
		text += " · рекорд!"
	lap_announced.emit(text)


func _on_peer_connected(id: int) -> void:
	if pilots.has(id):
		return
	var r := RemoteScript.new()
	r.name = "Pilot%d" % id
	add_child(r)
	pilots[id] = r
	_set_status("В игре пилотов: %d" % (pilots.size() + 1))


func _on_peer_disconnected(id: int) -> void:
	if not pilots.has(id):
		return
	var r: RemoteScript = pilots[id]
	pilots.erase(id)
	r.queue_free()
	if _peer != null:
		_set_status("В игре пилотов: %d" % (pilots.size() + 1))


func _set_status(text: String) -> void:
	status = text
	status_changed.emit()
