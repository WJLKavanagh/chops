extends Node2D

enum Move { NONE, HIGH_ATK, LOW_ATK, HIGH_BLK, LOW_BLK, SUPER }
enum State { IDLE, INPUT, RESOLUTION, ROUND_OVER, MATCH_OVER }

@export_group("Gameplay Constants")
@export var max_health: int = 5
@export var super_charge_req: int = 3
@export var super_damage: int = 5 
@export var base_damage: int = 1
@export var turn_time_seconds: float = 5.0

@onready var status_label = $UI/StatusLabel
@onready var p1_hp_label = $UI/LeftHPLabel
@onready var p2_hp_label = $UI/RightHPLabel
@onready var p1_sm_label = $UI/LeftSMLabel
@onready var p2_sm_label = $UI/RightSMLabel
@onready var p1_action_label = $Arena/FighterLeft/Label
@onready var p2_action_label = $Arena/FighterRight/Label
@onready var p1_status_label = $Arena/FighterLeft/HealthAndCharge
@onready var p2_status_label = $Arena/FighterRight/HealthAndCharge
@onready var p1_sprite = $Arena/FighterLeft/Body
@onready var p2_sprite = $Arena/FighterRight/Body

#TTS Autoloader connection, YAY!
@onready var tts = get_node("/root/TTS_Manager")

var p1_health: int
var p2_health: int
var p1_data: FighterData
var p2_data: FighterData
var p1_super: int
var p2_super: int
var p1_rounds: int = 0
var p2_rounds: int = 0
var local_is_p1: bool = true

var p1_move: Move = Move.NONE
var p2_move: Move = Move.NONE
var current_state: State = State.IDLE
var time_remaining: float = 0.0
var is_tts_prompting: bool = false #Is TTS prompting/running? Stop loop timer.

var move_dict = {
	"punch": Move.HIGH_ATK,
	"kick": Move.LOW_ATK,
	"duck": Move.HIGH_BLK,
	"jump": Move.LOW_BLK,
	"super move": Move.SUPER
}

func _ready() -> void:
	randomize()
	if has_node("/root/VoiceManager"):
		var vm = get_node("/root/VoiceManager")
		
		# Connect using the exact PascalCase string emitted by C#
		if not vm.is_connected("PhraseRecognised", Callable(self, "_on_phrase_recognised")):
			vm.connect("PhraseRecognised", Callable(self, "_on_phrase_recognised"))
		if  not vm.PartialPhraseRecognised.is_connected(_on_partial_recognised):
			vm.PartialPhraseRecognised.connect(_on_partial_recognised)
			
		var grammar:= PackedStringArray(move_dict.keys())
		vm.SetGrammar(grammar)
		
		# Cast to PackedStringArray so C# marshals it correctly to string[]
		_configure_confirmed_move_grammar(vm)
		
	start_match()

func _configure_confirmed_move_grammar(voice_manager: Node) -> void:
	var peer_id := multiplayer.get_unique_id()
	if not NetworkManager.session_data.has(peer_id):
		push_error("Fight: No network session data for local peer %d." % peer_id)
		return

	var confirmed_names: PackedStringArray = NetworkManager.session_data[peer_id]["move_names"]
	var move_types: Array[int] = [Move.HIGH_ATK, Move.LOW_ATK, Move.HIGH_BLK, Move.LOW_BLK, Move.SUPER]
	if confirmed_names.size() != move_types.size():
		push_error("Fight: Expected five confirmed move names for local peer %d, received %d." % [peer_id, confirmed_names.size()])
		return

	move_dict.clear()
	var grammar := PackedStringArray()
	for index in range(move_types.size()):
		var move_name := confirmed_names[index].strip_edges().to_lower()
		if move_name.is_empty() or move_dict.has(move_name):
			push_error("Fight: Confirmed move names must be non-empty and unique.")
			return
		move_dict[move_name] = move_types[index]
		grammar.append(move_name)

	voice_manager.SetGrammar(grammar)
	print("Fight: Local move grammar loaded: ", grammar)

