extends Resource
class_name BossEncounterEntry

# Boss 遭遇的编排行。ROUND_START 走回合开始；其余触发器在 Phase 2.5 已启用。
# 中途乱入的结算与普通刷怪策略见 IntruderEndMode / NormalSpawnMode。
enum Trigger {
	ROUND_START,
	TIME,
	KILLS,
	SPAWN_COUNT,
	ENEMY_COUNT,
	WAVE_CLEAR,
	BOSS_PHASE,
	CUSTOM,
}

enum Role {
	PRIMARY,
	ADD,
}

enum TimerMode {
	NORMAL_CONTINUES,
	PAUSE_NORMAL,
	REPLACE_NORMAL,
	EXTEND_NORMAL,
}

enum OnNormalTimeout {
	END_WITH_BOSS,
	HOLD_UNTIL_DEAD,
	BOSS_ESCAPES,
	FAIL,
}

# BOSS_FEVER / MANDATORY_KILL 的 Boss 计时起点。
enum BossTimerStart {
	ENCOUNTER_START,
	FIRST_BOSS_READY,
}

# 中途乱入的结算模式。ROUND_START 条目忽略该字段。
enum IntruderEndMode {
	ROUND_TIMER,      # 普通回合计时（含 extra_time）到点未杀则 missed
	BOSS_FEVER,       # Boss 独立计时，超时进入 fever；fever 结束未杀则 missed
	MANDATORY_KILL,   # 必须击杀，回合不能提前结束
}

enum NormalSpawnMode {
	CONTINUE,              # 不改变普通刷怪
	STOP_WHILE_BOSS_ALIVE, # 乱入期间停刷，Boss 死亡后恢复
	STOP_FOR_ROUND,        # 乱入后本回合不再刷怪
}

@export var encounter: BossRoundEntry
@export var trigger: Trigger = Trigger.ROUND_START
@export var trigger_value: float = 0.0
@export var trigger_name: StringName = &""
@export var role: Role = Role.ADD
@export var timer_mode: TimerMode = TimerMode.NORMAL_CONTINUES
@export var on_normal_timeout: OnNormalTimeout = OnNormalTimeout.END_WITH_BOSS
# 中途乱入专用。
@export var intruder_end_mode: IntruderEndMode = IntruderEndMode.ROUND_TIMER
@export var boss_timer_start: BossTimerStart = BossTimerStart.FIRST_BOSS_READY
# FIRST_BOSS_READY 的兜底：从遭遇触发起等待首个 Boss 入场；<=0 关闭。
@export var max_first_spawn_wait: float = 30.0
@export var extra_time: float = 0.0
@export var fever_duration: float = 15.0
@export var normal_spawn_mode: NormalSpawnMode = NormalSpawnMode.CONTINUE
# 旧字段：true 等价于 STOP_FOR_ROUND（仅在中途条目且 normal_spawn_mode=CONTINUE 时生效）。
@export var stop_normal_spawns: bool = false
@export var clear_minions_on_enter: bool = false
@export var end_round_on_defeat: bool = false
# full / short / none
@export var cinematic_policy: StringName = &"full"
@export var once: bool = true
@export var weight: float = 1.0
@export var round_min: int = 1
@export var round_max: int = 9999
@export var group: String = ""
@export var enabled: bool = true
