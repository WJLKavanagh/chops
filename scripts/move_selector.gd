class_name MoveSelector
extends Node2D
## Lets the player name their five moves by voice.
##
## Flow, once per move (high dodge, low dodge, high attack, low attack, super):
##   1. NAMING     - TTS asks "Name your <x> move."  Vosk runs in open dictation.
##   2. CONFIRMING - TTS reads the name back.        Vosk is restricted to yes / no words.
##        yes -> name is saved, move on to the next move
##        no  -> back to NAMING for the same move
## After the fifth move the choices are packed into an array, sent through the
## NetworkManager, and kept in MoveSelector.last_result for the next scene.
##
## The spoken loop reuses TTS_Manager: a Label in the "tts_element" group is read out
## whenever its text changes, and re-read after a quiet spell while it is also in "tts_loop".
## TTS_Manager also pauses the mic while it talks and resumes it afterwards.

## Emitted once all five moves are confirmed. result = [player, moves].
signal selection_complete(result: Array)

## Hand-off to the next scene (scene changes free this node, so a signal alone is not enough).
## Read it with:  var player = MoveSelector.last_result[0]
##                var moves  = MoveSelector.last_result[1]   # Dictionary, see MOVE_ORDER
static var last_result: Array = []

## Move keys, in the order they are asked. This is also the order of the
## PackedStringArray sent to NetworkManager.submit_moves().
const MOVE_ORDER: Array[String] = [
	"highDodge", "lowDodge", "highAttack", "lowAttack", "superMove"
]

## How each move is said out loud.
const MOVE_SPOKEN: Dictionary = {
	"highDodge": "high dodge move",
	"lowDodge": "low dodge move",
	"highAttack": "high attack move",
	"lowAttack": "low attack move",
	"superMove": "super move",
}
const MOVE_ANIMATIONS: Dictionary = {
	"highDodge": "block_high",
	"lowDodge": "block_low",
	"highAttack": "attack_high",
	"lowAttack": "attack_low",
	"superMove": "super_move",
}

const YES_WORDS: Array[String] = ["yes", "yeah", "okay", "correct"]
const NO_WORDS: Array[String] = ["no", "nope", "again", "retry"]
const ALTERNATIVE_WORDS: Array[String] = ["first", "second", "third", "retry"]
const MAX_NAME_WORDS: int = 4
const MIN_NAME_LENGTH: int = 2

## Tell NetworkManager this player is done (the host moves everyone on once both are ready).
@export var ready_up_when_done: bool = true
@export var debug_single_player_gordon: bool = false

enum Step { NAMING, SELECTING_ALTERNATIVE, CONFIRMING, FINISHED }

## The player passed in from the previous scene. Set it with setup().
## Accepted shapes: a String character id, a Dictionary with "character_id",
## or any object with a character_id property.
var player = null

## Confirmed names, keyed by MOVE_ORDER entries.
var moves: Dictionary = {}

var _step: Step = Step.NAMING
var _index: int = 0
var _pending_name: String = ""
var _single_player_debug_mode: bool = false
var _recognition_alternatives: PackedStringArray = PackedStringArray()
var _offered_alternatives: PackedStringArray = PackedStringArray()

var prompt_label: Label
var moves_label: Label
var recognition_label: Label
var action_preview: AnimatedSprite2D
var preview_fallback_label: Label


func setup(p_player) -> void:
	player = p_player


func _ready() -> void:
	_build_ui()
	TTS_Manager.set_listening_enabled(true)

	var local_peer_id := multiplayer.get_unique_id()
	var has_network_player := NetworkManager.session_data.has(local_peer_id)
	_single_player_debug_mode = debug_single_player_gordon or not has_network_player

	if _single_player_debug_mode:
		player = "Gordon"
		CharacterDB.selected_p1 = "Gordon"
	elif player == null:
		player = NetworkManager.session_data[multiplayer.get_unique_id()]["character_id"]

	if player == null or player == "":
		push_warning("MoveSelector: no player was passed in (call setup(player) first).")

	VoiceManager.PhraseRecognised.connect(_on_phrase_recognised)
	VoiceManager.PhraseAlternativesRecognised.connect(_on_phrase_alternatives_recognised)
	VoiceManager.PartialPhraseRecognised.connect(_on_partial_phrase_recognised)
	NetworkManager.player_data_updated.connect(_on_player_data_updated)
	NetworkManager.phase_complete.connect(_on_phase_complete)

	_load_player_animations()
	_refresh_moves_label()
	var prompt_prefix := "Let's name your five moves. "
	if _single_player_debug_mode:
		prompt_prefix = "Debug mode. Gordon selected. Let's name your five moves. "
	_prompt_for_name(prompt_prefix)


