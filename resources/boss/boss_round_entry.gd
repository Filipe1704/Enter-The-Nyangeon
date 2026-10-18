extends Resource
class_name BossRoundEntry

# 一次 Boss 遭遇的内容：打哪些 Boss、怎么生成、何时算结束。
enum SpawnMode {
	SINGLE,
	SEQUENCE,
	SIMULTANEOUS,
	SCHEDULED, # spawn_conditions 按索引分时入场
}

enum EndCondition {
	ALL_DEFEATED,
	ANY_DEFEATED,
	SEQUENCE_COMPLETE,
}

@export var bosses: Array[BossCard] = []
@export var spawn_mode: SpawnMode = SpawnMode.SINGLE
@export var end_condition: EndCondition = EndCondition.ALL_DEFEATED
@export var profile_override: BossRoundProfile
@export var positions: Array[Vector2] = []
# 分时入场：与 bosses 下标对齐；为空时沿用 spawn_mode 的旧行为。
@export var spawn_conditions: Array[BossSpawnCondition] = []
# HBox 同时显示的最大 Boss 血条槽位；超出的 Boss 进入等待队列。
@export var max_visible_hp_bars: int = 4
@export var clear_minions_on_enter: bool = false
@export var stop_normal_spawns: bool = false
@export var reward_scene: PackedScene
