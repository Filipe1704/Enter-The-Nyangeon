class_name BossRoundController
extends Node

# Boss 回合唯一权威：选择遭遇、生成 Boss、决定回合模式与结算。
signal boss_encounter_started(entry: BossEncounterEntry, plan: Dictionary)

signal boss_encounter_ended(entry: BossEncounterEntry, result: Dictionary)
signal boss_joined(boss: BossEnemy, entry: BossEncounterEntry)
signal boss_round_settled(result: Dictionary)
signal boss_trigger_fired(entry: BossEncounterEntry, trigger_name: StringName)

const SPAWN_TICK_SECONDS := 0.1

@export var enable_mid_round_encounters: bool = true
# 联机预留：host=true；客机由 coop mod 置 false 并跳过本地结算。
var is_authority: bool = true

var spawner: BossSpawner
var encounters: Array[BossEncounter] = []
var primary: BossEncounter = null
var current_plan: Dictionary = {}

var boss_round_active: bool = false
var encounter_active: bool = false
var _pending_mid_entries: Array[BossEncounterEntry] = []
var _last_boss_id: String = ""
var _warned_mid: bool = false
var _settling: bool = false
var _rotation: Dictionary = {}

var _current_round_index: int = 0
var _current_group: String = ""
var _current_is_endless: bool = false
var _current_endless_index: int = 0
var _elapsed_ticks: int = 0
var _kill_count: int = 0
var _spawn_count: int = 0
var _round_spawn_seen: bool = false
var _timed_intruder: BossEncounter = null
var _fever_intruder: BossEncounter = null
var _fever_generation: int = 0
var _spawn_tick_accum: float = 0.0

func _ready() -> void:
	add_to_group("BossRoundController")
	spawner = BossSpawner.new()
	spawner.name = "BossSpawner"
	add_child(spawner)
	GameEvents.boss_spawned.connect(_on_boss_spawned)
	GameEvents.round_end.connect(_on_round_finished)
	GameEvents.game_over.connect(_on_game_over)
	GameEvents.first_round_add.connect(_reset_rotation)
	GameEvents.global_time_count.connect(_on_global_time_count)
	GameEvents.enemy_dead_position.connect(_on_enemy_dead_position)
	GameEvents.enemy_spawn.connect(_on_enemy_spawn)
	GameEvents.boss_phase_changed.connect(_on_global_boss_phase_changed)
	_connect_round_timer.call_deferred()

func plan_for_round(round_index: int, group: String, is_endless: bool, endless_round: int = 0) -> Dictionary:
	if _current_round_index != round_index:
		cancel_for_round_end()
		_reset_mid_round_state()
		current_plan.clear()
		_current_round_index = round_index
		_current_group = group
		_current_is_endless = is_endless
		_current_endless_index = endless_round
	if ExtensionHooks.is_hook_active("boss_plan_override"):
		var override = ExtensionHooks.boss_plan_override.call(round_index, group, is_endless, endless_round)
		if override is Dictionary and not override.is_empty():
			return override
	var schedules := _get_schedules()
	if schedules.is_empty():
		_arm_mid_entries(round_index, group, is_endless, endless_round)
		return {}
	for schedule in schedules:
		if schedule == null or not schedule.enabled:
			continue
		var pool: Array[BossEncounterEntry] = schedule.endless_entries if is_endless else schedule.entries
		if pool.is_empty():
			pool = schedule.entries
		var target_round := endless_round if is_endless else round_index
		var entry := _pick_entry(pool, target_round, group, is_endless, schedule)
		if entry == null:
			continue
		return _make_plan(entry, round_index, is_endless, endless_round)
	_arm_mid_entries(round_index, group, is_endless, endless_round)
	return {}

