extends Node

#preloading resource file for characters here so instantly ready in memory

var roster: Dictionary = {
	"Gordon": preload("res://Resources/Gordon.tres"),
}

#Character select screen variables

var selected_p1: String = "Player 1 pick"
var selected_p2: String = "Player 2 pick"

func get_fighter(fighter_name: String) -> FighterData: 
	var key = fighter_name.to_lower()
	if roster.has(key):
		return roster[key]
	return null
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
