extends Node

@onready var tts_timer: Timer = $Timer

func _ready() -> void:
	tts_timer.timeout.connect(_on_timer_timeout)
