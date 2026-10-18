class_name BossSpawnDelayCondition
extends BossSpawnCondition

# 从遭遇触发时刻开始读秒；seconds <= 0 表示立即入场。
@export var seconds: float = 0.0

func is_met(ctx: BossSpawnContext) -> bool:
	return ctx != null and ctx.elapsed_seconds >= maxf(0.0, seconds)
