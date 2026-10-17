extends Node

signal match_started(is_host: bool)
signal player_data_updated(peer_id: int)
signal phase_complete(next_scene_path: String)

const PORT = 54321	# TODO: Confirm this port later on.
@export var target_ip: String = "127.0.0.1" # TODO: This is set to localhost for now

var _peer = ENetMultiplayerPeer.new()

# The central data blob. Keys are peer IDs (1 for host, dynamically generated for client).
# Values are dictionaries holding the player's current state and choices.
var session_data: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# --- BLIND LAN HANDSHAKE ---

func start_lan_match() -> void:
	print("Attempting to connect as client...")
	var err = _peer.create_client(target_ip, PORT)
	
	if err != OK:
		_host_match()
		return
		
	multiplayer.multiplayer_peer = _peer
	
	# Wait 1.5 seconds. If we are still "connecting", the host doesn't exist yet.
	await get_tree().create_timer(1.5).timeout
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		print("Client connection timed out. Pivoting to host.")
		multiplayer.multiplayer_peer = null
		_peer.close()
		_host_match()

func _host_match() -> void:
	print("Starting local server...")
	_peer.create_server(PORT, 2) # Limit to 2 players max
	multiplayer.multiplayer_peer = _peer
	_initialise_player_data(1)
	match_started.emit(true)

func _on_connected_to_server() -> void:
	print("Successfully joined host!")
	_initialise_player_data(multiplayer.get_unique_id())
	match_started.emit(false)

func _on_connection_failed() -> void:
	print("Connection failed. Pivoting to host.")
	multiplayer.multiplayer_peer = null
	_host_match()

func _on_peer_connected(id: int) -> void:
	print("Peer %d connected." % id)
	_initialise_player_data(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer %d disconnected." % id)
	session_data.erase(id)

# --- SESSION STATE INITIALISATION ---

func _initialise_player_data(peer_id: int) -> void:
	if not session_data.has(peer_id):
		session_data[peer_id] = {
			"character_id": "",
			"move_names": PackedStringArray(),
			"is_ready": false
		}
	player_data_updated.emit(peer_id)

# --- BEGINNER-FRIENDLY API WRAPPERS ---
# Team members call these standard functions, which safely route to the RPCs.

func submit_character(char_id: String) -> void:
	rpc("_rpc_update_character", char_id)

func submit_moves(moves: PackedStringArray) -> void:
	rpc("_rpc_update_moves", moves)

func set_ready(ready_state: bool) -> void:
	rpc("_rpc_set_ready", ready_state)

# --- RPC CONTRACTS & SYNCHRONISATION ---

@rpc("any_peer", "call_local", "reliable")
func _rpc_update_character(char_id: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	session_data[sender_id]["character_id"] = char_id
	player_data_updated.emit(sender_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_update_moves(moves: PackedStringArray) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	session_data[sender_id]["move_names"] = moves
	player_data_updated.emit(sender_id)

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_ready(ready_state: bool) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	session_data[sender_id]["is_ready"] = ready_state
	player_data_updated.emit(sender_id)
	
	_check_phase_completion()

func _check_phase_completion() -> void:
	# Only the host dictates scene transitions to prevent race conditions
	if not multiplayer.is_server():
		return
		
	if session_data.size() < 2:
		return
		
	var all_ready = true
	for peer_id in session_data.keys():
		if not session_data[peer_id]["is_ready"]:
			all_ready = false
			break
			
	if all_ready:
		# Reset readiness for the next phase
		for peer_id in session_data.keys():
			session_data[peer_id]["is_ready"] = false
		
		# Define your scene flow here based on current state
		var next_scene = ""
		if session_data[1]["character_id"] == "":
			next_scene = "res://scenes/CharacterSelect.tscn"
		elif session_data[1]["move_names"].size() == 0:
			next_scene = "res://scenes/MoveBinding.tscn"
		else:
			next_scene = "res://scenes/fight.tscn"
			
		rpc("_rpc_transition_scene", next_scene)

@rpc("authority", "call_local", "reliable")
func _rpc_transition_scene(scene_path: String) -> void:
	print("Transitioning both clients to: ", scene_path)
	phase_complete.emit(scene_path)
	get_tree().change_scene_to_file(scene_path)