func _exit_tree() -> void:
	if VoiceManager.PhraseRecognised.is_connected(_on_phrase_recognised):
		VoiceManager.PhraseRecognised.disconnect(_on_phrase_recognised)
	if VoiceManager.PhraseAlternativesRecognised.is_connected(_on_phrase_alternatives_recognised):
		VoiceManager.PhraseAlternativesRecognised.disconnect(_on_phrase_alternatives_recognised)
	if VoiceManager.PartialPhraseRecognised.is_connected(_on_partial_phrase_recognised):
		VoiceManager.PartialPhraseRecognised.disconnect(_on_partial_phrase_recognised)
	if NetworkManager.player_data_updated.is_connected(_on_player_data_updated):
		NetworkManager.player_data_updated.disconnect(_on_player_data_updated)
	if NetworkManager.phase_complete.is_connected(_on_phase_complete):
		NetworkManager.phase_complete.disconnect(_on_phase_complete)


# --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	# Use nodes from the scene if they exist, otherwise create them.
	prompt_label = get_node_or_null("PromptLabel") as Label
	if prompt_label == null:
		prompt_label = Label.new()
		prompt_label.name = "PromptLabel"
		prompt_label.position = Vector2(60, 170)
		prompt_label.size = Vector2(1030, 200)
		prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prompt_label.add_theme_font_size_override("font_size", 40)
		add_child(prompt_label)

	moves_label = get_node_or_null("MovesLabel") as Label
	if moves_label == null:
		moves_label = Label.new()
		moves_label.name = "MovesLabel"
		moves_label.position = Vector2(60, 400)
		moves_label.size = Vector2(1030, 200)
		moves_label.add_theme_font_size_override("font_size", 28)
		add_child(moves_label)

	recognition_label = Label.new()
	recognition_label.name = "RecognitionLabel"
	recognition_label.position = Vector2(60, 650)
	recognition_label.size = Vector2(1030, 100)
	recognition_label.add_theme_font_size_override("font_size", 28)
	recognition_label.add_theme_color_override("font_color", Color(0.75, 0.84, 0.95))
	recognition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(recognition_label)

	action_preview = AnimatedSprite2D.new()
	action_preview.name = "ActionPreview"
	action_preview.position = Vector2(1510, 565)
	action_preview.centered = true
	action_preview.visible = false
	add_child(action_preview)

	preview_fallback_label = Label.new()
	preview_fallback_label.name = "PreviewFallbackLabel"
	preview_fallback_label.position = Vector2(1200, 480)
	preview_fallback_label.size = Vector2(620, 180)
	preview_fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_fallback_label.add_theme_font_size_override("font_size", 30)
	preview_fallback_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	add_child(preview_fallback_label)

	# TTS_Manager reads this label aloud and loops it. Only this label is in the group,
	# so the progress list below is shown but not spoken.
	prompt_label.add_to_group("tts_element")
	prompt_label.add_to_group("tts_loop")


func _say(text: String) -> void:
	prompt_label.text = text


func _refresh_moves_label() -> void:
	var lines := PackedStringArray()
	for key in MOVE_ORDER:
		lines.append("%s: %s" % [key, moves.get(key, "...")])
	moves_label.text = "\n".join(lines)

