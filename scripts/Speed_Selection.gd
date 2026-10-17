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
		vm.connect("PhraseRecognised", Callable(self, "_on_phase_recognised"))



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
