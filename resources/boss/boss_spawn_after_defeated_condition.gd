class_name BossSpawnAfterDefeatedCondition
extends BossSpawnCondition

# 等待 spawn_conditions 同一编队中指定下标的 Boss 死亡。
@export var boss_index: int = 0
@export var extra_delay: float = 0.0

func is_met(ctx: BossSpawnContext) -> bool:
	if ctx == null or not ctx.is_boss_defeated(boss_index):
		return false
	return ctx.elapsed_seconds >= ctx.get_defeated_at(boss_index) + maxf(0.0, extra_delay)
