extends Resource
class_name FighterData

@export var character_name: String = "Unknown Fighter"

@export_group("Combat Stats")
@export var max_health: int = 5
@export var super_charge_req: int = 3
@export var base_damage: int = 1
@export var super_damage: int = 5

@export_group("TTS Move Descriptions")
@export var desc_idle: String = "Idle desc"
@export var desc_punch: String = "High attack desc"
@export var desc_kick: String = "Low attack desc"
@export var desc_jump: String = "Jump dodge desc"
@export var desc_duck: String = "Duck desc"
@export var desc_super: String = "unleashes superattack"

#Helper function for combat manager asking the resources
func get_move_text(move_enum: int) -> String:
	
	match move_enum:
		0: return desc_idle # Move Idle
		1: return desc_punch
		2: return desc_kick
		3: return desc_jump
		4: return desc_duck
		5: return desc_super
	return "Unknown"



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
