class_name BossSpawnContext
extends RefCounted

# 分时入场的只读上下文。自定义条件通过它读取遭遇进度，
# 不要直接修改 encounter/controller（入场调度由 BossRoundController 负责）。
var encounter = null
var controller: Node = null
var elapsed_seconds: float = 0.0
var total_count: int = 0
var spawned_count: int = 0
var defeated_count: int = 0
var active_boss_count: int = 0
var normal_enemy_count: int = 0
var normal_spawn_seen: bool = false
var wave_clear: bool = false
var wave_clear_since: float = -1.0
var defeated_at_seconds: Dictionary = {}
var phase_at_seconds: Dictionary = {}

func is_boss_defeated(index: int) -> bool:
	return defeated_at_seconds.has(index)

func get_defeated_at(index: int) -> float:
	return float(defeated_at_seconds.get(index, -1.0))

func get_phase_reached_at(index: int, phase: int) -> float:
	var phases: Dictionary = phase_at_seconds.get(index, {})
	return float(phases.get(phase, -1.0))
