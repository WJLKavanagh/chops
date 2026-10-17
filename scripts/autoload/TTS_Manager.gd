extends Node

signal tts_queue_finished
signal tts_started

var message_queue: Array[String] = []
var is_speaking: bool = false
var voice_id: String = ""

var voice_manager: Node
var screen_scan_timer: Timer
var last_spoken_text: String = ""
var current_scene_name: String = ""

#Previous next confirm carousel.


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#System voice for boot
	
	var voices = DisplayServer.tts_get_voices()
	if voices.size() > 0:
				#ID string of voice from the background dictionary
		var voice_id: String = voices[0]["id"]
				
			#Main C# manager for binding
		call_deferred("bind_voice_manager")
			
			#Menu and screen timer dynamic setup.
			
		screen_scan_timer = Timer.new()
		add_child(screen_scan_timer)
		screen_scan_timer.wait_time = 0.5
		screen_scan_timer.autostart = true
		screen_scan_timer.timeout.connect(on_screen_scan_timeout)
		screen_scan_timer.start()
			
func bind_voice_manager() -> void:
				voice_manager = get_tree().root.get_node_or_null("VoiceManager")
	
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
		elif force_loop and not is_speaking and message_queue.is_empty():
				queue_text(current_screen_text, 0)
			
	#
func queue_text(text: String, priority: int = 0) -> void:
	if priority == 1:
		message_queue.clear()
		DisplayServer.tts_stop()
		is_speaking = false
		
	message_queue.append(text)
	process_queue()
	
func process_queue() -> void:
	if is_speaking or message_queue.is_empty():
		return
		
	is_speaking = true
	tts_started.emit()
	
	#Muting microphone so no TTS heard
	if voice_manager != null and voice_manager.has_method("StopListening"):
		voice_manager.StopListening()
		
	var text_to_speak = message_queue.pop_front()
	DisplayServer.tts_speak(text_to_speak, voice_id, 50, 1.0, 1.0)
	
	check_tts_completion()
	
func check_tts_completion() -> void:
	if DisplayServer.tts_is_speaking():
		get_tree().create_timer(0.1).timeout.connect(check_tts_completion)
	else:
		is_speaking = false
		if not message_queue.is_empty():
			process_queue()
		else:
			tts_queue_finished.emit()
		
func prompt_player_for_action() -> void:
	queue_text("Your turn.")
	await tts_queue_finished
	
	if voice_manager != null and voice_manager.has_method("StartListening"):
		voice_manager.StartListening()
	
		
	
