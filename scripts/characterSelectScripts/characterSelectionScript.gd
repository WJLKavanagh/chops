extends Node

@export var colourQueue = [Color.RED,Color.ORANGE,Color.YELLOW,Color.GREEN,Color.BLUE,Color.INDIGO,Color.VIOLET]
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
	
	_changeImages()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if(Input.is_action_just_pressed("testRight")&&!moving):
		moving = true
		queuePointer-=1
		if queuePointer==-1:
			queuePointer = colourQueue.size()-1
		_moveAllDocksRight()
	elif (Input.is_action_just_pressed("testLeft")&&!moving):
		moving = true
		queuePointer+=1
		if queuePointer==colourQueue.size():
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
	for a in range(0,5):
		var index = queuePointer+a
		if(index>=colourQueue.size()):
			index-=colourQueue.size()
		dockList[a].color = colourQueue[index]
	#	Put image change here when image, for now, colour change
	pass
	
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
	
	moving = false
	_changeImages()