func start_match() -> void:
	#Checking who is local player before grabbing everything else
	local_is_p1 = (multiplayer.get_unique_id() == 1)
	p1_data = CharacterDB.get_fighter(CharacterDB.selected_p1)
	p2_data = CharacterDB.get_fighter(CharacterDB.selected_p2)
	
	if p1_data == null:
		p1_data = CharacterDB.get_fighter("morgan")
	if p2_data == null:
		p2_data = CharacterDB.get_fighter("cari")
	p1_rounds = 0
	p2_rounds = 0
	
	#Player 1 animations HOPEFULLY lmao
	if p1_data:
		var p1_name = p1_data.character_name.to_lower()
		var p1_path = "res://assets/fighters/%s/%s_frames.tres" % [p1_name, p1_name]
		if ResourceLoader.exists(p1_path):
			p1_sprite.sprite_frames = load(p1_path)
			
			p1_sprite.play("idle")
	if p2_data:
		var p2_name = p2_data.character_name.to_lower()
		var p2_path = "res://assets/fighters/%s/%s_frames.tres" % [p2_name, p2_name]
		if ResourceLoader.exists(p2_path):
			p2_sprite.sprite_frames = load(p2_path)
			
			p2_sprite.play("idle")
		
			
	if p1_data and p2_data:
		TTS_Manager.queue_text("Match Start." + p1_data.character_name + " versus " + p2_data.character_name + ".", 1)
	TTS_Manager.queue_text("Round start, Fight!")
	start_round()

func start_round() -> void:
	p1_health = max_health
	p2_health = max_health
	p1_super = 0
	p2_super = 0
	
	if tts.is_speaking:
		await tts.tts_queue_finished
		
	start_input_phase()

func start_input_phase() -> void:
	current_state = State.INPUT
	p1_move = Move.NONE
	p2_move = Move.NONE
	time_remaining = turn_time_seconds
	
	p1_action_label.text = "Listening..."
	p2_action_label.text = "Thinking..."
	update_ui()
	
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StartListening()
		
	if p1_sprite.sprite_frames: p1_sprite.play("idle")
	if p2_sprite.sprite_frames: p2_sprite.play("idle")

func _process(delta: float) -> void:
	if current_state == State.INPUT and not is_tts_prompting:
		time_remaining -= delta
		status_label.text = "Time: %.1f" % time_remaining
		
		if time_remaining <= 0:
			current_state = State.RESOLUTION #Timer stopped safely
			
			if multiplayer.is_server():
				rpc("rpc_force_resolve", p1_move, p2_move)
				
			
		

	p1_status_label.text = "HP: %d | SP: %d/%d" % [p1_health, p1_super, super_charge_req]
	p2_status_label.text = "HP: %d | SP: %d/%d" % [p2_health, p2_super, super_charge_req]
	
@rpc("authority", "call_local", "reliable")
func rpc_force_resolve(host_p1_move: int, host_p2_move: int) -> void:
	
	#Host truth
	p1_move = host_p1_move as Move
	p2_move = host_p2_move as Move
	
	resolve_turn()

func _on_partial_recognised(phrase: String) -> void:
	if current_state != State.INPUT: return
	
	var sorted_keys = move_dict.keys().duplicate()
	sorted_keys.sort_custom(func(a, b): return a.length() > b.length())
	
	for key in sorted_keys:
		if key in phrase:
			_lock_in_move(key)
			return
	tts.queue_text("Unrecognised", 1)
			


func _on_phrase_recognised(phrase: String) -> void:
	print("--- STT SIGNAL RECEIVED: '%s' ---" % phrase)
	
	if current_state != State.INPUT:
		print("Ignored: Not in INPUT phase.")
		return
	
	var sorted_keys = move_dict.keys().duplicate()
	sorted_keys.sort_custom(func(a, b): return a.length() > b.length())
	
	for key in move_dict.keys():
		if key in phrase:
			_lock_in_move(key)
			return
		
	tts.queue_text("Unrecognised", 1)

