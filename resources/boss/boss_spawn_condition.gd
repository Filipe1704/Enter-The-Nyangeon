class_name BossSpawnCondition
extends Resource

# 单个 Boss 的入场条件基类。按时间/事件/波次等条件由内置子类提供；
# mod 可继承本类并实现 is_met(ctx)，条件只读 ctx。
func is_met(_ctx: BossSpawnContext) -> bool:
	return false