func begin_round(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	current_plan = plan
	var entry: BossEncounterEntry = plan.get("entry")
	if entry == null or entry.encounter == null or entry.encounter.bosses.is_empty():
		return
	_start_encounter(entry, true, plan)

func _start_encounter(entry: BossEncounterEntry, is_round_start: bool, plan: Dictionary) -> void:
	var encounter := BossEncounter.new(entry)
	encounters.append(encounter)
	encounter_active = true
	if is_round_start:
		if encounter.is_primary():
			primary = encounter
			var mode := _effective_timer_mode(entry)
			boss_round_active = mode == BossEncounterEntry.TimerMode.REPLACE_NORMAL
			if boss_round_active:
				# 先设置 primary，round_timer.boss_round() 会通过 get_profile() 读取。
				GameEvents.emit_boss_round_start()
			elif mode == BossEncounterEntry.TimerMode.PAUSE_NORMAL:
				var rt := _round_timer()
				if rt != null and rt.has_method("pause_normal_round"):
					rt.pause_normal_round()
		_arm_mid_entries(
			plan.get("round", _current_round_index),
			_current_group,
			plan.get("is_endless", _current_is_endless),
			plan.get("endless_round", _current_endless_index)
		)
		if entry.stop_normal_spawns or entry.encounter.stop_normal_spawns:
			GameEvents.emit_spawn_stop()
	else:
		_apply_intruder_mode(encounter)
	boss_encounter_started.emit(entry, plan)
	GameEvents.emit_boss_encounter_started(entry, plan)
	ExtensionHooks.notify_named("on_boss_encounter_started", [entry, plan])
	if entry.clear_minions_on_enter or entry.encounter.clear_minions_on_enter:
		_clear_minions()
	encounter.state = BossEncounter.State.SPAWNING
	if _uses_scheduled_spawns(encounter):
		_init_scheduled_spawns(encounter)
	else:
		_spawn_next(encounter)

func arm_mid_round_encounters(entries: Array[BossEncounterEntry]) -> void:
	_pending_mid_entries = entries.duplicate()
	if not _pending_mid_entries.is_empty() and not enable_mid_round_encounters and not _warned_mid:
		_warned_mid = true
		push_warning("[BossRoundController] 中途加入 Boss 的触发器已预留但未启用（enable_mid_round_encounters=false）")

func fire_trigger(name: StringName) -> void:
	if not enable_mid_round_encounters:
		push_warning("[BossRoundController] fire_trigger(%s) 当前未启用。" % name)
		return
	for entry in _pending_mid_entries.duplicate():
		if entry == null or not entry.enabled:
			continue
		if entry.trigger != BossEncounterEntry.Trigger.CUSTOM:
			continue
		if entry.trigger_name == name:
			_pending_mid_entries.erase(entry)
			boss_trigger_fired.emit(entry, name)
			begin_encounter(entry)
			return

func _reset_mid_round_state() -> void:
	_pending_mid_entries.clear()
	_elapsed_ticks = 0
	_kill_count = 0
	_spawn_count = 0
	_round_spawn_seen = false
	_fever_generation += 1
	_timed_intruder = null
	_fever_intruder = null

func _arm_mid_entries(round_index: int, group: String, is_endless: bool, endless_round: int) -> void:
	_pending_mid_entries.clear()
	if not enable_mid_round_encounters:
		return
	var target_round := endless_round if is_endless else round_index
	for schedule in _get_schedules():
		if schedule == null or not schedule.enabled:
			continue
		var pool: Array[BossEncounterEntry] = schedule.endless_entries if is_endless else schedule.entries
		if pool.is_empty():
			pool = schedule.entries
		for entry in pool:
			if entry == null or not entry.enabled or entry.encounter == null:
				continue
			if entry.trigger == BossEncounterEntry.Trigger.ROUND_START:
				continue
			if target_round < entry.round_min or target_round > entry.round_max:
				continue
			if entry.group != "" and entry.group != group:
				continue
			if not _pending_mid_entries.has(entry):
				_pending_mid_entries.append(entry)

func _connect_round_timer() -> void:
	var rt := _round_timer()
	if rt != null and rt.has_signal("boss_timeout") and not rt.boss_timeout.is_connected(_on_boss_timeout):
		rt.boss_timeout.connect(_on_boss_timeout)

func _process(delta: float) -> void:
	if encounters.is_empty():
		_spawn_tick_accum = 0.0
		return
	_spawn_tick_accum += delta
	if _spawn_tick_accum < SPAWN_TICK_SECONDS:
		return
	var step := _spawn_tick_accum
	_spawn_tick_accum = 0.0
	_tick_scheduled_spawns(step)

func _on_global_time_count() -> void:
	if not enable_mid_round_encounters or _pending_mid_entries.is_empty():
		return
	_elapsed_ticks += 1
	_evaluate_mid_triggers(-1)

func _on_enemy_dead_position(_dead_position: Vector2) -> void:
	_evaluate_all_scheduled_spawns()
	if not enable_mid_round_encounters or _pending_mid_entries.is_empty():
		return
	_kill_count += 1
	_evaluate_mid_triggers(-1)

func _on_enemy_spawn() -> void:
	_spawn_count += 1
	_round_spawn_seen = true
	_evaluate_all_scheduled_spawns()
	if not enable_mid_round_encounters or _pending_mid_entries.is_empty():
		return
	_evaluate_mid_triggers(-1)

func _on_global_boss_phase_changed(_boss: Node, phase: int) -> void:
	_evaluate_all_scheduled_spawns()
	if not enable_mid_round_encounters or _pending_mid_entries.is_empty():
		return
	_evaluate_mid_triggers(phase)

func _evaluate_mid_triggers(phase: int) -> void:
	for entry in _pending_mid_entries.duplicate():
		if not _matches_mid_trigger(entry, phase):
			continue
		_pending_mid_entries.erase(entry)
		boss_trigger_fired.emit(entry, StringName(""))
		begin_encounter(entry)
		return

func _matches_mid_trigger(entry: BossEncounterEntry, phase: int) -> bool:
	match entry.trigger:
		BossEncounterEntry.Trigger.TIME:
			return _elapsed_ticks >= int(ceil(entry.trigger_value * 10.0))
		BossEncounterEntry.Trigger.KILLS:
			return _kill_count >= int(entry.trigger_value)
		BossEncounterEntry.Trigger.SPAWN_COUNT:
			return _spawn_count >= int(entry.trigger_value)
		BossEncounterEntry.Trigger.ENEMY_COUNT:
			return _round_spawn_seen and PoolManager.active_enemy_count <= int(entry.trigger_value)
		BossEncounterEntry.Trigger.WAVE_CLEAR:
			return _round_spawn_seen and PoolManager.active_enemy_count == 0
		BossEncounterEntry.Trigger.BOSS_PHASE:
			return phase >= 0 and phase >= int(entry.trigger_value)
		_:
			return false

func _apply_spawn_policy(encounter: BossEncounter) -> void:
	var entry := encounter.entry
	var stop := entry.normal_spawn_mode != BossEncounterEntry.NormalSpawnMode.CONTINUE
	if not stop and entry.stop_normal_spawns:
		stop = true
	if not stop and entry.encounter != null and entry.encounter.stop_normal_spawns:
		stop = true
	if stop:
		encounter.spawn_stopped = true
		GameEvents.emit_spawn_stop()

func _resume_spawns_if_needed(encounter: BossEncounter) -> void:
	if encounter == null or not encounter.spawn_stopped:
		return
	if encounter.entry.normal_spawn_mode != BossEncounterEntry.NormalSpawnMode.STOP_WHILE_BOSS_ALIVE:
		return
	encounter.spawn_stopped = false
	for other in encounters:
		if other != encounter and other.spawn_stopped and other.state not in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			return
	GameEvents.emit_spawn_restart()

func _apply_intruder_mode(encounter: BossEncounter) -> void:
	var entry := encounter.entry
	_apply_spawn_policy(encounter)
	match entry.intruder_end_mode:
		BossEncounterEntry.IntruderEndMode.ROUND_TIMER:
			var rt := _round_timer()
			if rt != null:
				if entry.extra_time > 0.0 and rt.has_method("extend_normal_round"):
					rt.extend_normal_round(entry.extra_time)
				if rt.has_method("set_boss_encounter_active"):
					rt.set_boss_encounter_active(true)
		BossEncounterEntry.IntruderEndMode.BOSS_FEVER, BossEncounterEntry.IntruderEndMode.MANDATORY_KILL:
			_timed_intruder = encounter
			boss_round_active = true
			var rt := _round_timer()
			if rt != null and rt.has_method("pause_normal_round"):
				rt.pause_normal_round()
			if entry.boss_timer_start == BossEncounterEntry.BossTimerStart.ENCOUNTER_START:
				_start_timed_boss_timer(encounter)

func _on_boss_timeout(_profile: BossRoundProfile) -> void:
	if _timed_intruder == null:
		return
	_cancel_scheduled_spawns(_timed_intruder)
	if _timed_intruder.entry.intruder_end_mode != BossEncounterEntry.IntruderEndMode.BOSS_FEVER:
		return
	var encounter := _timed_intruder
	_fever_intruder = encounter
	_fever_generation += 1
	var generation := _fever_generation
	var duration := maxf(0.1, encounter.entry.fever_duration)
	await get_tree().create_timer(duration, true, false, true).timeout
	if generation != _fever_generation or _timed_intruder != encounter:
		return
	if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	await _resolve_missed(encounter, &"fever_timeout", true)

func hold_normal_round_for_boss() -> void:
	var encounter := _timed_intruder
	if encounter == null:
		for e in encounters:
			if e.state not in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED] and e.entry.intruder_end_mode == BossEncounterEntry.IntruderEndMode.MANDATORY_KILL:
				encounter = e
				break
	if encounter == null:
		return
	_timed_intruder = encounter
	boss_round_active = true
	_start_timed_boss_timer(encounter)

