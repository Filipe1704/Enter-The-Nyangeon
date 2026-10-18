class_name BossSpawnWaveClearCondition
extends BossSpawnCondition

# 本回合至少生成过普通敌人，且当前普通敌人清空后入场；Boss 不计入清空判定。
@export var extra_delay: float = 0.0

func is_met(ctx: BossSpawnContext) -> bool:
	if ctx == null or not ctx.wave_clear or ctx.wave_clear_since < 0.0:
		return false
	return ctx.elapsed_seconds >= ctx.wave_clear_since + maxf(0.0, extra_delay)
