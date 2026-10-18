extends Resource
class_name BossRoundProfile

# Boss 回合规则。单机默认值尽量贴近现有 goliath/erosion_tower_group 行为，
# phase 2 起由 BossRoundController 读取；未配置 profile 的旧 Boss 继续走旧路径。
enum TimeoutMode {
	RAGE,
	END,
	FAIL,
	CUSTOM,
}

@export var time_limit: float = 90.0
@export var timeout_mode: TimeoutMode = TimeoutMode.RAGE
@export var rage_interval_ticks: int = 5
@export var fever_buff: Buff
@export var end_on_death: bool = true
@export var end_on_pickup: bool = false
@export var end_delay: float = 0.0
@export var final_boss: bool = false
# upgrade / victory / game_over / continue
@export var victory_mode: StringName = &"upgrade"
@export var boss_hp_curve: Curve
@export var boss_damage_curve: Curve
