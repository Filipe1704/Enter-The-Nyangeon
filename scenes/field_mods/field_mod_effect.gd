class_name FieldModEffect
extends Node2D

signal finished

var chip: GameMode
var active: bool = false

func start(new_chip: GameMode) -> void:
	if active:
		stop()
	chip = new_chip
	active = true
	if not GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.connect(_on_global_tick)
	on_start()

func stop() -> void:
	if not active:
		return
	active = false
	if GameEvents.global_time_count.is_connected(_on_global_tick):
		GameEvents.global_time_count.disconnect(_on_global_tick)
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
