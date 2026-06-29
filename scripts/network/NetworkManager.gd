extends Node
## NetworkManager — Autoload singleton that owns all networking state.
##
## Responsibilities:
##   * Host a local WiFi game server (ENet)
##   * Discover rooms via UDP broadcast
##   * Join a room as a client
##   * Relay RPC messages between host and clients
##   * Expose typed signals the rest of the game listens to
##
## The room discovery protocol is intentionally simple:
##   * Server broadcasts a heartbeat (room name + port) every 1s on 255.255.255.255:7778
##   * Clients listen on UDP port 7778 and surface discovered rooms via the
##     `room_discovered(room_info)` signal.
##
## For in-game traffic we use Godot's high-level multiplayer (ENet on port 7777).
## Host is authoritative for game state.

const DEFAULT_PORT: int = 7777
const DISCOVERY_PORT: int = 7778
const BROADCAST_INTERVAL: float = 1.0
const MAX_PLAYERS: int = 4

signal hosting_started(room_name: String, port: int)
signal hosting_failed(reason: String)
signal room_discovered(room_info: Dictionary)
signal room_lost(ip: String)
signal join_started(host_ip: String)
signal join_succeeded(peer_id: int)
signal join_failed(reason: String)
signal peer_joined(peer_id: int, player_name: String)
signal peer_left(peer_id: int)
signal connection_lost()
signal host_migrated()
signal game_message_received(from_peer: int, type: String, payload: Dictionary)

enum Role { NONE, HOST, CLIENT }

var role: Role = Role.NONE
var room_name: String = ""
var my_player_name: String = "Player"
var my_peer_id: int = 0
var connected_peers: Dictionary = {} # peer_id -> player_name

var _server_peer: ENetMultiplayerPeer
var _client_peer: ENetMultiplayerPeer
var _discovery_socket: PacketPeerUDP
var _broadcast_timer: Timer
var _listen_timer: Timer
var _known_rooms: Dictionary = {} # ip -> {name, port, last_seen}
var _room_lost_timer: Timer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_discovery_socket = PacketPeerUDP.new()
	_discovery_socket.set_broadcast_enabled(true)

	_broadcast_timer = Timer.new()
	_broadcast_timer.wait_time = BROADCAST_INTERVAL
	_broadcast_timer.one_shot = false
	_broadcast_timer.timeout.connect(_on_broadcast_tick)
	add_child(_broadcast_timer)

	_listen_timer = Timer.new()
	_listen_timer.wait_time = 0.25
	_listen_timer.one_shot = false
	_listen_timer.timeout.connect(_on_listen_tick)
	add_child(_listen_timer)

	_room_lost_timer = Timer.new()
	_room_lost_timer.wait_time = 2.0
	_room_lost_timer.one_shot = false
	_room_lost_timer.timeout.connect(_on_room_lost_tick)
	add_child(_room_lost_timer)

func _exit_tree() -> void:
	stop_hosting()
	stop_joining()
	_stop_discovery()

func start_hosting(p_room_name: String, p_player_name: String) -> bool:
	if role != Role.NONE:
		push_warning("[NetworkManager] start_hosting called while role is %s" % role)
		return false

	room_name = p_room_name
	my_player_name = p_player_name

	_server_peer = ENetMultiplayerPeer.new()
	var err := _server_peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		hosting_failed.emit("Could not bind port %d (err=%d)" % [DEFAULT_PORT, err])
		_server_peer = null
		return false

	multiplayer.multiplayer_peer = _server_peer
	role = Role.HOST
	my_peer_id = 1
	connected_peers[my_peer_id] = my_player_name

	_broadcast_timer.start()
	hosting_started.emit(room_name, DEFAULT_PORT)
	print("[NetworkManager] Hosting '%s' on port %d" % [room_name, DEFAULT_PORT])
	return true

func stop_hosting() -> void:
	if role != Role.HOST:
		return
	_broadcast_timer.stop()
	if _server_peer:
		_server_peer.close()
		_server_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	connected_peers.clear()
	host_migrated.emit()
	print("[NetworkManager] Stopped hosting")

func start_room_discovery() -> void:
	_stop_discovery()
	var err := _discovery_socket.bind(DISCOVERY_PORT)
	if err != OK and err != ERR_ALREADY_IN_USE:
		push_warning("[NetworkManager] Discovery bind failed: %d" % err)
		return
	_listen_timer.start()
	_room_lost_timer.start()
	print("[NetworkManager] Room discovery started on UDP %d" % DISCOVERY_PORT)

func stop_room_discovery() -> void:
	_stop_discovery()

func _stop_discovery() -> void:
	if _listen_timer:
		_listen_timer.stop()
	if _room_lost_timer:
		_room_lost_timer.stop()
	if _discovery_socket and _discovery_socket.is_bound():
		_discovery_socket.close()
	_known_rooms.clear()

func join_room(host_ip: String, p_player_name: String) -> bool:
	if role != Role.NONE:
		return false
	if host_ip.is_empty():
		join_failed.emit("Host IP is empty")
		return false

	my_player_name = p_player_name
	_client_peer = ENetMultiplayerPeer.new()
	var err := _client_peer.create_client(host_ip, DEFAULT_PORT)
	if err != OK:
		_client_peer = null
		join_failed.emit("create_client failed (err=%d)" % err)
		return false

	multiplayer.multiplayer_peer = _client_peer
	role = Role.CLIENT
	stop_room_discovery()
	join_started.emit(host_ip)
	print("[NetworkManager] Joining %s:%d" % [host_ip, DEFAULT_PORT])
	return true