func _start_timed_boss_timer(encounter: BossEncounter) -> void:
	if encounter == null or encounter.timed_timer_started:
		return
	encounter.timed_timer_started = true
	var rt := _round_timer()
	if rt != null and rt.has_method("start_boss_encounter_timer"):
		rt.start_boss_encounter_timer(encounter.profile(), true)

func resolve_normal_timeout_missed() -> void:
	for encounter in encounters.duplicate():
		if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		if encounter.entry.intruder_end_mode != BossEncounterEntry.IntruderEndMode.ROUND_TIMER:
			continue
		_cancel_scheduled_spawns(encounter)
		await _resolve_missed(encounter, &"round_timer_end", false)

func _resolve_missed(encounter: BossEncounter, reason: StringName, emit_round_end: bool) -> void:
	if encounter == null or encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	_cancel_scheduled_spawns(encounter)
	encounter.missed = true
	encounter.state = BossEncounter.State.SETTLING
	_settling = true
	if encounter == _timed_intruder:
		var rt := _round_timer()
		if rt != null and rt.has_method("stop_boss_encounter_timer"):
			rt.stop_boss_encounter_timer()
	for boss in encounter.bosses:
		if boss == null or not is_instance_valid(boss) or boss._boss_dead:
			continue
		await _wait_boss_exit(boss)
		_remove_boss_bar(encounter, boss)
		if is_instance_valid(boss):
			boss.despawn_after_death()
	_settling = false
	if encounter.state == BossEncounter.State.CANCELLED:
		return
	_finish_encounter(encounter, reason, emit_round_end)

func _wait_boss_exit(boss: BossEnemy) -> void:
	var tree := get_tree()
	if tree == null:
		boss.play_exit_anim()
		return
	var done: Array[bool] = [false]
	var cb := func():
		done[0] = true
	boss.boss_exit_finished.connect(cb)
	boss.play_exit_anim()
	var deadline := Time.get_ticks_msec() + 8000
	while not done[0] and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.05, true, false, true).timeout
	if boss.boss_exit_finished.is_connected(cb):
		boss.boss_exit_finished.disconnect(cb)

