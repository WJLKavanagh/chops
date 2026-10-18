extends Control

@onready var tts = get_node("/root/TTS_Manager")
@onready var status_label

#Dictionary: Speed Commands (Must be strictly lowercase for Vosk)

var speed_commands = {
	"slow": 1.0,
	"normal": 1.8,
	"fast": 2.2,
	"extra fast": 2.6,
	"super fast": 3.2
}



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if has_node("/root/VoiceManager"):
		var vm = get_node("/root/VoiceManager")
		vm.connect("PhraseRecognised", Callable(self, "on_phrase_recognised"))
		
		#Vosk dictionary lock
		var grammar := PackedStringArray(speed_commands.keys())
		vm.SetGrammar(grammar)
		
		start_speed_menu()
		
func start_speed_menu() -> void:
	if status_label:
		status_label.text = "Waiting for speed selection..."
			
	tts.queue_text("Text to Speech Speed Calibration.")
	tts.queue_text("Say slow, normal, fast, extra fast, or super fast.")
	
	#Wait for the TTS to finish reading the instructions, then turn on the mix
	await tts.tts_queue_finished
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StartListening()
		
func on_phrase_recognised(phrase: String) -> void:
	#Mic muted for no TTS speed
	if has_node("/root/VoiceManager"):
		get_node("/root/VoiceManager").StopListening()
		
	if speed_commands.has(phrase):
		var selected_speed = speed_commands[phrase]
		
		#New speed should be applied here for tts
		tts.current_rate = selected_speed
		
		if status_label:
			status_label.text = "Speed set to : " + phrase
			
			#Confirmation for playing new speed
			
		tts.queue_text("Speed set to " + phrase + ".", 1)
		
		await tts.tts_queue_finished
		
		get_tree().change_scene_to_file("res://scenes/mainMenu.tscn")
		
		#Mic back on
		if has_node("/root/VoiceManager"):
			get_node("/root/VoiceManager").StartListening()
			
	else:
		tts.queue_text("Command not recognised.", 1)
		
		await tts.tts_queue_finished
		if has_node("/root/VoiceManager"):
			get_node("/root/VoiceManager").StartListening()
	



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
