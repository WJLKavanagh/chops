extends Node

const CHARACTERS: Array[Dictionary] = [
	{
		"name": "William",
		"texture": preload("res://assets/fighters/william/1000041990.jpg")
	},
	{
		"name": "Gordon",
		"texture": preload("res://assets/fighter_actions/gordon/ATTACK_HIGH00216001.png")
	},
	{
		"name": "Morgan",
		"texture": preload("res://assets/fighter_actions/morgan/DODGE_HIGH00216002.png")
	}
]

var queuePointer:int = 0

@export var movementTime: float = 0.5

@onready var characterDockLeft = $characterL
@onready var characterDockRight = $characterR
@onready var characterDockMain = $characterMain
@onready var characterDockOffScreenR = $characterOffScreenR
@onready var characterDockOffScreenL = $characterOffScreenL

var dockList

var leftPos: Transform2D
var rightPos: Transform2D
var mainPos: Transform2D
var offScreenRPos: Transform2D
var offScreenLPos: Transform2D

var mainScale: Vector2 = Vector2(1,1)
var nonMainScale: Vector2 = Vector2(0.8,0.8)

var moving:bool = false

var commandDict = {
	"left": "left",
	"right": "right",
	"next": "right",
	"back":"left"
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	leftPos = characterDockLeft.get_transform()
	rightPos = characterDockRight.get_transform()
	mainPos = characterDockMain.get_transform()
	offScreenRPos = characterDockOffScreenR.get_transform()
	offScreenLPos = characterDockOffScreenL.get_transform()
	
	dockList = [characterDockOffScreenL, characterDockLeft, characterDockMain, characterDockRight, characterDockOffScreenR]
	
	_setup_character_panels()
	_changeImages()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if(Input.is_action_just_pressed("testRight")&&!moving):
		moving = true
		queuePointer-=1
		if queuePointer==-1:
			queuePointer = CHARACTERS.size()-1
		_moveAllDocksRight()
	elif (Input.is_action_just_pressed("testLeft")&&!moving):
		moving = true
		queuePointer+=1
		if queuePointer==CHARACTERS.size():
			queuePointer = 0
		_moveAllDocksLeft()
	
func _moveAllDocksLeft():
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(characterDockLeft, "position", offScreenLPos.origin, movementTime)
	tween.tween_property(characterDockLeft, "scale", nonMainScale, movementTime)

	tween.tween_property(characterDockMain, "position", leftPos.origin, movementTime)
	tween.tween_property(characterDockMain, "scale", nonMainScale, movementTime)

	tween.tween_property(characterDockRight, "position", mainPos.origin, movementTime)
	tween.tween_property(characterDockRight, "scale", mainScale, movementTime)

	tween.tween_property(characterDockOffScreenR, "position", rightPos.origin, movementTime)
	tween.tween_property(characterDockOffScreenR, "scale", nonMainScale, movementTime)

	await tween.finished
	print("Move finished")
	_resetMove()
	
func _moveAllDocksRight():
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(characterDockLeft, "position", mainPos.origin, movementTime)
	tween.tween_property(characterDockLeft, "scale", mainScale, movementTime)

	tween.tween_property(characterDockRight, "position", offScreenRPos.origin, movementTime)
	tween.tween_property(characterDockRight, "scale", nonMainScale, movementTime)

	tween.tween_property(characterDockMain, "position", rightPos.origin, movementTime)
	tween.tween_property(characterDockMain, "scale", nonMainScale, movementTime)

	tween.tween_property(characterDockOffScreenL, "position", leftPos.origin, movementTime)
	tween.tween_property(characterDockOffScreenL, "scale", nonMainScale, movementTime)

	await tween.finished
	print("Move finished")
	_resetMove()

func _moveEachDock(dock,tween:Tween,tweens:Tween,scale:Vector2,position:Vector2,):
	tween.tween_property(dock, "position", position, movementTime)
	tweens.tween_property(dock, "scale", scale, movementTime)
	
	if (tween.finished):
		return true
	return false
	
func _changeImages():
	for panel_index in range(dockList.size()):
		var character_index = posmod(queuePointer + panel_index - 2, CHARACTERS.size())
		var character = CHARACTERS[character_index]
		var dock = dockList[panel_index]
		dock.color = Color.WHITE
		dock.get_node("Portrait").texture = character["texture"]
		dock.get_node("Name").text = character["name"]

func _setup_character_panels() -> void:
	for dock in dockList:
		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_child(portrait)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.offset_top = -56.0
		name_label.offset_bottom = -8.0
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 32)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_child(name_label)
	
func _resetMove():
	print("reset")
	_resetDocks(characterDockLeft,leftPos)
	_resetDocks(characterDockRight,rightPos)
	_resetDocks(characterDockMain,mainPos)
	_resetDocks(characterDockOffScreenR,offScreenRPos)
	_resetDocks(characterDockOffScreenL,offScreenLPos)

	
func _resetDocks(dockToReset, position:Transform2D):
	print("resetting")
	dockToReset.position = position.origin
	dockToReset.scale = position.get_scale()
<<<<<<< HEAD
=======
	
	moving = false
	_changeImages()
>>>>>>> d57f54892a0bd06a87c150986f2b63b5637488de