func begin_encounter(entry: BossEncounterEntry) -> void:
	if entry == null or entry.encounter == null or entry.encounter.bosses.is_empty():
		return
	var plan := _make_plan(entry, _current_round(), PlayerData.on_endless, _current_endless_round())
	current_plan = plan
	_start_encounter(entry, false, plan)

func on_normal_round_timeout() -> int:
	for encounter in encounters:
		if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		match encounter.entry.intruder_end_mode:
			BossEncounterEntry.IntruderEndMode.ROUND_TIMER:
				return BossEncounterEntry.OnNormalTimeout.BOSS_ESCAPES
			BossEncounterEntry.IntruderEndMode.MANDATORY_KILL:
				return BossEncounterEntry.OnNormalTimeout.HOLD_UNTIL_DEAD
			BossEncounterEntry.IntruderEndMode.BOSS_FEVER:
				return BossEncounterEntry.OnNormalTimeout.HOLD_UNTIL_DEAD
	return BossEncounterEntry.OnNormalTimeout.END_WITH_BOSS

func request_end(reason: StringName) -> void:
	if primary == null:
		return
	if primary.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	_finish_encounter(primary, reason)

func cancel_for_round_end() -> void:
	if encounters.is_empty():
		primary = null
		boss_round_active = false
		encounter_active = false
		_settling = false
		return
	for encounter in encounters:
		if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		_cancel_scheduled_spawns(encounter)
		encounter.state = BossEncounter.State.CANCELLED
		for boss in encounter.bosses:
			if boss != null and is_instance_valid(boss):
				boss.despawn_immediate()
		_dispose_hp_group(encounter)
	BossCinematic.release(self)
	encounters.clear()
	primary = null
	boss_round_active = false
	encounter_active = false
	_settling = false
	_reset_mid_round_state()

func get_profile() -> BossRoundProfile:
	if _timed_intruder != null:
		return _timed_intruder.profile()
	if primary != null:
		return primary.profile()
	if current_plan.has("profile"):
		return current_plan.get("profile")
	return null

func get_active_bosses() -> Array[BossEnemy]:
	var out: Array[BossEnemy] = []
	for encounter in encounters:
		for boss in encounter.bosses:
			if boss != null and is_instance_valid(boss) and not boss._boss_dead:
				out.append(boss)
	return out
func is_encounter_active() -> bool:
	return encounter_active


func is_boss_round_active() -> bool:
	return boss_round_active

func is_settling() -> bool:
	return _settling

func get_current_plan() -> Dictionary:
	return current_plan

func _uses_scheduled_spawns(encounter: BossEncounter) -> bool:
	if encounter == null or encounter.entry == null or encounter.entry.encounter == null:
		return false
	return encounter.entry.encounter.spawn_mode == BossRoundEntry.SpawnMode.SCHEDULED \
		or not encounter.entry.encounter.spawn_conditions.is_empty()

func _init_scheduled_spawns(encounter: BossEncounter) -> void:
	encounter.spawn_generation += 1
	encounter.spawn_elapsed_seconds = 0.0
	encounter.first_boss_ready = false
	encounter.first_spawn_timed_out = false
	encounter.wave_clear_since = -1.0
	encounter.defeated_at_seconds.clear()
	encounter.phase_at_seconds.clear()
	encounter.pending_spawns.clear()
	var cards := encounter.boss_cards()
	var conditions := encounter.entry.encounter.spawn_conditions
	if not conditions.is_empty() and conditions.size() != cards.size():
		push_warning("[BossRoundController] spawn_conditions 数量(%d)与 bosses(%d)不一致，缺失项按立即入场处理" % [conditions.size(), cards.size()])
	for i in cards.size():
		var condition: BossSpawnCondition = null
		if i < conditions.size():
			condition = conditions[i]
		encounter.pending_spawns.append({"index": i, "condition": condition})
	_evaluate_scheduled_spawns(encounter)

func _tick_scheduled_spawns(delta: float) -> void:
	for encounter in encounters:
		if encounter == null or encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		encounter.spawn_elapsed_seconds += maxf(0.0, delta)
		_refresh_wave_clear(encounter)
		_evaluate_scheduled_spawns(encounter)
		_check_first_spawn_timeout(encounter)

func _evaluate_all_scheduled_spawns() -> void:
	for encounter in encounters:
		if encounter == null or encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		_refresh_wave_clear(encounter)
		_evaluate_scheduled_spawns(encounter)

func _evaluate_scheduled_spawns(encounter: BossEncounter) -> void:
	if encounter == null or encounter.pending_spawns.is_empty():
		return
	if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	var generation := encounter.spawn_generation
	var pending := encounter.pending_spawns.duplicate()
	for item in pending:
		if generation != encounter.spawn_generation:
			return
		if not encounter.pending_spawns.has(item):
			continue
		var condition: BossSpawnCondition = item.get("condition")
		if condition != null and not condition.is_met(_make_spawn_context(encounter)):
			continue
		var index := int(item.get("index", -1))
		var cards := encounter.boss_cards()
		if index < 0 or index >= cards.size():
			encounter.pending_spawns.erase(item)
			continue
		if _spawn_card(encounter, cards[index], index, _boss_multipliers()):
			encounter.pending_spawns.erase(item)
		else:
			return

