class_name OrbitalBarrageRemote
extends Node2D

const MARKER_SCENE: PackedScene = preload("res://scenes/effects/orbital_strike_marker.tscn")
const GOLIATH_PARTICLE_SCENE: PackedScene = preload("res://scenes/effects/goliath_cannon_particles.tscn")

var _markers: Dictionary = {}
var _particles: Array[Node2D] = []

# 客机纯表现：音效必须在这里回放，否则场地词条在客机侧完全无声。
# 与 host 侧 scenes/field_mods/orbital_barrage.gd 对齐——_spawn_next_target() 播 BlipSounds1，
# _fire_blast() 播 ExplosionSounds2（60ms 节流）；改一处务必同步另一处。
func add_marker(id: int, point: Vector2, remaining_seconds: float, play_sound: bool = true) -> void:
	if _markers.has(id):
		_remove_marker(id)
	var marker := MARKER_SCENE.instantiate() as OrbitalStrikeMarker
	if marker == null:
		return
	add_child(marker)
	marker.global_position = point
	marker.setup(maxf(0.1, remaining_seconds))
	marker.start_countdown()
	_markers[id] = marker
	if play_sound:
		SoundManager.play_sfx_throttled("BlipSounds1")

func marker_detonated(id: int) -> void:
	_remove_marker(id)

func spawn_blast(point: Vector2, radius: float) -> void:
	var blast := GOLIATH_PARTICLE_SCENE.instantiate() as GoliathCannonParticles
	if blast == null:
		return
	blast.z_index = 4
	add_child(blast)
	blast.global_position = point
	blast.rotation = randf_range(0.0, TAU)
	var scale := randf_range(1.0, 1.15)
	blast.scale = Vector2(scale, scale)
	blast.play_at(radius)
	_particles.append(blast)
	SoundManager.play_sfx_throttled("ExplosionSounds2", 60)
	var lifetime := get_tree().create_timer(1.2)
	lifetime.timeout.connect(func() -> void:
		if blast != null and is_instance_valid(blast):
			blast.queue_free()
	)

func apply_state(markers: Array) -> void:
	clear()
	for marker_state in markers:
		if marker_state is Dictionary:
			# 补发已存在的 marker 时不播音效（晚加入/重连不应补播一串提示音）
			add_marker(int(marker_state.get("id", -1)), marker_state.get("point", Vector2.ZERO), float(marker_state.get("remaining", 0.0)), false)

func clear() -> void:
	for marker in _markers.values():
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
	_markers.clear()
	for particle in _particles:
		if particle != null and is_instance_valid(particle):
			particle.queue_free()
	_particles.clear()

func _remove_marker(id: int) -> void:
	var marker = _markers.get(id)
	if marker != null and is_instance_valid(marker):
		marker.play_exit()
	_markers.erase(id)
