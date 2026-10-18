class_name BossSpawnAfterPhaseCondition
extends BossSpawnCondition

# 等待同一编队中指定下标的 Boss 到达 1 基阶段（phase=1 为第一个阶段）。
@export var boss_index: int = 0
@export var phase: int = 1
@export var extra_delay: float = 0.0

func is_met(ctx: BossSpawnContext) -> bool:
	if ctx == null:
		return false
	var reached_at := ctx.get_phase_reached_at(boss_index, phase)
	if reached_at < 0.0:
		return false
	return ctx.elapsed_seconds >= reached_at + maxf(0.0, extra_delay)