func _make_spawn_context(encounter: BossEncounter) -> BossSpawnContext:
	var ctx := BossSpawnContext.new()
	ctx.encounter = encounter
	ctx.controller = self
	ctx.elapsed_seconds = encounter.spawn_elapsed_seconds
	ctx.total_count = encounter.total_bosses()
	ctx.spawned_count = encounter.spawned_count
	ctx.defeated_count = encounter.defeated_count
	ctx.active_boss_count = _active_boss_count(encounter)
	ctx.normal_enemy_count = _normal_enemy_count()
	ctx.normal_spawn_seen = _round_spawn_seen
	ctx.wave_clear = encounter.wave_clear_since >= 0.0
	ctx.wave_clear_since = encounter.wave_clear_since
	ctx.defeated_at_seconds = encounter.defeated_at_seconds.duplicate()
	ctx.phase_at_seconds = encounter.phase_at_seconds.duplicate(true)
	return ctx

func _refresh_wave_clear(encounter: BossEncounter) -> void:
	if encounter == null:
		return
	var cleared := _round_spawn_seen and _normal_enemy_count() == 0
	if cleared:
		if encounter.wave_clear_since < 0.0:
			encounter.wave_clear_since = encounter.spawn_elapsed_seconds
	else:
		encounter.wave_clear_since = -1.0

func _normal_enemy_count() -> int:
	var count := 0
	for enemy in PoolManager.get_active_enemies():
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("BOSS") or enemy.is_in_group("EnemyPart"):
			continue
		count += 1
	return count

func _active_boss_count(encounter: BossEncounter) -> int:
	var count := 0
	for boss in encounter.bosses:
		if boss != null and is_instance_valid(boss) and not boss._boss_dead:
			count += 1
	return count

func _cancel_scheduled_spawns(encounter: BossEncounter) -> void:
	if encounter == null:
		return
	encounter.spawn_generation += 1
	encounter.pending_spawns.clear()

func _check_first_spawn_timeout(encounter: BossEncounter) -> void:
	if encounter == null or encounter.first_boss_ready or encounter.first_spawn_timed_out:
		return
	var wait := encounter.entry.max_first_spawn_wait if encounter.entry != null else 0.0
	if wait <= 0.0 or encounter.spawn_elapsed_seconds < wait:
		return
	encounter.first_spawn_timed_out = true
	_resolve_first_spawn_timeout(encounter)

func _resolve_first_spawn_timeout(encounter: BossEncounter) -> void:
	if encounter == null:
		return
	_cancel_scheduled_spawns(encounter)
	await _resolve_missed(encounter, &"first_spawn_timeout", false)
	if encounter.state != BossEncounter.State.ENDED or not encounter.missed:
		return
	# ROUND_TIMER 让普通回合计时继续；fever/mandatory 的普通计时已暂停，需要主动结束。
	if encounter.entry.intruder_end_mode == BossEncounterEntry.IntruderEndMode.ROUND_TIMER \
			and not encounter.is_primary():
		return
	if not ExtensionHooks.intercept_named("round_end_emit_gate", []):
		GameEvents.emit_round_end()

func _find_boss_index(encounter: BossEncounter, boss: BossEnemy) -> int:
	if encounter == null or boss == null or boss.boss_card == null:
		return -1
	return encounter.boss_cards().find(boss.boss_card)

func _spawn_next(encounter: BossEncounter) -> void:
	var cards := encounter.boss_cards()
	if cards.is_empty():
		return
	var mode := encounter.spawn_mode()
	var multipliers := _boss_multipliers()
	if mode == BossRoundEntry.SpawnMode.SIMULTANEOUS:
		for i in cards.size():
			if i < encounter.spawned_count:
				continue
			_spawn_card(encounter, cards[i], i, multipliers)
	elif mode == BossRoundEntry.SpawnMode.SEQUENCE:
		if encounter.spawned_count >= cards.size():
			return
		var idx := encounter.spawned_count
		_spawn_card(encounter, cards[idx], idx, multipliers)
	else:
		if encounter.spawned_count > 0:
			return
		_spawn_card(encounter, cards[0], 0, multipliers)

func _spawn_card(encounter: BossEncounter, card: BossCard, index: int, multipliers: Dictionary) -> bool:
	if card == null:
		return false
	var cards := encounter.boss_cards()
	var pos := Vector2.ZERO
	if encounter.entry.encounter.positions.size() > index:
		pos = encounter.entry.encounter.positions[index]
	elif card.spawn_position != Vector2.ZERO:
		pos = card.spawn_position
	elif cards.size() > 1:
		var center := Vector2.ZERO
		var center_node := get_tree().get_first_node_in_group("CenterPosition")
		if center_node is Node2D:
			center = (center_node as Node2D).global_position
		pos = center + Vector2((float(index) - (float(cards.size()) - 1.0) * 0.5) * 180.0, 0)
	if spawner.spawn(card, pos, multipliers):
		encounter.spawned_count += 1
		return true
	return false

