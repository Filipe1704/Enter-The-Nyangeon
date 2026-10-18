class_name BossEncounter
extends RefCounted

# 一次 Boss 遭遇的运行实例。数据在 BossEncounterEntry，这里只记录本次进度。
enum State {
	PENDING,
	SPAWNING,
	ENTERING,
	FIGHTING,
	SETTLING,
	ENDED,
	CANCELLED,
}

var entry: BossEncounterEntry
var state: State = State.PENDING
var bosses: Array[BossEnemy] = []
var spawned_count: int = 0
var defeated_count: int = 0
var result: Dictionary = {}
var hp_group: BossHPGroup = null
var phase_queue: Array = []
var phase_busy: bool = false
var spawn_stopped: bool = false
var missed: bool = false

# 分时入场 / 首个 Boss 计时运行态。
var spawn_generation: int = 0
var spawn_elapsed_seconds: float = 0.0
var pending_spawns: Array = []
var first_boss_ready: bool = false
var first_spawn_timed_out: bool = false
var timed_timer_started: bool = false
var defeated_at_seconds: Dictionary = {}
var phase_at_seconds: Dictionary = {}
var wave_clear_since: float = -1.0

func _init(p_entry: BossEncounterEntry) -> void:
	entry = p_entry

func is_primary() -> bool:
	if entry == null:
		return false
	return entry.trigger == BossEncounterEntry.Trigger.ROUND_START or entry.role == BossEncounterEntry.Role.PRIMARY

func profile() -> BossRoundProfile:
	if entry == null or entry.encounter == null:
		return null
	if entry.encounter.profile_override != null:
		return entry.encounter.profile_override
	for card in entry.encounter.bosses:
		if card != null and card.round_profile != null:
			return card.round_profile
	return null

func boss_cards() -> Array[BossCard]:
	if entry == null or entry.encounter == null:
		return []
	return entry.encounter.bosses

func total_bosses() -> int:
	return boss_cards().size()

func spawn_mode() -> int:
	if entry == null or entry.encounter == null:
		return BossRoundEntry.SpawnMode.SINGLE
	return entry.encounter.spawn_mode

func end_condition() -> int:
	if entry == null or entry.encounter == null:
		return BossRoundEntry.EndCondition.ALL_DEFEATED
	return entry.encounter.end_condition

func current_card() -> BossCard:
	var cards := boss_cards()
	if spawned_count < 0 or spawned_count >= cards.size():
		return null
	return cards[spawned_count]

func is_complete() -> bool:
	var total := total_bosses()
	if total <= 0:
		return true
	match end_condition():
		BossRoundEntry.EndCondition.ANY_DEFEATED:
			return defeated_count >= 1
		BossRoundEntry.EndCondition.SEQUENCE_COMPLETE:
			return spawned_count >= total and defeated_count >= total
		_:
			return spawned_count >= total and defeated_count >= total

func has_next_sequence() -> bool:
	if spawn_mode() != BossRoundEntry.SpawnMode.SEQUENCE:
		return false
	return spawned_count < total_bosses()
