extends Node

@export var normal_volume_db: float = -18.0
@export var ducked_volume_db: float = -30.0
@export var fade_duration: float = 0.35
@export var menu_music: AudioStream

var audio_player: AudioStreamPlayer
var volume_tween: Tween

var _is_tts_active: bool = false
var _is_stt_listening: bool = false

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.volume_db = normal_volume_db

	if menu_music:
		play_track(menu_music)

	call_deferred("_connect_listeners")

func _connect_listeners() -> void:
	if has_node("/root/TTS_Manager"):
		var tts = get_node("/root/TTS_Manager")
		if not tts.tts_started.is_connected(_on_tts_started):
			tts.tts_started.connect(_on_tts_started)
		if not tts.tts_queue_finished.is_connected(_on_tts_finished):
			tts.tts_queue_finished.connect(_on_tts_finished)
			
	# RESTORED: Listen to VoiceManager to duck audio during STT input
	if has_node("/root/VoiceManager"):
		var vm = get_node("/root/VoiceManager")
		if not vm.StatusChanged.is_connected(_on_stt_status_changed):
			vm.StatusChanged.connect(_on_stt_status_changed)

func play_track(track: AudioStream) -> void:
	if track == null:
		return
	if audio_player.stream == track and audio_player.playing:
		return

	audio_player.stream = track
	audio_player.play()
	_evaluate_volume(true)

func stop_track() -> void:
	audio_player.stop()

func _on_tts_started() -> void:
	_is_tts_active = true
	_evaluate_volume()

func _on_tts_finished() -> void:
	_is_tts_active = false
	_evaluate_volume()

func _on_stt_status_changed(is_listening: bool) -> void:
	_is_stt_listening = is_listening
	_evaluate_volume()

func _evaluate_volume(instant: bool = false) -> void:
	# Check both flags. If either system is active, duck the music.
	var should_duck = _is_tts_active or _is_stt_listening
	var target_db = ducked_volume_db if should_duck else normal_volume_db

	if instant:
		if volume_tween and volume_tween.is_running():
			volume_tween.kill()
		audio_player.volume_db = target_db
		return

	if volume_tween and volume_tween.is_running():
		volume_tween.kill()

	volume_tween = create_tween()
	volume_tween.tween_property(audio_player, "volume_db", target_db, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