func _on_boss_spawned(boss: BossEnemy, card: BossCard) -> void:
	var encounter := _find_spawn_target(card)
	if encounter == null:
		return
	boss.boss_card = card
	boss.reward_scene_override = encounter.entry.encounter.reward_scene
	encounter.bosses.append(boss)
	boss.boss_defeated.connect(_on_boss_defeated.bind(boss, encounter))
	boss.boss_phase_changed.connect(_on_boss_phase_changed.bind(boss))
	_ensure_hp_group(encounter)
	if encounter.hp_group != null:
		encounter.hp_group.add_boss(boss)
	encounter.state = BossEncounter.State.ENTERING
	boss_joined.emit(boss, encounter.entry)
	GameEvents.emit_boss_joined(boss, encounter.entry)
	ExtensionHooks.notify_named("on_boss_joined", [boss, encounter.entry])
	var allow_camera := encounter.is_primary()
	if encounter.spawn_mode() == BossRoundEntry.SpawnMode.SIMULTANEOUS and encounter.bosses.size() > 1:
		allow_camera = false
	var policy: StringName = encounter.entry.cinematic_policy
	if card != null and not card.cinematic:
		policy = &"none"
	await BossCinematic.play_enter(self, boss, policy, allow_camera)
	if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	encounter.state = BossEncounter.State.FIGHTING
	encounter.first_boss_ready = true
	if encounter == _timed_intruder:
		_start_timed_boss_timer(encounter)
	_evaluate_scheduled_spawns(encounter)

func _on_boss_defeated(boss: BossEnemy, encounter: BossEncounter) -> void:
	if encounter == null or encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	encounter.state = BossEncounter.State.SETTLING
	_settling = true
	encounter.defeated_count += 1
	var defeated_index := _find_boss_index(encounter, boss)
	if defeated_index >= 0:
		encounter.defeated_at_seconds[defeated_index] = encounter.spawn_elapsed_seconds
	var allow_camera := encounter.is_primary()
	if encounter.spawn_mode() == BossRoundEntry.SpawnMode.SIMULTANEOUS and encounter.bosses.size() > 1 and encounter.bosses[0] != boss:
		allow_camera = false
	var policy: StringName = encounter.entry.cinematic_policy
	if boss != null and boss.boss_card != null and not boss.boss_card.cinematic:
		policy = &"none"
	await BossCinematic.play_death(self, boss, policy, allow_camera)
	_remove_boss_bar(encounter, boss)
	if not is_instance_valid(boss):
		_settling = false
		return
	boss.drop_rewards()
	var profile := encounter.profile()
	if profile != null and profile.end_delay > 0.0:
		await get_tree().create_timer(profile.end_delay, true, false, true).timeout
	boss.despawn_after_death()
	_evaluate_scheduled_spawns(encounter)
	if encounter.is_complete():
		_cancel_remaining(encounter)
		_settling = false
		_finish_encounter(encounter, &"hp_zero")
		return
	if encounter.has_next_sequence():
		encounter.state = BossEncounter.State.FIGHTING
		_settling = false
		_spawn_next(encounter)
		return
	# ALL_DEFEATED 尚未满足：保留剩余 Boss，等待后续死亡。
	encounter.state = BossEncounter.State.FIGHTING
	_settling = false

func _on_boss_phase_changed(phase: int, boss: BossEnemy) -> void:
	ExtensionHooks.notify_named("on_boss_phase_changed", [boss, phase])
	var encounter := _find_encounter_for_boss(boss)
	if encounter == null:
		return
	var boss_index := _find_boss_index(encounter, boss)
	if boss_index >= 0:
		var phases: Dictionary = encounter.phase_at_seconds.get(boss_index, {})
		if not phases.has(phase):
			phases[phase] = encounter.spawn_elapsed_seconds
		encounter.phase_at_seconds[boss_index] = phases
	_evaluate_scheduled_spawns(encounter)
	encounter.phase_queue.append({"boss": boss, "index": phase - 1})
	if encounter.phase_busy:
		return
	encounter.phase_busy = true
	call_deferred("_run_phase_queue", encounter)

func _run_phase_queue(encounter: BossEncounter) -> void:
	while not encounter.phase_queue.is_empty():
		var item: Dictionary = encounter.phase_queue.pop_front()
		var boss: BossEnemy = item.get("boss")
		var phase_index := int(item.get("index", -1))
		if boss == null or not is_instance_valid(boss) or boss._boss_dead:
			continue
		var phase_data := boss.get_phase_data(phase_index)
		if phase_data == null:
			continue
		var policy: StringName = &"full"
		if boss.boss_card != null and not boss.boss_card.cinematic:
			policy = &"none"
		await BossCinematic.play_phase(self, boss, phase_index, phase_data, policy)
	encounter.phase_busy = false

func _find_encounter_for_boss(boss: BossEnemy) -> BossEncounter:
	for encounter in encounters:
		if encounter.bosses.has(boss):
			return encounter
	return null

