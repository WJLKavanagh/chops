extends Node

@onready var tts_timer: Timer = $Timer

#Need this for rembering whatever it is the game has just read. To make this system modular we'll need some kind of priority tree.
#Note to self: Priority tree should come before audio cue system. Find that beat maker online website.

var last_spoken_text: String = ""

func _ready() -> void:
	tts_timer.timeout.connect(OnTimerTimeout)
	
func OnTimerTimeout() -> void:
	#1. Stop playing TTS for new loop
	
	if DisplayServer.tts_is_speaking():
		return
		
	
	
	var current_screen_text: String = ""
	var force_loop: bool = false #In global groups, we need to check a label for whether it is a tts_element (do we want it read) and
	#check it for tts_loop if we want it repeating, IE: how to start the game on the main menu.
	
	#2. Grabbing every node placed for the tts_element.
	
	var elements = get_tree().get_nodes_in_group("tts_element")
	
	#Extracting the text from each element
	
	for element in elements:
		if element is Label:
			#Pause for TTS ever so slightly
			current_screen_text += element.text + ". "
		elif "custom_tts_string" in element:
			#Custom variables
			current_screen_text += element.custom_tts_string + ". "
			
			#Checks if loop is active
		if element.is_in_group("tts_loop") or ("is_looping" in element and element.is_looping):
			force_loop = true
			
			#Below: Are you text we've said before? If nay play it, if we're currently playing it, surprise, don't play it again. This part of the system should be
			#used for when we have stats or other screen elements to read out continously to the player, not the loops. 
			#Loops I think I'll just make a bool for and then another group for the label.
	if current_screen_text != last_spoken_text or force_loop:
			
			DisplayServer.tts_stop()
	#3. Speaking the actual text 
	
	
			var voices = DisplayServer.tts_get_voices()
			if voices.size() > 0:
			#id string of voice from dictionary
				var voice_id: String = voices[0]["id"]
			#System normal voice, volume, pitch, rate
				DisplayServer.tts_speak(current_screen_text, voice_id[0], 50, 1.0, 1.0)
			
			last_spoken_text = current_screen_text
