extends Node2D

const CHARACTERS: Array[Dictionary] = [
	{
		"name": "Morgan",
		"texture": preload("res://assets/fighter_actions/morgan/processed/IDLE001.png")
	},
	{"name": "Cari", "texture": null},
	{
		"name": "Gordon",
		"texture": preload("res://assets/fighter_actions/gordon/processed/IDLE001.png")
	},
	{"name": "James", "texture": null},
	{"name": "Kelly", "texture": null},
	{"name": "Kay", "texture": null},
	{
		"name": "William",
		"texture": preload("res://assets/fighters/william/1000041990.jpg")
	}
]

const PLACEHOLDER_COLORS: Array[Color] = [
	Color(0.17, 0.32, 0.48),
	Color(0.39, 0.24, 0.42),
	Color(0.23, 0.37, 0.31)
]

@export var movementTime: float = 0.5

@onready var characterDockLeft: ColorRect = $characterL
@onready var characterDockRight: ColorRect = $characterR
@onready var characterDockMain: ColorRect = $characterMain
@onready var characterDockOffScreenR: ColorRect = $characterOffScreenR
@onready var characterDockOffScreenL: ColorRect = $characterOffScreenL
@onready var tts_manager: Node = get_node("/root/TTS_Manager")

var queuePointer: int = 0
var dockList: Array[ColorRect] = []
var moving: bool = false
var leftPos: Transform2D
var rightPos: Transform2D
var mainPos: Transform2D
var offScreenRPos: Transform2D
var offScreenLPos: Transform2D
var mainScale: Vector2
var nonMainScale: Vector2
var _announcement_id: int = 0
var _bark_player: AudioStreamPlayer

func _ready() -> void:
	tts_manager.set_listening_enabled(false)
	dockList = [
		characterDockOffScreenL,
		characterDockLeft,
		characterDockMain,
		characterDockRight,
		characterDockOffScreenR
	]
	leftPos = characterDockLeft.get_transform()
	rightPos = characterDockRight.get_transform()
	mainPos = characterDockMain.get_transform()
	offScreenRPos = characterDockOffScreenR.get_transform()
	offScreenLPos = characterDockOffScreenL.get_transform()
	mainScale = mainPos.get_scale()
	nonMainScale = leftPos.get_scale()
	_setup_character_panels()
	_changeImages()
	_announce_selection()

func _process(_delta: float) -> void:
	if moving:
		return

	if Input.is_action_just_pressed("testRight"):
		queuePointer = posmod(queuePointer - 1, CHARACTERS.size())
		_moveAllDocksRight()
	elif Input.is_action_just_pressed("testLeft"):
		queuePointer = posmod(queuePointer + 1, CHARACTERS.size())
		_moveAllDocksLeft()

func _setup_character_panels() -> void:
	for dock in dockList:
		dock.pivot_offset = dock.size * 0.5

		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_child(portrait)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.offset_top = -64.0
		name_label.offset_bottom = -8.0
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 40)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_child(name_label)

func _moveAllDocksLeft() -> void:
	moving = true
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
	_resetMove()

func _moveAllDocksRight() -> void:
	moving = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(characterDockLeft, "position", mainPos.origin, movementTime)
	tween.tween_property(characterDockLeft, "scale", mainScale, movementTime)
	tween.tween_property(characterDockMain, "position", rightPos.origin, movementTime)
	tween.tween_property(characterDockMain, "scale", nonMainScale, movementTime)
	tween.tween_property(characterDockRight, "position", offScreenRPos.origin, movementTime)
	tween.tween_property(characterDockRight, "scale", nonMainScale, movementTime)
	tween.tween_property(characterDockOffScreenL, "position", leftPos.origin, movementTime)
	tween.tween_property(characterDockOffScreenL, "scale", nonMainScale, movementTime)
	await tween.finished
	_resetMove()

func _changeImages() -> void:
	for slot in range(dockList.size()):
		var character_index := posmod(queuePointer + slot - 2, CHARACTERS.size())
		var character: Dictionary = CHARACTERS[character_index]
		var dock := dockList[slot]
		var portrait := dock.get_node("Portrait") as TextureRect
		portrait.texture = character["texture"]
		dock.color = Color.WHITE if portrait.texture != null else PLACEHOLDER_COLORS[character_index % PLACEHOLDER_COLORS.size()]
		dock.get_node("Name").text = character["name"]

func _resetMove() -> void:
	_resetDock(characterDockLeft, leftPos)
	_resetDock(characterDockRight, rightPos)
	_resetDock(characterDockMain, mainPos)
	_resetDock(characterDockOffScreenR, offScreenRPos)
	_resetDock(characterDockOffScreenL, offScreenLPos)
	moving = false
	_changeImages()
	_announce_selection()

func _resetDock(dock: ColorRect, dock_transform: Transform2D) -> void:
	dock.position = dock_transform.origin
	dock.scale = dock_transform.get_scale()

func _announce_selection() -> void:
	_announcement_id += 1
	var current_announcement_id := _announcement_id
	var character: Dictionary = CHARACTERS[queuePointer]
	if _bark_player != null:
		_bark_player.stop()

	tts_manager.queue_text(character["name"], 1)
	await tts_manager.tts_queue_finished

	if current_announcement_id != _announcement_id:
		return

	var bark_path := "res://assets/audio/sfx/%s_bark.wav" % character["name"].to_lower()
	if not ResourceLoader.exists(bark_path):
		return

	var bark := load(bark_path) as AudioStream
	if bark == null:
		push_error("CharacterSelect: Could not load bark audio at %s." % bark_path)
		return

	if _bark_player == null:
		_bark_player = AudioStreamPlayer.new()
		_bark_player.volume_db = 10.0
		add_child(_bark_player)
	_bark_player.stream = bark
	_bark_player.play()