func stop_joining() -> void:
	if role != Role.CLIENT:
		return
	if _client_peer:
		_client_peer.close()
		_client_peer = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	connected_peers.clear()
	print("[NetworkManager] Stopped joining")

func send_game_message(type: String, payload: Dictionary, target_peer: int = 0) -> void:
	var msg := {"type": type, "payload": payload, "from": my_peer_id}
	if role == Role.HOST:
		if target_peer == 0:
			for peer_id in connected_peers.keys():
				if peer_id == my_peer_id:
					continue
				_send_rpc_to(peer_id, msg)
			game_message_received.emit(my_peer_id, type, payload)
		else:
			_send_rpc_to(target_peer, msg)
	else:
		_send_rpc_to(1, msg)

func _send_rpc_to(target_peer: int, msg: Dictionary) -> void:
	rpc_id(target_peer, "_receive_game_message", msg)

@rpc("any_peer", "reliable", "call_remote")
func _receive_game_message(msg: Dictionary) -> void:
	var sender: int = int(msg.get("from", 0))
	var t: String = str(msg.get("type", ""))
	var payload: Dictionary = msg.get("payload", {})
	if role == Role.HOST:
		if not connected_peers.has(sender):
			connected_peers[sender] = "Player %d" % sender
			broadcast_player_list()
	game_message_received.emit(sender, t, payload)

func broadcast_player_list() -> void:
	if role != Role.HOST:
		return
	var list := {}
	for peer_id in connected_peers.keys():
		list[peer_id] = connected_peers[peer_id]
	for peer_id in connected_peers.keys():
		if peer_id == my_peer_id:
			continue
		rpc_id(peer_id, "_receive_player_list", list)

@rpc("authority", "reliable", "call_remote")
func _receive_player_list(list: Dictionary) -> void:
	connected_peers = list
	print("[NetworkManager] Player list updated: %s" % str(connected_peers))

func _on_peer_connected(peer_id: int) -> void:
	print("[NetworkManager] Peer connected: %d" % peer_id)
	if role == Role.HOST:
		connected_peers[peer_id] = "Player %d" % peer_id
		rpc_id(peer_id, "_receive_room_info", {"name": room_name, "you": peer_id})
		broadcast_player_list()
		peer_joined.emit(peer_id, connected_peers[peer_id])

func _on_peer_disconnected(peer_id: int) -> void:
	print("[NetworkManager] Peer disconnected: %d" % peer_id)
	connected_peers.erase(peer_id)
	if role == Role.HOST:
		broadcast_player_list()
	peer_left.emit(peer_id)

func _on_connected_to_server() -> void:
	my_peer_id = multiplayer.get_unique_id()
	connected_peers[1] = "Host"
	connected_peers[my_peer_id] = my_player_name
	rpc_id(1, "_receive_player_list", {my_peer_id: my_player_name})
	join_succeeded.emit(my_peer_id)

func _on_connection_failed() -> void:
	role = Role.NONE
	if _client_peer:
		_client_peer.close()
		_client_peer = null
	multiplayer.multiplayer_peer = null
	join_failed.emit("Connection failed — host not reachable")
	start_room_discovery()

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected")
	role = Role.NONE
	connected_peers.clear()
	if _client_peer:
		_client_peer.close()
		_client_peer = null
	multiplayer.multiplayer_peer = null
	connection_lost.emit()

func _on_broadcast_tick() -> void:
	if role != Role.HOST:
		return
	var packet := {
		"magic": "PARTYGAMES_V1",
		"name": room_name,
		"port": DEFAULT_PORT,
		"players": connected_peers.size(),
		"max": MAX_PLAYERS,
		"host_name": my_player_name,
	}
	var bytes := var_to_bytes(packet)
	_discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_socket.put_packet(bytes)

func _on_listen_tick() -> void:
	if not _discovery_socket.is_bound():
		return
	while _discovery_socket.get_available_packet_count() > 0:
		var bytes := _discovery_socket.get_packet()
		var sender_ip := _discovery_socket.get_packet_ip()
		var packet = bytes_to_var(bytes)
		if typeof(packet) != TYPE_DICTIONARY:
			continue
		if packet.get("magic") != "PARTYGAMES_V1":
			continue
		var info := {
			"name": packet.get("name", "Room"),
			"port": packet.get("port", DEFAULT_PORT),
			"players": packet.get("players", 0),
			"max": packet.get("max", MAX_PLAYERS),
			"host_name": packet.get("host_name", "Host"),
			"ip": sender_ip,
			"last_seen": Time.get_ticks_msec(),
		}
		var is_new := not _known_rooms.has(sender_ip)
		_known_rooms[sender_ip] = info
		if is_new:
			room_discovered.emit(info)

func _on_room_lost_tick() -> void:
	var now := Time.get_ticks_msec()
	var stale: Array[String] = []
	for ip in _known_rooms.keys():
		var info: Dictionary = _known_rooms[ip]
		if now - int(info.get("last_seen", 0)) > 3500:
			stale.append(ip)
	for ip in stale:
		_known_rooms.erase(ip)
		room_lost.emit(ip)

func get_local_ip() -> String:
	var addresses := IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	for addr in addresses:
		if not addr.begins_with("127."):
			return addr
	return "127.0.0.1"

func is_host() -> bool: return role == Role.HOST
func is_client() -> bool: return role == Role.CLIENT
func has_role() -> bool: return role != Role.NONE
func get_player_count() -> int: return connected_peers.size()