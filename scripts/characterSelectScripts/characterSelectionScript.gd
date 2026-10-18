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
	{"name": "Kellie", "texture": null}
]

const PLACEHOLDER_COLORS: Array[Color] = [
	Color(0.17, 0.32, 0.48),
	Color(0.39, 0.24, 0.42),
	Color(0.23, 0.37, 0.31)
]
const VOICE_COMMANDS: PackedStringArray = ["next", "previous", "lock in"]
const MOVE_VARIATIONS_PATH := "res://Resources/MoveVariations.json"
const MOVE_ORDER: Array[String] = ["high_attack", "low_attack", "high_block", "low_block", "super_move"]
const MOVE_LABELS: Array[String] = ["high attack", "low attack", "high block", "low block", "super move"]
const CONFIRMATION_PANEL_COLOR := Color(0.035, 0.055, 0.09, 0.94)

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
var _awaiting_command: bool = false
var _locked_in: bool = false
var _idle_animations: Dictionary = {}
var _move_variations: Dictionary = {}
var _selected_move_names: PackedStringArray = PackedStringArray()
var _move_confirmation_index: int = 0
var _confirmation_prompt_label: Label
var _confirmation_progress_label: Label

func _ready() -> void:
	randomize()
	tts_manager.set_listening_enabled(false)
	if not VoiceManager.PhraseRecognised.is_connected(_on_phrase_recognised):
		VoiceManager.PhraseRecognised.connect(_on_phrase_recognised)
	VoiceManager.SetGrammar(VOICE_COMMANDS)

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
	_load_idle_animations()
	_move_variations = _load_move_variations()
	_setup_character_panels()
	_changeImages()
	_announce_selection()

func _process(_delta: float) -> void:
	if moving or _awaiting_command or _locked_in:
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

		var idle_sprite := AnimatedSprite2D.new()
		idle_sprite.name = "IdleAnimation"
		idle_sprite.position = dock.size * 0.5
		idle_sprite.centered = true
		dock.add_child(idle_sprite)

		var fallback_sprite := Sprite2D.new()
		fallback_sprite.name = "FallbackSprite"
		fallback_sprite.position = dock.size * 0.5
		fallback_sprite.centered = true
		dock.add_child(fallback_sprite)

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

func _load_idle_animations() -> void:
	for character in CHARACTERS:
		var character_name: String = character["name"].to_lower()
		var frames_path := "res://assets/fighters/%s/%s_frames.tres" % [character_name, character_name]
		if not ResourceLoader.exists(frames_path):
			continue

		var frames := load(frames_path) as SpriteFrames
		if frames == null:
			push_error("CharacterSelect: Could not load SpriteFrames at %s." % frames_path)
			continue
		if not frames.has_animation("idle"):
			push_warning("CharacterSelect: No idle animation found in %s." % frames_path)
			continue

		var looping_frames := frames.duplicate() as SpriteFrames
		looping_frames.set_animation_loop("idle", true)
		_idle_animations[character_name] = looping_frames

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
		var idle_sprite := dock.get_node("IdleAnimation") as AnimatedSprite2D
		var fallback_sprite := dock.get_node("FallbackSprite") as Sprite2D
		var character_name: String = character["name"].to_lower()
		var idle_frames := _idle_animations.get(character_name) as SpriteFrames

		# lets make that label massive
		var name_label := dock.get_node("Name") as Label

		if idle_frames != null:
			idle_sprite.sprite_frames = idle_frames
			idle_sprite.animation = "idle"
			idle_sprite.visible = true
			fallback_sprite.visible = false
			portrait.texture = null
			name_label.add_theme_font_size_override("font_size", 72)

			# Move it further down
			name_label.offset_top = -20.0
			name_label.offset_bottom = 36.0
			var first_frame := idle_frames.get_frame_texture("idle", 0)
			if first_frame != null:
				var fit_scale := (dock.size.y * 2.3) / first_frame.get_height()
				idle_sprite.scale = Vector2.ONE * fit_scale
				idle_sprite.offset = _get_visual_center_offset(first_frame)
			idle_sprite.play("idle")
		else:
			idle_sprite.stop()
			idle_sprite.visible = false
			name_label.add_theme_font_size_override("font_size", 40)

			name_label.offset_top = -64.0
			name_label.offset_bottom = -8.0
			var fallback_texture := character["texture"] as Texture2D
			if fallback_texture != null:
				var fallback_image := fallback_texture.get_image()
				if fallback_image != null and not fallback_image.is_empty() and fallback_image.detect_alpha():
					fallback_sprite.texture = fallback_texture
					fallback_sprite.offset = _get_visual_center_offset(fallback_texture)
					fallback_sprite.scale = Vector2.ONE * (dock.size.y * 1.15 / fallback_texture.get_height())
					fallback_sprite.visible = true
					portrait.texture = null
				else:
					fallback_sprite.visible = false
					portrait.texture = fallback_texture
			else:
				fallback_sprite.visible = false
				portrait.texture = null

		dock.color = Color(1, 1, 1, 0) if idle_frames != null or fallback_sprite.visible or portrait.texture != null else PLACEHOLDER_COLORS[character_index % PLACEHOLDER_COLORS.size()]
		dock.get_node("Name").text = character["name"]

