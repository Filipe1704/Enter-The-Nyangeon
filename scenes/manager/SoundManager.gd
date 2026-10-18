extends Node

enum Bus { MASTER, SFX, BGM, VOICE }

signal cut_finish
signal fade_out_end

@onready var sfx = $SFX
@onready var voice = $VOICE
@onready var talk: Node = $Talk
@onready var bgm_player = $BGM/BGMPlayer
@onready var animation_player: AnimationPlayer = $BGM/AnimationPlayer
@onready var voice_player: AudioStreamPlayer = $SupportVoice/VoicePlayer

const BGM_FADE_DEFAULT := 1.0
const BGM_SILENCE_DB := -60.0
var _bgm_fade_tween: Tween = null
var _bgm_base_db: float = 0.0
var game_end: bool = false

const SFX_THROTTLE_DEFAULT_MS := 40
var _sfx_frame_guard: Dictionary = {}
var _sfx_last_ms: Dictionary = {}

func _get_sfx(sfx_name: String) -> AudioStreamPlayer:
	if sfx == null:
		return null
	return sfx.get_node_or_null(sfx_name) as AudioStreamPlayer

func _get_nested(root: Node, player_name: String, type: String) -> AudioStreamPlayer:
	if root == null:
		return null
	var group_node: Node = root.get_node_or_null(player_name)
	if group_node == null:
		return null
	return group_node.get_node_or_null(type) as AudioStreamPlayer

func play_sfx(sfx_name: String):
	var player := _get_sfx(sfx_name)
	if player == null:
		return
	player.play()

func play_sfx_once(sfx_name: String):
	var player := _get_sfx(sfx_name)
	if player == null:
		return
	if player.playing:
		return
	player.play()

# 高频受击音效节流：同一 process 帧最多 1 次，且全局最小间隔 min_interval_ms
func play_sfx_throttled(sfx_name: String, min_interval_ms: int = SFX_THROTTLE_DEFAULT_MS):
	var frame := Engine.get_process_frames()
	if _sfx_frame_guard.get(sfx_name, -1) == frame:
		return
	var now := Time.get_ticks_msec()
	if now - int(_sfx_last_ms.get(sfx_name, -1000000000)) < min_interval_ms:
		return
	_sfx_frame_guard[sfx_name] = frame
	_sfx_last_ms[sfx_name] = now
	play_sfx(sfx_name)

func play_loop_sfx(sfx_name: String):
	var player := _get_sfx(sfx_name)
	if player == null or player.playing:
		return
	player.play()

func stop_sfx(sfx_name: String):
	var player := _get_sfx(sfx_name)
	if player == null:
		return
	player.stop()

func play_support_voice(stream: AudioStream):
	if voice_player == null or stream == null:
		return
	if voice_player.playing:
		return
	voice_player.stream = stream
	voice_player.play()

func play_voice(player_name: String, type: String):
	var player := _get_nested(voice, player_name, type)
	if player == null:
		return
	player.play()

func play_talk(player_name: String, type: String):
	var player := _get_nested(talk, player_name, type)
	if player == null:
		return
	player.play()

# 设定非淡变目标音量（暂停调暗等走这里，避免被淡出/淡入清掉）
func set_bgm_base_db(db: float) -> void:
	_bgm_base_db = db
	if bgm_player == null:
		return
	if _bgm_fade_tween == null or not _bgm_fade_tween.is_running():
		bgm_player.volume_db = db


func _bgm_kill_fade() -> void:
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_fade_tween = null


func _bgm_fade_in(fade_in: float) -> void:
	if bgm_player == null:
		return
	if fade_in > 0.0:
		bgm_player.volume_db = BGM_SILENCE_DB
		bgm_player.play()
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(bgm_player, "volume_db", _bgm_base_db, fade_in)
	else:
		bgm_player.volume_db = _bgm_base_db
		bgm_player.play()


func play_bgm_cut(stream: AudioStream, fade_in: float = 0.0):
	if bgm_player == null or stream == null:
		return
	if bgm_player.stream == stream and bgm_player.playing:
		return
	_bgm_kill_fade()
	bgm_player.stream = stream
	_bgm_fade_in(fade_in)
	await bgm_player.finished
	cut_finish.emit()


func play_bgm(stream: AudioStream, fade_in: float = 0.0):
	if bgm_player == null or stream == null:
		return
	if bgm_player.stream == stream and bgm_player.playing:
		return
	_bgm_kill_fade()
	bgm_player.stream = stream
	_bgm_fade_in(fade_in)


func bgm_fade_out(fade: float = BGM_FADE_DEFAULT):
	if bgm_player == null:
		return
	if bgm_player.playing and bgm_player.volume_db > BGM_SILENCE_DB:
		_bgm_base_db = bgm_player.volume_db
	_bgm_kill_fade()
	if bgm_player.playing and fade > 0.0:
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(bgm_player, "volume_db", BGM_SILENCE_DB, fade)
		await _bgm_fade_tween.finished
	bgm_player.stop()
	bgm_player.volume_db = _bgm_base_db
	fade_out_end.emit()


func bgm_slow_fade_out(stream: AudioStream, fade_out: float = 4.0, fade_in: float = 1.0):
	await bgm_fade_out(fade_out)
	if game_end == true:
		return
	play_bgm_cut(stream, fade_in)

func get_volume(bus_index: int):
	if bus_index < 0 or bus_index >= AudioServer.bus_count:
		return 1.0
	var db := AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(db)

func set_volume(bus_index: int, v: float):
	if bus_index < 0 or bus_index >= AudioServer.bus_count:
		return
	var db := linear_to_db(v)
	AudioServer.set_bus_volume_db(bus_index, db)
