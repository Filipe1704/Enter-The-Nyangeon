class_name FieldModEffect
extends Node2D

signal finished

const BOUNDS_READY_MAX_FRAMES := 60 # ≈1s @60Hz；等不到 walls 也照常启动（C1 墙射线兜底）

var chip: GameMode
var active: bool = false
var _on_start_done: bool = false
var _start_token: int = 0

func start(new_chip: GameMode) -> void:
	if active:
		stop()
	chip = new_chip
	active = true
	_on_start_done = false
	_start_token += 1
	var token := _start_token
	# 首轮场地词条可能在场景刚装载、物理还未就绪时启动：先等 MapBounds
	# 的墙射线可用，避免 MapChunks 用偏小的 SpawnMap 兜底边界构建（首帧抢跑）。
	var bounds_ok: bool = await _await_bounds_ready(BOUNDS_READY_MAX_FRAMES)
	if token != _start_token or not active or not is_inside_tree():
		return
	if not bounds_ok:
		push_warning("FieldModEffect: MapBounds not walls after %d physics frames (source=%s); starting with current boundary" % [BOUNDS_READY_MAX_FRAMES, MapBounds.get_boundary_source()])
	if not GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.connect(_on_global_tick)
	_on_start_done = true
	on_start()

func _await_bounds_ready(max_frames: int) -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var frames := maxi(1, max_frames)
	for i in frames:
		MapBounds.ensure_ready()
		if MapBounds.get_boundary_source() == &"walls":
			MapChunks.ensure_ready()
			return true
		if i < frames - 1:
			await tree.physics_frame
			if not active or not is_inside_tree():
				return false
	return MapBounds.get_boundary_source() == &"walls"

func stop() -> void:
	if not active:
		return
	active = false
	_start_token += 1
	if GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.disconnect(_on_global_tick)
	if _on_start_done:
		_on_start_done = false
		on_stop()

func finish() -> void:
	if not active:
		return
	stop()
	finished.emit()

func _exit_tree() -> void:
	if GameEvents != null and GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.disconnect(_on_global_tick)

func _on_global_tick() -> void:
	if active:
		on_tick()

func on_start() -> void:
	pass

func on_stop() -> void:
	pass

func on_tick() -> void:
	pass