func _lock_in_move(move_key: String) -> void:
	#Double lock impossible for mic
	var current_local_move = p1_move if local_is_p1 else p2_move
	if current_local_move != Move.NONE:
		return
		
	var selected_move = move_dict[move_key]
	var current_super = p1_super if local_is_p1 else p2_super
	
	if selected_move == Move.SUPER and current_super < super_charge_req:
		tts.queue_text("Super not charged.", 1)
		return
		
	if local_is_p1:
		p1_move = selected_move
		p1_action_label.text = "Locked in!"
		
	else:
		p2_move = selected_move
		p2_action_label.text = "Locked in!"
		
	rpc("rpc_sync_move", multiplayer.get_unique_id(), selected_move)
	tts.queue_text("Locked", 1)
	
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StopListening()
	
	
@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_move(peer_id: int, move_enum: int) -> void:
	if peer_id == 1:
		p1_move = move_enum as Move
	else:
		p2_move = move_enum as Move
	print("NetworkL recieved locked in from peer", peer_id)

func generate_ai_move() -> Move:
	if p2_super >= super_charge_req:
		return Move.SUPER
	return randi_range(1, 4) as Move
	
#function for turning enumns into the actual spoken player words
func get_move_name(move_enum: Move) -> String:
	match move_enum:
		Move.NONE: return "nothing"
		Move.HIGH_ATK: return "Punch"
		Move.LOW_ATK: return "Kick"
		Move.HIGH_BLK: return "Duck"
		Move.LOW_BLK: return "Jump"
		Move.SUPER: return "Supermove"
	return "Unknown Move"
	
func play_move_animation(sprite: AnimatedSprite2D, move: Move) -> void:
	if sprite.sprite_frames == null: return
	
	match move:
		Move.HIGH_ATK:
			sprite.play("attack_high")
		Move.LOW_ATK:
			sprite.play("attack_low")
		Move.SUPER:
			sprite.play("super_move")
		Move.HIGH_BLK:
			sprite.play("block_high")
		Move.LOW_BLK:
			sprite.play("block_low")
		_:
			sprite.play("idle")
			return
			
	await sprite.animation_finished
	sprite.play("idle")

func resolve_turn() -> void:
	current_state = State.RESOLUTION
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StopListening()
		
	#p2_move = generate_ai_move()
	
	p1_action_label.text = Move.keys()[p1_move]
	p2_action_label.text = Move.keys()[p2_move]
	
	#Health tracker
	var p1_start_hp = p1_health
	var p2_start_hp = p2_health
	
	
	evaluate_combat(p1_move, p2_move, true, p1_data) 
	evaluate_combat(p2_move, p1_move, false, p2_data)
	
	# Debug printing block 
	print("\n--- TURN RESOLUTION ---")
	print("Player 1 Move: %s" % Move.keys()[p1_move])
	print("Player 2 (AI) Move: %s" % Move.keys()[p2_move])
	print("Outcome -> Player 1: HP %d | SP %d/%d" % [p1_health, p1_super, super_charge_req])
	print("Outcome -> Player 2: HP %d | SP %d/%d" % [p2_health, p2_super, super_charge_req])
	print("-----------------------\n")
	
	update_ui()
	
	play_move_animation(p1_sprite, p1_move)
	play_move_animation(p2_sprite, p2_move)
	
	var p1_action_text = p1_data.get_move_text(p1_move)
	var p2_action_text = p2_data.get_move_text(p2_move)
	
	#Fix for us making sure this works over the network, hopefully will save William some work tomorrow
	if local_is_p1:
		tts.queue_text("You execute " + p1_action_text + ".")
		tts.queue_text("The enemy " + p2_action_text + ".")
	else:
		tts.queue_text("You execute " + p2_action_text + ".")
		tts.queue_text("The enemy " + p1_action_text + ".")
	
	#OLD TTS combat narrative, new narrative I have up above now
	#if p1_move == Move.NONE:
	#		tts.queue_text("You did zilch.")
	#else:
	#		tts.queue_text("You used" + get_move_name(p1_move) + ".")
	
	#tts.queue_text("The enemy used " + get_move_name(p2_move) + ".") 
	
	var p1_dmg_taken = p1_start_hp - p1_health
	var p2_dmg_taken = p2_start_hp - p2_health
	var local_dmg_taken = p1_dmg_taken if local_is_p1 else p2_dmg_taken
	var enemy_dmg_taken = p2_dmg_taken if local_is_p1 else p1_dmg_taken
	var local_move = p1_move if local_is_p1 else p2_move
	var enemy_move = p2_move if local_is_p1 else p1_move
	
	var local_health = p1_health if local_is_p1 else p2_health
	
	if enemy_dmg_taken > 0:
		tts.queue_text("You hit the enemy for " + str(enemy_dmg_taken) + "damage!")
	elif local_move in [Move.HIGH_ATK, Move.LOW_ATK, Move.SUPER] and enemy_dmg_taken == 0:
			tts.queue_text("Your attack was blocked, oh no.")
			
	if local_dmg_taken > 0:
			tts.queue_text("You were hit for " + str(local_dmg_taken) + " Damage!")
	elif enemy_move in [Move.HIGH_ATK, Move.LOW_ATK, Move.SUPER] and local_dmg_taken == 0:
			tts.queue_text("You blocked, well done.")
			
	#Health state announcement
	if local_health == 1:
		tts.queue_text("You have one health left")
		
	#Announcer narration when added to be stopped here
	
	await tts.tts_queue_finished
		
	check_round_end()

