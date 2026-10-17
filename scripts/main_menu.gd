extends Node

const START_PHRASES: Array[String] = [
	"let me kick a man in the head",
	"get fighting",
	"ready to rumble",
	"start the match",
	"throw hands"
]

const FILLER_WORDS: Array[String] = [
	"time", "to", "i", "am", "i'm", "ready", "let's", "go", "please", "just"
]

var active_phrase: String = ""
var is_processing_input: bool = false
var last_error_time: float = 0.0

var swap_timer: Timer

@onready var start_prompt = $StartPrompt

func _ready() -> void:
	active_phrase = START_PHRASES.pick_random()
	
	start_prompt.text = "Say '%s' to start" % active_phrase
	start_prompt.add_to_group("tts_element")
	start_prompt.add_to_group("tts_loop")
	
	# Setup the 10-second swap timer
	swap_timer = Timer.new()
	swap_timer.wait_time = 10.0
	swap_timer.timeout.connect(_on_swap_timer_timeout)
	add_child(swap_timer)
	swap_timer.start()
	
	var valid_words = _build_padded_grammar(active_phrase)
	
	# Connect STT using direct Autoload
	if not VoiceManager.PhraseRecognised.is_connected(_on_phrase_recognised):
		VoiceManager.PhraseRecognised.connect(_on_phrase_recognised)
		
	VoiceManager.SetGrammar(PackedStringArray(valid_words))
	VoiceManager.StartListening()
		
	# Connect Network signals using direct Autoload
	if not NetworkManager.match_started.is_connected(_on_match_started):
		NetworkManager.match_started.connect(_on_match_started)

func _on_swap_timer_timeout() -> void:
	if is_processing_input:
		return
		
	var new_phrase = active_phrase
	while new_phrase == active_phrase:
		new_phrase = START_PHRASES.pick_random()
		
	active_phrase = new_phrase
	print("Swapping target phrase to: ", active_phrase)
	
	start_prompt.text = "Say '%s' to start" % active_phrase
	
	var valid_words = _build_padded_grammar(active_phrase)
	VoiceManager.SetGrammar(PackedStringArray(valid_words))

func _build_padded_grammar(target_phrase: String) -> Array:
	var words := target_phrase.split(" ")
	var unique_words := []
	
	for word in words:
		if not unique_words.has(word):
			unique_words.append(word)
			
	for filler in FILLER_WORDS:
		if not unique_words.has(filler):
			unique_words.append(filler)
			
	return unique_words

func _process(delta: float) -> void:
	last_error_time += delta

func _on_phrase_recognised(phrase: String) -> void:
	if is_processing_input:
		return
		
	if active_phrase in phrase:
		is_processing_input = true
		swap_timer.stop() 
		
		print("Start phrase recognised within input. Initiating network connection...")
		
		start_prompt.text = "Connecting..."
		start_prompt.remove_from_group("tts_loop")
		
		VoiceManager.StopListening()
		NetworkManager.start_lan_match()
	else:
		_trigger_feedback(phrase)

func _trigger_feedback(heard_text: String) -> void:
	if heard_text.length() < 3:
		return
		
	if last_error_time >= 3.0:
		print("Failed recognition. Heard: ", heard_text)
		
		start_prompt.text = "I heard %s. Please say: %s" % [heard_text, active_phrase]
		last_error_time = 0.0
		
		swap_timer.start()
		
		await get_tree().create_timer(4.0).timeout
		if not is_processing_input:
			start_prompt.text = "Say '%s' to start" % active_phrase

func _on_match_started(is_host: bool) -> void:
	if is_host:
		start_prompt.text = "Hosting match. Waiting for player 2..."
	else:
		start_prompt.text = "Joined match! Proceeding..."