func _finish_encounter(encounter: BossEncounter, reason: StringName, emit_round_end: bool = true) -> void:
	if encounter == null or encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
		return
	_cancel_scheduled_spawns(encounter)
	var was_timed := encounter == _timed_intruder
	var is_primary := encounter.is_primary()
	encounter.state = BossEncounter.State.ENDED
	var profile := encounter.profile()
	var result := _build_result(encounter, reason, profile)
	encounter.result = result
	if ExtensionHooks.intercept_named("boss_encounter_settle_gate", [encounter.entry, result]):
		_dispose_hp_group(encounter)
		_clear_timed_intruder(encounter)
		primary = null if primary == encounter else primary
		_refresh_active()
		return
	boss_encounter_ended.emit(encounter.entry, result)
	GameEvents.emit_boss_encounter_ended(encounter.entry, result)
	ExtensionHooks.notify_named("on_boss_encounter_ended", [encounter.entry, result])
	if is_primary or was_timed:
		var was_boss_round := boss_round_active
		boss_round_active = false
		if was_timed:
			var rt := _round_timer()
			if rt != null and rt.has_method("stop_boss_encounter_timer"):
				rt.stop_boss_encounter_timer()
		elif was_boss_round:
			GameEvents.emit_boss_round_end()
		var next := str(result.get("next", "end_round"))
		boss_round_settled.emit(result)
		GameEvents.emit_boss_round_settled(result)
		ExtensionHooks.notify_named("on_boss_round_settled", [result])
		if next == "victory":
			GameEvents.emit_game_over(false)
		elif next == "game_over":
			GameEvents.emit_game_over(true)
		elif next == "continue_round":
			_resume_spawns_if_needed(encounter)
		elif emit_round_end:
			if not ExtensionHooks.intercept_named("round_end_emit_gate", []):
				GameEvents.emit_round_end()
	else:
		if emit_round_end:
			_resume_spawns_if_needed(encounter)
	_clear_timed_intruder(encounter)
	_dispose_hp_group(encounter)
	primary = null if primary == encounter else primary
	_refresh_active()

func _clear_timed_intruder(encounter: BossEncounter) -> void:
	if _timed_intruder == encounter:
		_timed_intruder = null
	if _fever_intruder == encounter:
		_fever_intruder = null
	_fever_generation += 1

func _build_result(encounter: BossEncounter, reason: StringName, profile: BossRoundProfile) -> Dictionary:
	var ids: Array[String] = []
	for card in encounter.boss_cards():
		if card != null:
			ids.append(card.id)
	var next := "continue_round"
	var was_timed := encounter == _timed_intruder
	if encounter.is_primary():
		next = "upgrade"
		if profile != null:
			if profile.final_boss:
				next = "victory"
			elif not profile.end_on_death and encounter.is_primary():
				next = "continue_round"
			elif String(profile.victory_mode) != "":
				next = String(profile.victory_mode)
		var mode := _effective_timer_mode(encounter.entry)
		if encounter.entry.end_round_on_defeat and next == "continue_round":
			next = "upgrade"
		if mode == BossEncounterEntry.TimerMode.REPLACE_NORMAL and next == "continue_round":
			next = "upgrade"
	elif was_timed:
		next = "end_round"
		if profile != null and profile.final_boss:
			next = "victory"
	elif encounter.entry.end_round_on_defeat:
		next = "end_round"
	var missed := reason in [&"missed", &"round_timer_end", &"fever_timeout", &"first_spawn_timeout"]
	if missed:
		next = "end_round"
	return {
		"entry": encounter.entry,
		"boss_ids": ids,
		"total_count": encounter.total_bosses(),
		"spawned_count": encounter.spawned_count,
		"defeated_count": encounter.defeated_count,
		"result": "missed" if missed else ("defeated" if reason == &"hp_zero" else String(reason)),
		"reason": String(reason),
		"role": "primary" if encounter.is_primary() else ("timed" if was_timed else "add"),
		"next": next,
		"is_final": profile != null and profile.final_boss,
		"missed": missed,
	}

func _ensure_hp_group(encounter: BossEncounter) -> void:
	if encounter.hp_group != null and is_instance_valid(encounter.hp_group):
		return
	var group_scene := load("res://ui/boss_hp_group.tscn") as PackedScene
	if group_scene == null:
		return
	var group := group_scene.instantiate() as BossHPGroup
	if group == null:
		return
	group.max_visible = maxi(1, encounter.entry.encounter.max_visible_hp_bars)
	var ui_root := get_tree().get_first_node_in_group("GameUI")
	if ui_root == null:
		ui_root = get_tree().current_scene
	if ui_root == null:
		return
	ui_root.add_child(group)
	encounter.hp_group = group

func _remove_boss_bar(encounter: BossEncounter, boss: BossEnemy) -> void:
	if encounter == null or encounter.hp_group == null:
		return
	encounter.hp_group.remove_boss(boss)

func _dispose_hp_group(encounter: BossEncounter) -> void:
	if encounter == null or encounter.hp_group == null:
		return
	encounter.hp_group.clear_all()
	encounter.hp_group.queue_free()
	encounter.hp_group = null

func _cancel_remaining(encounter: BossEncounter) -> void:
	_cancel_scheduled_spawns(encounter)
	for boss in encounter.bosses:
		if boss != null and is_instance_valid(boss) and not boss._boss_dead:
			boss.despawn_immediate()
	if encounter.hp_group != null:
		encounter.hp_group.clear_all()

func _find_spawn_target(card: BossCard) -> BossEncounter:
	for encounter in encounters:
		if encounter.state in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			continue
		if encounter.boss_cards().has(card):
			return encounter
	return null

