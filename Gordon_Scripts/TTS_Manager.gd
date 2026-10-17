extends Node

var tts_timer: Timer
var last_spoken_text: String = ""
var current_scene_name: String = ""

#Previous next confirm carousel.


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#Dynamically make the timer so the script doesn't need a scene tree.
	
	tts_timer = Timer.new()
	add_child(tts_timer)
	tts_timer.wait_time = 0.5 #New text checker every 0.5 seconds
	tts_timer.autostart = true
	tts_timer.timeout.connect(OnTimerTimeout)
	tts_timer.start()

func OnTimerTimeout() -> void:
	if DisplayServer.tts_is_speaking():
		return
		
	var current_screen_text: String = ""
	var force_loop: bool = false
	
	#Next part SHOULD stop the system getting stuck when the player loads a new level
	var active_scene= get_tree().current_scene.name if get_tree().current_scene else ""
	if current_scene_name != active_scene:
		last_spoken_text = ""
		current_scene_name = active_scene
		
		#Grab every node on the tts_element
	var elements = get_tree().get_nodes_in_group("tts_element")
	
	#text to be extracted from each element
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
			
			#Attemping to stop TTS from speaking voids in the text. Will this manifest, who knows?
			if current_screen_text.strip_edges() == "":
				return
			
				
			

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
