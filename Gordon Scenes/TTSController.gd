extends Node

@onready var tts_timer: Timer = $Timer

func _ready() -> void:
	tts_timer.timeout.connect(OnTimerTimeout)
	
func OnTimerTimeout() -> void:
	#1. Stop playing TTS for new loop
	
	DisplayServer.tts_stop()
	
	var screen_text: String = ""
	
	#2. Grabbing every node placed for the tts_element.
	
	var elements = get_tree().get_nodes_in_group("tts_element")
	
	#Extracting the text from each element
	
	for element in elements:
		if element is Label:
			#Pause for TTS ever so slightly
			screen_text += element.text + ". "
		elif "custom_tts_string" in element:
			#Custom variables
			screen_text += element.custom_tts_string + ". "
			
	#4. Speaking the actual text 
	
	if screen_text != "":
		var voices = DisplayServer.tts_get_voices()
		if voices.size() > 0:
			#System normal voice, volume, pitch, rate
			DisplayServer.tts_speak(screen_text, voices[0], 50, 1.0, 1.0)
			