func evaluate_combat(atk_move: Move, def_move: Move, is_p1: bool, _attacker_data: FighterData) -> void:
	if atk_move == Move.NONE or atk_move == Move.HIGH_BLK or atk_move == Move.LOW_BLK:
		return
		
	var damage = 0
	var blocked = false
	
	if atk_move == Move.SUPER:
		damage = super_damage
		if is_p1: p1_super = 0 
		else: p2_super = 0
	elif atk_move == Move.HIGH_ATK:
		if def_move == Move.HIGH_BLK: blocked = true
		else: damage = base_damage
	elif atk_move == Move.LOW_ATK:
		if def_move == Move.LOW_BLK: blocked = true
		else: damage = base_damage
			
	if blocked:
		if is_p1: p2_super += 1
		else: p1_super += 1
	else:
		if is_p1: 
			p2_health -= damage
			
		else: 
			p1_health -= damage
			

func check_round_end() -> void:
	if p1_health <= 0 or p2_health <= 0:
		current_state = State.ROUND_OVER
		if p1_health <= 0 and p2_health <= 0:
			print("Draw!")
			tts.queue_text("Round Draw.")
		elif p2_health <= 0:
			p1_rounds += 1
			print("Player 1 Wins Round!")
			if local_is_p1: tts.queue_text("You won no way!!")
			else: tts.queue_text("Your enemy won! NOOOOOOOOO!")
		else:
			p2_rounds += 1
			print("Player 2 Wins Round!")
			if local_is_p1: tts.queue_text("The opponent won, arghhh!")
			else: tts.queue_text("You won! No wayyyyy")
			
		await tts.tts_queue_finished
			
		if p1_rounds >= 2 or p2_rounds >= 2:
			current_state = State.MATCH_OVER
			status_label.text = "MATCH OVER"
			end_match()
		else:
			await get_tree().create_timer(3.0).timeout
			start_round()
	else:
		await get_tree().create_timer(2.0).timeout
		start_input_phase()

func end_match() -> void:
	current_state = State.MATCH_OVER
	status_label.text = "MATCH OVER"
	
	#if has_node("/root/VoiceManager"):
		#get_node("/root/VoiceManager").StopListening()
		
	var local_won: bool = false
	if p1_rounds >= 2 and local_is_p1:
		local_won = true
	elif p2_rounds >= 2 and not local_is_p1:
		local_won = true
		
#Announcing result
	if local_won:
		tts.queue_text("Congratulations!! You won the match!", 1)
	else:
		tts.queue_text("Your reign of terror is over, defeated!", 1)
		
	await tts.tts_queue_finished
	
	await get_tree().create_timer(2.0).timeout
	
	multiplayer.multiplayer_peer = null
	
	get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")
	


func update_ui() -> void:
	p1_hp_label.text = "HP: %d" % p1_health
	p2_hp_label.text = "HP: %d" % p2_health
	p1_sm_label.text = "SP: %d/%d" % [p1_super, super_charge_req]
	p2_sm_label.text = "SP: %d/%d" % [p2_super, super_charge_req]
