extends Node

signal tts_queue_finished
signal tts_started

var message_queue: Array[String] = []
var voice_id: String = ""
var current_rate: float = 1.8 #Normal speed selected first.

var voice_manager: Node
var listening_enabled: bool = false
var screen_scan_timer: Timer
var completion_timer: Timer
var last_spoken_text: String = ""
var current_scene_name: String = ""
var is_processing: bool = false

#Is TTS active from other scripts
var is_speaking: bool:
	get: return is_processing or DisplayServer.tts_is_speaking()

# a cooldown to spread out prompts
var loop_cooldown: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#System voice for boot

	var voices = DisplayServer.tts_get_voices()
	if voices.size() > 0:
		#ID string of voice from the background dictionary
		voice_id = voices[0]["id"]

	#Main C# manager for binding
	call_deferred("bind_voice_manager")

	#DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, Callable(self, "_on_tts_utterance_ended"))

	#Menu and screen timer dynamic setup.
	screen_scan_timer = Timer.new()
	screen_scan_timer.wait_time = 0.5
	screen_scan_timer.autostart = true
	screen_scan_timer.timeout.connect(on_screen_scan_timeout)
	add_child(screen_scan_timer)
	screen_scan_timer.start()

	# # completion polling timer
	# completion_timer = Timer.new()
	# completion_timer.wait_time = 0.1
	# completion_timer.autostart = false
	# #completion_timer.timeout.connect(_on_completion_poll)
	# add_child(completion_timer)

func _process(delta: float) -> void:
	if loop_cooldown > 0:
		loop_cooldown -= delta

func bind_voice_manager() -> void:
	voice_manager = get_tree().root.get_node_or_null("VoiceManager")
	

func set_listening_enabled(enabled: bool) -> void:
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").SetListeningEnabled(enabled)
	

func on_screen_scan_timeout() -> void: #Next part SHOULD stop the system getting stuck when the player loads a new level
	var active_scene = get_tree().current_scene.name if get_tree().current_scene else ""
	if current_scene_name != active_scene:
		last_spoken_text = ""
		current_scene_name = active_scene

	#Grab every node on the tts_element
	var elements = get_tree().get_nodes_in_group("tts_element")

	#If no TTS on screen during combat
	if elements.is_empty():
			last_spoken_text = ""
			return

	var current_screen_text: String = ""
	var force_loop: bool = false

	for element in elements:
		if element is Label or element is RichTextLabel:
			#Slight pause for TTS
			current_screen_text += element.text + ". "
		elif "custom_tts_string" in element:
			#Custom variables
			current_screen_text += element.custom_tts_string + ". "

		#is a loop element active (loop group)?
		if element.is_in_group("tts_loop") or ("is_looping" in element and element.is_looping):
			force_loop = true

	current_screen_text = current_screen_text.strip_edges()
	if current_screen_text == "":
		return

	#If brand new text, clear queue and speak it (priority one)
	if current_screen_text != last_spoken_text:
		last_spoken_text = current_screen_text
		queue_text(current_screen_text, 1)

		#If looping menu text, only inject if game is silent
	elif force_loop and loop_cooldown <= 0.0 and not is_speaking and message_queue.is_empty():
		queue_text(current_screen_text, 0)

func queue_text(text: String, priority: int = 0) -> void:
	if priority >= 1:
		
		DisplayServer.tts_stop()
		message_queue.clear()
		message_queue.append(text)
		#completion_timer.stop()
	else:
		#Combat logs
		message_queue.append(text)
		
	#Backgground loop not running so start
	if not is_processing:
		process_queue()
		

	
	

# func process_queue() -> void:
# 	if is_speaking or message_queue.is_empty():
# 		return

# 	is_speaking = true
# 	tts_started.emit()

# 	# Pause mic during narration of prompts
# 	if voice_manager != null and voice_manager.has_method("StopListening"):
# 		voice_manager.StopListening()

# 	var text_to_speak = message_queue.pop_front()
# 	DisplayServer.tts_speak(text_to_speak, voice_id, 50, 1.0, 1.0)

# 	# Wait for the OS audio thread to catch up before we begin polling
# 	await get_tree().create_timer(0.25).timeout
# 	completion_timer.start()

func process_queue() -> void:
	is_processing = true
	
	while message_queue.size() > 0:
		var next_text = message_queue.pop_front()
		
		DisplayServer.tts_speak(next_text, voice_id, 50, 1.0, current_rate)
		
		#Yielding frame so registering
		await get_tree().process_frame
		
		#Hold loop here until it finishes
		while DisplayServer.tts_is_speaking():
			await get_tree().create_timer(0.1).timeout
			
	#The queue is empty so announce TTS finish
	is_processing = false
	tts_queue_finished.emit()
	
	
	
#SLOW IS Speed 1, Normal 1.8, Fast 2.2, Extra Fast 2.6 Super Fast 3.2, now above
# func _on_completion_poll() -> void:
# 	if not DisplayServer.tts_is_speaking():
# 		completion_timer.stop()
# 		is_speaking = false

# 		if not message_queue.is_empty():
# 			process_queue()
# 		else:
# 			# Give the player a 5-second silence window to issue a command
# 			loop_cooldown = 5.0
# 			tts_queue_finished.emit()

# 			if voice_manager != null and voice_manager.has_method("StartListening"):
# 				voice_manager.StartListening()

# Triggered directly by the OS when the voice finishes
#func _on_tts_utterance_ended(_utterance_id: int) -> void:
	#is_speaking = false

	#if not message_queue.is_empty():
		#process_queue()
	#else:
		# Narration complete: give a 6-second window for player to speak
		#loop_cooldown = 6.0
		#tts_queue_finished.emit()

		#if listening_enabled and voice_manager != null and voice_manager.has_method("StartListening"):
			#voice_manager.StartListening()

func prompt_player_for_action(text: String = "Your turn.") -> void:
	queue_text(text, 1)