func _refresh_active() -> void:
	encounter_active = false
	for encounter in encounters:
		if encounter.state not in [BossEncounter.State.ENDED, BossEncounter.State.CANCELLED]:
			encounter_active = true
			break
	var rt := _round_timer()
	if rt != null and rt.has_method("set_boss_encounter_active"):
		rt.set_boss_encounter_active(encounter_active)

func _on_round_finished() -> void:
	cancel_for_round_end()
	_reset_mid_round_state()

func _on_game_over(_player_dead: bool) -> void:
	cancel_for_round_end()
	_reset_mid_round_state()

func _get_schedules() -> Array[BossSchedule]:
	var out: Array[BossSchedule] = []
	if ModManager != null:
		for s in ModManager.get_mod_boss_schedules():
			if s is BossSchedule:
				out.append(s)
	out.sort_custom(func(a, b): return a.priority > b.priority)
	return out

func _all_entries() -> Array[BossEncounterEntry]:
	var out: Array[BossEncounterEntry] = []
	for schedule in _get_schedules():
		if schedule == null or not schedule.enabled:
			continue
		out.append_array(schedule.entries)
		out.append_array(schedule.endless_entries)
	return out

func _pick_entry(pool: Array[BossEncounterEntry], round_index: int, group: String, is_endless: bool, schedule: BossSchedule = null) -> BossEncounterEntry:
	var candidates: Array[BossEncounterEntry] = []
	for entry in pool:
		if entry == null or not entry.enabled or entry.encounter == null or entry.encounter.bosses.is_empty():
			continue
		if entry.trigger != BossEncounterEntry.Trigger.ROUND_START:
			continue
		if round_index < entry.round_min or round_index > entry.round_max:
			continue
		if entry.group != "" and entry.group != group:
			continue
		candidates.append(entry)
	if candidates.is_empty():
		return null

	var use_rotation := is_endless and schedule != null and schedule.endless_mode == BossSchedule.EndlessMode.ROTATION
	if use_rotation:
		var key := schedule.id if schedule.id != "" else str(schedule.get_instance_id())
		var idx := int(_rotation.get(key, 0))
		var entry := candidates[idx % candidates.size()]
		_rotation[key] = idx + 1
		_last_boss_id = entry.encounter.bosses[0].id
		return entry

	if _last_boss_id != "":
		var filtered: Array[BossEncounterEntry] = []
		for entry in candidates:
			if entry.encounter.bosses[0].id != _last_boss_id:
				filtered.append(entry)
		if not filtered.is_empty():
			candidates = filtered
	var total := 0.0
	for entry in candidates:
		total += maxf(0.01, entry.weight)
	var pick := randf() * total
	for entry in candidates:
		pick -= maxf(0.01, entry.weight)
		if pick <= 0.0:
			_last_boss_id = entry.encounter.bosses[0].id
			return entry
	_last_boss_id = candidates[candidates.size() - 1].encounter.bosses[0].id
	return candidates[candidates.size() - 1]

func _make_plan(entry: BossEncounterEntry, round_index: int, is_endless: bool, endless_round: int = 0) -> Dictionary:
	var profile := entry.encounter.profile_override
	if profile == null and not entry.encounter.bosses.is_empty():
		profile = entry.encounter.bosses[0].round_profile
	return {
		"entry": entry,
		"bosses": entry.encounter.bosses,
		"profile": profile,
		"round": round_index,
		"is_endless": is_endless,
		"endless_round": endless_round,
		"trigger": entry.trigger,
	}

func _effective_timer_mode(entry: BossEncounterEntry) -> int:
	if entry.trigger == BossEncounterEntry.Trigger.ROUND_START and entry.timer_mode == BossEncounterEntry.TimerMode.NORMAL_CONTINUES:
		return BossEncounterEntry.TimerMode.REPLACE_NORMAL
	return entry.timer_mode

func _boss_multipliers() -> Dictionary:
	var out := {"hp": 1.0, "damage": 1.0}
	var mgr := get_tree().get_first_node_in_group("EnemyManager")
	if mgr != null and mgr.has_method("get_spawn_multipliers"):
		out = mgr.get_spawn_multipliers(true)
	var profile := get_profile()
	if profile != null:
		var max_round := 20.0
		var rm := get_parent()
		if rm != null and rm.get("max_round") != null:
			max_round = maxf(1.0, float(rm.max_round))
		var x := float(PlayerData.now_round) / max_round
		if profile.boss_hp_curve != null:
			out["hp"] = profile.boss_hp_curve.sample(x)
		if profile.boss_damage_curve != null:
			out["damage"] = profile.boss_damage_curve.sample(x)
	return out

func _round_timer() -> Node:
	return get_tree().get_first_node_in_group("RoundTime")

func _current_round() -> int:
	var round_manager := get_parent()
	if round_manager != null and round_manager.get("now_round_num") != null:
		return int(round_manager.now_round_num)
	return 1

func _current_endless_round() -> int:
	var round_manager := get_parent()
	if round_manager == null or round_manager.get("max_round") == null:
		return 1
	return maxi(1, int(PlayerData.now_round) - int(round_manager.max_round))

func _reset_rotation() -> void:
	_rotation.clear()
	_last_boss_id = ""

func _clear_minions() -> void:
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("EnemyPart") or enemy.is_in_group("BOSS"):
			continue
		if enemy.has_method("idle_state"):
			enemy.idle_state()