func _get_visual_center_offset(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector2.ZERO

	var visible_bounds := image.get_used_rect()
	if visible_bounds.size.x <= 0 or visible_bounds.size.y <= 0:
		return Vector2.ZERO

	var visible_center := Vector2(visible_bounds.position) + Vector2(visible_bounds.size) * 0.5
	return Vector2(texture.get_size()) * 0.5 - visible_center

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
	_awaiting_command = false
	tts_manager.set_listening_enabled(false)
	VoiceManager.StopListening()
	if _bark_player != null:
		_bark_player.stop()

	tts_manager.queue_text(character["name"], 1)
	await tts_manager.tts_queue_finished

	if current_announcement_id != _announcement_id or _locked_in:
		return

	var bark_path := "res://assets/audio/sfx/%s_bark.wav" % character["name"].to_lower()
	if ResourceLoader.exists(bark_path):
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
		await _bark_player.finished

	if current_announcement_id != _announcement_id or _locked_in:
		return

	tts_manager.queue_text("Say next, previous, or lock in.", 1)
	await tts_manager.tts_queue_finished

	if current_announcement_id != _announcement_id or _locked_in:
		return

	VoiceManager.SetGrammar(VOICE_COMMANDS)
	_awaiting_command = true
	tts_manager.set_listening_enabled(true)
	VoiceManager.StartListening()

func _on_phrase_recognised(phrase: String) -> void:
	if not _awaiting_command or moving:
		return

	if _locked_in:
		_handle_move_confirmation(phrase)
		return

	var command := phrase.strip_edges().to_lower()
	_awaiting_command = false
	tts_manager.set_listening_enabled(false)

	if command.contains("next"):
		queuePointer = posmod(queuePointer + 1, CHARACTERS.size())
		_moveAllDocksLeft()
	elif command.contains("previous"):
		queuePointer = posmod(queuePointer - 1, CHARACTERS.size())
		_moveAllDocksRight()
	elif command.contains("lock in"):
		_lock_in_selection()
	else:
		_announce_selection()

func _lock_in_selection() -> void:
	var character_name: String = CHARACTERS[queuePointer]["name"]
	if _move_variations.is_empty() or not _move_variations.has(character_name):
		push_error("CharacterSelect: Move variations are unavailable for %s." % character_name)
		tts_manager.queue_text("Move names are unavailable for this character. Please try another character.", 1)
		await tts_manager.tts_queue_finished
		_announce_selection()
		return

	_locked_in = true
	var local_peer_id := multiplayer.get_unique_id()
	if local_peer_id == 1:
		CharacterDB.selected_p1 = character_name
	else:
		CharacterDB.selected_p2 = character_name
	NetworkManager.submit_character(character_name)
	_prepare_move_confirm_screen()
	tts_manager.queue_text("%s locked in." % character_name, 1)
	await tts_manager.tts_queue_finished
	_announce_move_confirmation()

func _load_move_variations() -> Dictionary:
	if not FileAccess.file_exists(MOVE_VARIATIONS_PATH):
		push_error("CharacterSelect: Move variation data not found at %s." % MOVE_VARIATIONS_PATH)
		return {}

	var file := FileAccess.open(MOVE_VARIATIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("CharacterSelect: Could not open move variation data at %s." % MOVE_VARIATIONS_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("CharacterSelect: Move variation data must contain a JSON object.")
		return {}

	for character in CHARACTERS:
		var character_name: String = character["name"]
		if not parsed.has(character_name) or not parsed[character_name] is Dictionary:
			push_error("CharacterSelect: Move variations are missing for %s." % character_name)
			return {}
		for move_key in MOVE_ORDER:
			var variations: Variant = parsed[character_name].get(move_key)
			if not variations is Array or variations.size() != 2:
				push_error("CharacterSelect: %s must have exactly two variations for %s." % [character_name, move_key])
				return {}
			for variation in variations:
				if not variation is String or variation.strip_edges().is_empty():
					push_error("CharacterSelect: %s has an invalid variation for %s." % [character_name, move_key])
					return {}

	return parsed

func _prepare_move_confirm_screen() -> void:
	for dock in [characterDockOffScreenL, characterDockLeft, characterDockRight, characterDockOffScreenR]:
		dock.hide()

	characterDockMain.set_anchors_preset(Control.PRESET_TOP_LEFT)
	characterDockMain.position = Vector2.ZERO
	characterDockMain.size = Vector2(680.0, 1080.0)
	characterDockMain.scale = Vector2.ONE
	characterDockMain.pivot_offset = characterDockMain.size * 0.5
	characterDockMain.color = Color(1, 1, 1, 0)

	var portrait := characterDockMain.get_node("Portrait") as TextureRect
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var idle_sprite := characterDockMain.get_node("IdleAnimation") as AnimatedSprite2D
	var fallback_sprite := characterDockMain.get_node("FallbackSprite") as Sprite2D
	var name_label := characterDockMain.get_node("Name") as Label
	idle_sprite.position = characterDockMain.size * 0.5
	fallback_sprite.position = characterDockMain.size * 0.5
	name_label.add_theme_font_size_override("font_size", 54)
	name_label.offset_top = -110.0
	name_label.offset_bottom = -25.0

	if idle_sprite.visible and idle_sprite.sprite_frames != null:
		var frame := idle_sprite.sprite_frames.get_frame_texture(idle_sprite.animation, 0)
		if frame != null:
			idle_sprite.scale = Vector2.ONE * (characterDockMain.size.y * 0.92 / frame.get_height())
			idle_sprite.offset = _get_visual_center_offset(frame)
	elif fallback_sprite.visible and fallback_sprite.texture != null:
		fallback_sprite.scale = Vector2.ONE * (characterDockMain.size.y * 0.92 / fallback_sprite.texture.get_height())
		fallback_sprite.offset = _get_visual_center_offset(fallback_sprite.texture)

	var panel := ColorRect.new()
	panel.name = "MoveConfirmationPanel"
	panel.position = Vector2(680.0, 0.0)
	panel.size = Vector2(1240.0, 1080.0)
	panel.color = CONFIRMATION_PANEL_COLOR
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var heading := Label.new()
	heading.text = "MOVE CONFIRMATION"
	heading.position = Vector2(110.0, 190.0)
	heading.size = Vector2(1000.0, 90.0)
	heading.add_theme_font_size_override("font_size", 48)
	heading.add_theme_color_override("font_color", Color(0.64, 0.86, 1.0))
	panel.add_child(heading)

	_confirmation_progress_label = Label.new()
	_confirmation_progress_label.position = Vector2(110.0, 315.0)
	_confirmation_progress_label.size = Vector2(1000.0, 70.0)
	_confirmation_progress_label.add_theme_font_size_override("font_size", 36)
	_confirmation_progress_label.add_theme_color_override("font_color", Color(0.82, 0.87, 0.94))
	panel.add_child(_confirmation_progress_label)

	_confirmation_prompt_label = Label.new()
	_confirmation_prompt_label.position = Vector2(110.0, 430.0)
	_confirmation_prompt_label.size = Vector2(1000.0, 260.0)
	_confirmation_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation_prompt_label.add_theme_font_size_override("font_size", 54)
	_confirmation_prompt_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_confirmation_prompt_label)

	var instruction := Label.new()
	instruction.text = "Say the move name to confirm it."
	instruction.position = Vector2(110.0, 760.0)
	instruction.size = Vector2(1000.0, 80.0)
	instruction.add_theme_font_size_override("font_size", 34)
	instruction.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	panel.add_child(instruction)

	_selected_move_names.clear()
	var character_moves: Dictionary = _move_variations[CHARACTERS[queuePointer]["name"]]
	for move_key in MOVE_ORDER:
		var variations: Array = character_moves[move_key]
		_selected_move_names.append(variations[randi_range(0, variations.size() - 1)].strip_edges().to_lower())

func _announce_move_confirmation() -> void:
	if _move_confirmation_index >= MOVE_ORDER.size():
		_finish_move_confirmation()
		return

	var move_label: String = MOVE_LABELS[_move_confirmation_index]
	var move_name: String = _selected_move_names[_move_confirmation_index]
	var character_name: String = CHARACTERS[queuePointer]["name"]
	var prompt := "%s's %s is called %s, say %s to confirm." % [character_name, move_label, move_name, move_name]
	_confirmation_progress_label.text = "Move %d of %d" % [_move_confirmation_index + 1, MOVE_ORDER.size()]
	_confirmation_prompt_label.text = prompt
	_awaiting_command = false
	tts_manager.set_listening_enabled(false)
	VoiceManager.StopListening()
	VoiceManager.SetGrammar(PackedStringArray([move_name]))
	tts_manager.queue_text(prompt, 1)
	await tts_manager.tts_queue_finished

	if not _locked_in or _move_confirmation_index >= MOVE_ORDER.size():
		return

	_awaiting_command = true
	tts_manager.set_listening_enabled(true)
	VoiceManager.StartListening()

func _finish_move_confirmation() -> void:
	_awaiting_command = false
	tts_manager.set_listening_enabled(false)
	VoiceManager.StopListening()
	VoiceManager.SetGrammar(_selected_move_names)
	_confirmation_progress_label.text = "All five move names confirmed."
	_confirmation_prompt_label.text = "Waiting for the other player to finish..."
	NetworkManager.submit_moves(_selected_move_names)
	NetworkManager.set_ready(true)

func _handle_move_confirmation(phrase: String) -> void:
	_awaiting_command = false
	tts_manager.set_listening_enabled(false)
	VoiceManager.StopListening()

	var expected_name: String = _selected_move_names[_move_confirmation_index]
	if phrase.strip_edges().to_lower() != expected_name:
		_announce_move_confirmation()
		return

	_move_confirmation_index += 1
	_announce_move_confirmation()
