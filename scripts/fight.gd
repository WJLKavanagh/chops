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
		vm.connect("PhraseRecognised", Callable(self, "_on_phrase_recognised"))
		
		# Cast to PackedStringArray so C# marshals it correctly to string[]
		var grammar := PackedStringArray(move_dict.keys())
		vm.SetGrammar(grammar)
		
	start_match()

func start_match() -> void:
	
	p1_data = CharacterDB.get_fighter(CharacterDB.selected_p1)
	p2_data = CharacterDB.get_fighter(CharacterDB.selected_p2)
	p1_rounds = 0
	p2_rounds = 0
	start_round()

func start_round() -> void:
	p1_health = max_health
	p2_health = max_health
	p1_super = 0
	p2_super = 0
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

func _process(delta: float) -> void:
	if current_state == State.INPUT and not is_tts_prompting:
		time_remaining -= delta
		status_label.text = "Time: %.1f" % time_remaining
		
		if time_remaining <= 0:
			resolve_turn()

	p1_status_label.text = "HP: %d | SP: %d/%d" % [p1_health, p1_super, super_charge_req]
	p2_status_label.text = "HP: %d | SP: %d/%d" % [p2_health, p2_super, super_charge_req]
	
	

func _on_phrase_recognised(phrase: String) -> void:
	print("--- STT SIGNAL RECEIVED: '%s' ---" % phrase)
	
	if current_state != State.INPUT:
		print("Ignored: Not in INPUT phase.")
		return
		
	if move_dict.has(phrase):
		if move_dict[phrase] == Move.SUPER and p1_super < super_charge_req:
			tts.queue_text("Super not charged.", 1) #priority 1 to warn instant with tts
			print("Super move not charged.")
			return
			
		p1_move = move_dict[phrase]
		p1_action_label.text = "Locked In!"
		
		#Audio for locked
		tts.queue_text("Locked.", 1)
		
		print("Player selected: ", phrase)
	else:
		tts.queue_text("Unrecognised", 1)
		print("Ignored: '%s' is not in move dictionary." % phrase)

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

func resolve_turn() -> void:
	current_state = State.RESOLUTION
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StopListening()
		
	p2_move = generate_ai_move()
	
	p1_action_label.text = Move.keys()[p1_move]
	p2_action_label.text = Move.keys()[p2_move]
	
	#Health tracker
	var p1_start_hp = p1_health
	var p2_start_hp = p2_health
	
	
	evaluate_combat(p1_move, p2_move, true) 
	evaluate_combat(p2_move, p1_move, false)
	
	# Debug printing block 
	print("\n--- TURN RESOLUTION ---")
	print("Player 1 Move: %s" % Move.keys()[p1_move])
	print("Player 2 (AI) Move: %s" % Move.keys()[p2_move])
	print("Outcome -> Player 1: HP %d | SP %d/%d" % [p1_health, p1_super, super_charge_req])
	print("Outcome -> Player 2: HP %d | SP %d/%d" % [p2_health, p2_super, super_charge_req])
	print("-----------------------\n")
	
	update_ui()
	
	#TTS combat narrative
	if p1_move == Move.NONE:
			tts.queue_text("You did zilch.")
	else:
			tts.queue_text("You used" + get_move_name(p1_move) + ".")
	
	tts.queue_text("The enemy used " + get_move_name(p2_move) + ".")
	
	var p1_dmg_taken = p1_start_hp - p1_health
	var p2_dmg_taken = p2_start_hp - p2_health
	
	if p2_dmg_taken > 0:
		tts.queue_text("You hit the enemy for " + str(p2_dmg_taken) + "damage!")
	elif p1_move in [Move.HIGH_ATK, Move.LOW_ATK, Move.SUPER] and p2_dmg_taken == 0:
			tts.queue_text("Your attack was blocked, oh no.")
			
	if p1_dmg_taken > 0:
			tts.queue_text("You hit the enemy for " + str(p2_dmg_taken) + " Damage!")
	elif p2_move in [Move.HIGH_ATK, Move.LOW_ATK, Move.SUPER] and p1_dmg_taken == 0:
			tts.queue_text("You blocked, well done.")
			
	#Health state announcement
	if p1_health == 1:
		tts.queue_text("You have one health left")
		
	#Announcer narration when added to be stopped here
	
	await tts.tts_queue_finished
		
	check_round_end()

func evaluate_combat(atk_move: Move, def_move: Move, is_p1: bool) -> void:
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
			p1_super += 1 
		else: 
			p1_health -= damage
			p2_super += 1

func check_round_end() -> void:
	if p1_health <= 0 or p2_health <= 0:
		current_state = State.ROUND_OVER
		if p1_health <= 0 and p2_health <= 0:
			print("Draw!")
		elif p2_health <= 0:
			p1_rounds += 1
			print("Player 1 Wins Round!")
		else:
			p2_rounds += 1
			print("Player 2 Wins Round!")
			
		if p1_rounds >= 2 or p2_rounds >= 2:
			current_state = State.MATCH_OVER
			status_label.text = "MATCH OVER"
		else:
			await get_tree().create_timer(3.0).timeout
			start_round()
	else:
		await get_tree().create_timer(2.0).timeout
		start_input_phase()

func update_ui() -> void:
	p1_hp_label.text = "HP: %d" % p1_health
	p2_hp_label.text = "HP: %d" % p2_health
	p1_sm_label.text = "SP: %d/%d" % [p1_super, super_charge_req]
	p2_sm_label.text = "SP: %d/%d" % [p2_super, super_charge_req]
