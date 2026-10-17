extends Node

@export var leftColour: Color = Color.PALE_VIOLET_RED
@export var rightColour: Color = Color.AQUAMARINE
@export var mainColour: Color = Color.DARK_ORANGE

#@export var movementSpeed: float = 1
#@export var scaleSpeed: float = 0.1
@export var movementTime: float = 0.5

@onready var characterDockLeft = $characterL
@onready var characterDockRight = $characterR
@onready var characterDockMain = $characterMain
@onready var characterDockOffScreenR = $characterOffScreenR
@onready var characterDockOffScreenL = $characterOffScreenL

var leftPos: Transform2D
var rightPos: Transform2D
var mainPos: Transform2D
var offScreenRPos: Transform2D
var offScreenLPos: Transform2D

var mainScale: Vector2 = Vector2(1,1)
var nonMainScale: Vector2 = Vector2(0.8,0.8)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	leftPos = characterDockLeft.get_transform()
	rightPos = characterDockRight.get_transform()
	mainPos = characterDockMain.get_transform()
	offScreenRPos = characterDockOffScreenR.get_transform()
	offScreenLPos = characterDockOffScreenL.get_transform()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if(Input.is_action_just_pressed("testRight")):
		_moveAllDocksRight()
	pass
	
func _moveAllDocksLeft():
	var lTween = get_tree().create_tween()
	var rTween = get_tree().create_tween()
	var offRTween = get_tree().create_tween()
	var mainTween = get_tree().create_tween()
	
	#if (_moveEachDock(characterDockLeft, lTween, nonMainScale, offScreenLPos.origin) && _moveEachDock(characterDockMain, mainTween, nonMainScale, leftPos.origin) && _moveEachDock(characterDockRight, rTween, mainScale, mainPos.origin) && _moveEachDock(characterDockOffScreenR, offRTween, nonMainScale, rightPos.origin)):
	#	_resetMove()
	pass
	
func _moveAllDocksRight():
	var lTween = get_tree().create_tween()
	var rTween = get_tree().create_tween()
	var offLTween = get_tree().create_tween()
	var mainTween = get_tree().create_tween()
	
	var lTweens = get_tree().create_tween()
	var rTweens = get_tree().create_tween()
	var offLTweens = get_tree().create_tween()
	var mainTweens = get_tree().create_tween()
	
	var moveL:bool = _moveEachDock(characterDockLeft, lTween, lTweens, mainScale, mainPos.origin)
	var moveR:bool = _moveEachDock(characterDockRight, rTween, rTweens, nonMainScale, offScreenRPos.origin)
	var moveMain:bool = _moveEachDock(characterDockMain, mainTween, mainTweens, nonMainScale, rightPos.origin)
	var moveOffL:bool = _moveEachDock(characterDockOffScreenL, offLTween, offLTweens, nonMainScale, leftPos.origin)
	
	if (moveL && moveR && moveMain && moveOffL):
		print(3)
		_resetMove()
	pass
	
func _moveEachDock(dock,tween:Tween,tweens:Tween,scale:Vector2,position:Vector2,):
	tween.tween_property(dock, "position", position, movementTime)
	tweens.tween_property(dock, "scale", scale, movementTime)
	#tween.tween_callback(dock.)
	
	if (tween.finished):
		return true
	return false
	
func _changeImage(characterDock):
	#	Put image change here when image, for now, colour change
	pass
	
func _resetMove():
	print("reset")
	_resetDocks(characterDockLeft,leftPos)
	_resetDocks(characterDockRight,rightPos)
	_resetDocks(characterDockMain,mainPos)
	_resetDocks(characterDockOffScreenR,offScreenRPos)
	_resetDocks(characterDockOffScreenL,offScreenLPos)
	pass
	
func _resetDocks(dockToReset,position:Transform2D):
	dockToReset.position = position.origin
	print(position.origin)
	dockToReset.scale = position.get_scale()
	print(position.get_scale())
	pass
