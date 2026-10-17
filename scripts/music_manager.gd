extends Node

@export var normal_volume_db: float = -12.0
@export var ducked_volume_db: float = -30.0
@export var fade_duration: float = 0.5
@export var menu_music: AudioStream

var audio_player: AudioStreamPlayer
var volume_tween: Tween

var _is_ducking: bool = false
var _is_stt_listening: bool = false

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	#if has_node("/root/MusicManager") and menu_music:
	#	MusicManager.play_track(menu_music)
	
	# Connect to the C# STT status signal
	if has_node("/root/VoiceManager"):
		if not VoiceManager.StatusChanged.is_connected(_on_stt_status_changed):
			VoiceManager.StatusChanged.connect(_on_stt_status_changed)

func play_track(track: AudioStream) -> void:
	if audio_player.stream == track and audio_player.playing:
		return
		
	audio_player.stream = track
	# Set to lowest volume initially to prevent a spike if starting during speech
	audio_player.volume_db = ducked_volume_db if _is_stt_listening or DisplayServer.tts_is_speaking() else normal_volume_db
	audio_player.play()

func stop_track() -> void:
	audio_player.stop()

func _on_stt_status_changed(is_listening: bool) -> void:
	_is_stt_listening = is_listening

func _process(_delta: float) -> void:
	# Poll the TTS engine status
	var tts_active = DisplayServer.tts_is_speaking()
	
	# Duck the audio if either system is active
	var requires_ducking = _is_stt_listening or tts_active
	
	if requires_ducking != _is_ducking:
		_is_ducking = requires_ducking
		_fade_to(ducked_volume_db if requires_ducking else normal_volume_db)

func _fade_to(target_db: float) -> void:
	if volume_tween and volume_tween.is_running():
		volume_tween.kill()
		
	volume_tween = create_tween()
	volume_tween.tween_property(audio_player, "volume_db", target_db, fade_duration).set_trans(Tween.TRANS_SINE)