func _load_player_animations() -> void:
	var character_id := _character_id().to_lower()
	var frames_path := "res://assets/fighters/%s/%s_frames.tres" % [character_id, character_id]
	if character_id == "" or not ResourceLoader.exists(frames_path):
		preview_fallback_label.text = "No move animations available for %s." % _character_id()
		return

	var frames := load(frames_path) as SpriteFrames
	if frames == null:
		push_error("MoveSelector: Could not load SpriteFrames at %s." % frames_path)
		preview_fallback_label.text = "Could not load this fighter's animations."
		return

	action_preview.sprite_frames = frames.duplicate() as SpriteFrames
	action_preview.visible = true
	preview_fallback_label.visible = false

	var idle_animation := "idle"
	if action_preview.sprite_frames.has_animation(idle_animation):
		_play_preview_animation(idle_animation)
	else:
		action_preview.visible = false
		preview_fallback_label.visible = true
		preview_fallback_label.text = "No idle animation available for %s." % _character_id()


func _play_preview_animation(animation_name: String) -> void:
	if action_preview.sprite_frames == null or not action_preview.sprite_frames.has_animation(animation_name):
		action_preview.visible = false
		preview_fallback_label.visible = true
		preview_fallback_label.text = "No %s animation available for %s." % [
			_spoken(_current_key()), _character_id()
		]
		return

	action_preview.sprite_frames.set_animation_loop(animation_name, true)
	var frame := action_preview.sprite_frames.get_frame_texture(animation_name, 0)
	if frame != null:
		var fit_scale := minf(680.0 / frame.get_width(), 820.0 / frame.get_height())
		action_preview.scale = Vector2.ONE * fit_scale
	action_preview.visible = true
	preview_fallback_label.visible = false
	action_preview.play(animation_name)


# --- Naming / confirming loop -----------------------------------------------

func _current_key() -> String:
	return MOVE_ORDER[_index]


func _spoken(key: String) -> String:
	return MOVE_SPOKEN.get(key, key)


func _prompt_for_name(prefix: String = "") -> void:
	_step = Step.NAMING
	_pending_name = ""
	_recognition_alternatives.clear()
	recognition_label.text = ""
	_play_preview_animation(MOVE_ANIMATIONS[_current_key()])
	VoiceManager.StopListening()
	# Empty grammar = open dictation, so any name can be heard.
	VoiceManager.SetGrammar(PackedStringArray())
	_say("%sName your %s." % [prefix, _spoken(_current_key())])


func _on_phrase_recognised(phrase: String) -> void:
	phrase = phrase.strip_edges().to_lower()
	if phrase == "":
		return
	if _step == Step.NAMING:
		recognition_label.text = ""

	match _step:
		Step.NAMING:
			_handle_name(phrase)
		Step.SELECTING_ALTERNATIVE:
			_handle_alternative_choice(phrase)
		Step.CONFIRMING:
			_handle_confirmation(phrase)

func _on_phrase_alternatives_recognised(alternatives: PackedStringArray) -> void:
	_recognition_alternatives = alternatives


func _on_partial_phrase_recognised(phrase: String) -> void:
	if _step == Step.NAMING:
		recognition_label.text = "Hearing: %s" % phrase


func _handle_name(phrase: String) -> void:
	if phrase.length() < MIN_NAME_LENGTH:
		return

	var candidates := PackedStringArray()
	for alternative in _recognition_alternatives:
		var candidate := alternative.strip_edges().to_lower()
		if candidate.length() < MIN_NAME_LENGTH:
			continue
		if candidate.split(" ", false).size() > MAX_NAME_WORDS or moves.values().has(candidate):
			continue
		if not candidates.has(candidate):
			candidates.append(candidate)
		if candidates.size() == 3:
			break

	if candidates.size() > 1:
		_offer_alternatives(candidates)
		return

	var key := _current_key()
	if phrase.split(" ", false).size() > MAX_NAME_WORDS:
		_say("That name is too long. Use up to %d words. Name your %s." % [MAX_NAME_WORDS, _spoken(key)])
		return

	_set_pending_name(phrase)


func _offer_alternatives(candidates: PackedStringArray) -> void:
	_offered_alternatives = candidates
	_step = Step.SELECTING_ALTERNATIVE
	VoiceManager.StopListening()
	VoiceManager.SetGrammar(PackedStringArray(ALTERNATIVE_WORDS))
	var choices := PackedStringArray()
	for index in range(candidates.size()):
		choices.append("%s, %s" % [ALTERNATIVE_WORDS[index].capitalize(), candidates[index]])
	_say("I heard a few possible names. %s. Say first, second, or third to choose, or retry to say it again." % ", ".join(choices))


