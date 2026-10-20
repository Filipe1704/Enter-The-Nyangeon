class_name ExplosionAnim
extends Node2D

@export var explosion_sound_count: int = 4
@export var explosion_sound_interval: float = 0.25
@export var explosion_sound_volume_db: float = 0.0

@onready var smoke: GPUParticles2D = $smoke
@onready var explosion: GPUParticles2D = $explosion
@onready var explosion_sfx: AudioStreamPlayer2D = $ExplosionSfx

var _sound_generation: int = 0

func _ready() -> void:
	visible = false

func play() -> void:
	visible = true
	if explosion != null:
		explosion.emitting = true
		explosion.restart()
	if smoke != null:
		smoke.emitting = true
		smoke.restart()
	_sound_generation += 1
	_play_explosion_sounds(_sound_generation)

# 清场复用：只播爆炸粒子，不生成黑烟、不播音效。
func play_explosion_only(play_sound: bool = false) -> void:
	visible = true
	_sound_generation += 1
	if explosion_sfx != null:
		explosion_sfx.stop()
	if smoke != null:
		smoke.emitting = false
	if explosion != null:
		explosion.emitting = true
		explosion.restart()
	if play_sound:
		_play_explosion_sounds(_sound_generation)

func stop() -> void:
	_sound_generation += 1
	if explosion_sfx != null:
		explosion_sfx.stop()
	if explosion != null:
		explosion.emitting = false
	if smoke != null:
		smoke.emitting = false
	visible = false

func _play_explosion_sounds(generation: int) -> void:
	if explosion_sfx == null:
		return
	explosion_sfx.volume_db = explosion_sound_volume_db
	var count := maxi(explosion_sound_count, 0)
	for i in count:
		if generation != _sound_generation:
			return
		explosion_sfx.play()
		if i >= count - 1:
			break
		await get_tree().create_timer(explosion_sound_interval).timeout
