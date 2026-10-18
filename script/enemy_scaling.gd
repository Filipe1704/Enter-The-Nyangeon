class_name EnemyScaling

# 敌人/Boss 的血量与伤害缩放统一入口。
# 返回最终倍率（已包含无尽倍率），供普通波次和 BossSpawner 共用。
static func hp_damage_multipliers(
	now_round: float,
	max_round: float,
	is_boss: bool,
	on_endless: bool,
	level_hp: float,
	level_damage: float,
	endless_hp: float,
	endless_boss_hp: float,
	endless_damage: float,
	round_hp_curve: Curve,
	round_boss_hp_curve: Curve,
	round_damage_curve: Curve,
	hp_growth_curve: Curve,
	hujiu: bool = false
) -> Dictionary:
	var safe_max: float = maxf(1.0, max_round)
	var hp_round_x: float = 0.0 if safe_max <= 1.0 else clamp((now_round - 1.0) / (safe_max - 1.0), 0.0, 1.0)
	var hp_curve: Curve = round_boss_hp_curve if is_boss else round_hp_curve
	var hp_base: float = hp_curve.sample(hp_round_x) if hp_curve != null else 1.0
	var hp_growth: float = hp_growth_curve.sample(now_round / safe_max) if hp_growth_curve != null else now_round / (safe_max * 0.5)
	var hp_lv: float = minf(level_hp, 3.0) if (hujiu and is_boss) else level_hp
	var hp_mult: float = hp_base * pow(hp_lv, hp_growth) if not on_endless else hp_base * pow(maxf(1.0, hp_lv), hp_growth)

	var damage_round_x: float = 0.0 if safe_max <= 1.0 else clamp((now_round - 1.0) / (safe_max - 1.0), 0.0, 1.0)
	var round_damage_mult: float = round_damage_curve.sample(damage_round_x) if round_damage_curve != null else 1.0
	var damage_mult: float = level_damage * round_damage_mult

	var endless_hp_value: float = endless_boss_hp if is_boss else endless_hp
	return {
		"hp": hp_mult * endless_hp_value,
		"damage": damage_mult * endless_damage,
	}