func _handle_alternative_choice(phrase: String) -> void:
	var choice_index := ALTERNATIVE_WORDS.find(phrase)
	if phrase == "retry":
		_prompt_for_name("Okay, try again. ")
	elif choice_index >= 0 and choice_index < _offered_alternatives.size():
		_set_pending_name(_offered_alternatives[choice_index])


func _set_pending_name(phrase: String) -> void:
	if moves.values().has(phrase):
		_prompt_for_name("You already used %s. Pick a different name. " % phrase)
		return
	_pending_name = phrase
	_step = Step.CONFIRMING
	VoiceManager.StopListening()
	# Only yes/no words are allowed while confirming.
	VoiceManager.SetGrammar(PackedStringArray(YES_WORDS + NO_WORDS))
	_say("You said %s. Is that right? Say yes to keep it, or no to try again." % phrase)


func _handle_confirmation(phrase: String) -> void:
	var heard_yes := false
	var heard_no := false
	for word in phrase.split(" ", false):
		if YES_WORDS.has(word):
			heard_yes = true
		if NO_WORDS.has(word):
			heard_no = true

	# Neither, or both: ignore it. The TTS loop will ask again.
	if heard_yes == heard_no:
		return

	if heard_no:
		_prompt_for_name("Okay, try again. ")
		return

	var key := _current_key()
	moves[key] = _pending_name
	_refresh_moves_label()
	var saved := "%s saved as %s. " % [_spoken(key).capitalize(), _pending_name]

	_index += 1
	if _index >= MOVE_ORDER.size():
		_finish()
	else:
		_prompt_for_name(saved + "Now, ")


# --- Finishing and hand-off -------------------------------------------------

func _finish() -> void:
	_step = Step.FINISHED
	VoiceManager.StopListening()

	var names := PackedStringArray()
	var spoken_lines := PackedStringArray()
	for key in MOVE_ORDER:
		names.append(moves[key])
		spoken_lines.append("%s: %s." % [_spoken(key).capitalize(), moves[key]])

	# Player and moves, as one array for the next scene.
	last_result = [player, moves.duplicate()]
	selection_complete.emit(last_result)
	print("MoveSelector: array for the next scene = ", last_result)

	var summary := "All five moves are set. " + " ".join(spoken_lines)
	var sent_to_network := _submit_to_network(names)
	if sent_to_network and ready_up_when_done:
		summary += " Waiting for the other player."

	# Stop the spoken loop; the summary is read once.
	prompt_label.remove_from_group("tts_loop")
	_say(summary)


## Sends the player's choices through NetworkManager. Returns false when there is no match yet.
func _submit_to_network(names: PackedStringArray) -> bool:
	if _single_player_debug_mode:
		return false

	if not NetworkManager.session_data.has(multiplayer.get_unique_id()):
		push_warning("MoveSelector: no active match, so nothing was sent (fine when testing this scene alone).")
		return false

	var char_id := _character_id()
	if char_id != "":
		NetworkManager.submit_character(char_id)
	else:
		push_warning("MoveSelector: the player has no character id. The host needs one to pick the next scene.")

	NetworkManager.submit_moves(names)

	if ready_up_when_done:
		NetworkManager.set_ready(true)
	return true


func _character_id() -> String:
	if player is String:
		return player
	if player is Dictionary:
		return str(player.get("character_id", ""))
	if player is Object and "character_id" in player:
		return str(player.character_id)
	return ""


# --- Network feedback -------------------------------------------------------

func _on_player_data_updated(peer_id: int) -> void:
	if _step != Step.FINISHED or not NetworkManager.session_data.has(peer_id):
		return
	var data: Dictionary = NetworkManager.session_data[peer_id]
	print("MoveSelector: player %d ready=%s moves=%s" % [peer_id, data["is_ready"], data["move_names"]])


func _on_phase_complete(next_scene_path: String) -> void:
	print("MoveSelector: both players ready, moving to ", next_scene_path)
