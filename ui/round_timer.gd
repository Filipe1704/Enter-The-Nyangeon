extends CanvasLayer

# 横幅复用：FEVER 与 Boss 乱入共用同一套 FeverTime 节点与动画，只切换 Label 文本。
# 任何新增触发点都必须经 _play_banner(text) 显式写回自己的文本，FEVER 入口负责恢复默认文本。
const FEVER_BANNER_TEXT := ">> FEVER TIME >>"
const BOSS_RAID_BANNER_TEXT := "!! BOSS RAID !!"
const BOSS_RAID_EVENT := "boss_intruder_start"

@export var enemy_buff: Buff

@onready var now_round = $Control/NowRound
@onready var timer = $Control/Timer
@onready var minute_show = $Control/HBoxContainer/MinuteShow
@onready var second_show = $Control/HBoxContainer/SecondShow
@onready var millisecond_show = $Control/HBoxContainer/MillisecondShow
@onready var animation_player = $AnimationPlayer
@onready var time_bar = $%TimeBar
@onready var round_timer = $RoundTimer
@onready var global_timer = $GlobalTimer

@onready var fever_anim_1: AnimationPlayer = $FeverTime/AnimationPlayer
@onready var fever_anim_2: AnimationPlayer = $FeverTime/AnimationPlayer2
@onready var banner_label: Label = $FeverTime/Label

var is_boss_round: bool = false
var rage_mode: bool = false
var boss_group: Array
var value: Array = [999, 0.05, 99999]
var rage_time: int = 0

var time_mult: float = 1
var is_game_mode_1: bool = false
# boss 回合「等待拾取青辉石结束本回合」标志：仅 boss_round_start 置真，本回合 round_end 清假。
# 防止非 boss 回合收到杂散 pyroxenes_pick_up（如联机视觉副本）而误触发 end_boss_round 跳关。
var boss_round_pending_end: bool = false
# 有 Boss 在场（含中途 ADD）；与 is_boss_round（Boss 接管回合计时）分开。
var boss_encounter_active: bool = false
var _normal_round_paused: bool = false
var _saved_round_time: int = 0
var _saved_round_wait: float = 0.0
var _saved_round_time_left: float = 0.0
var _saved_global_time_left: float = 0.0
var _force_rage_timeout: bool = false
# 乱入 Boss 在普通计时归零后的 15 秒 FEVER 延长窗口。
var intruder_fever_active: bool = false
# FEVER 结算兜底：resolve/演出 await 永久不返回时，超过该时长也强制结束回合（测试可调）。
var fever_resolve_timeout: float = 8.0
var _fever_resolve_token: int = 0
# 联机客机首轮本地倒计时（对齐联机版）：host 广播 round_end 驱动，客机只本地计时显示
var client_round_countdown_started: bool = false

@warning_ignore("unused_signal")
signal round_start
@warning_ignore("unused_signal")
signal round_end
signal round_time_warning
signal round_time_out
# Boss 独立计时归零（中途乱入 / Boss 回合都会发；控制器按自身状态决定是否处理）。
signal boss_timeout(profile: BossRoundProfile)

var now_round_num = 0:
	set(v):
		now_round_num = v
		now_round.text = "ROUND %s" % [str(v) ]
		GameEvents.emit_round_num_changed(now_round_num)
		PlayerData.now_round = now_round_num

var round_time = 0:
	set(v):
		round_time = v
		if floor(float(v) / 60.0 ) < 10:
			minute_show.text = str( "0",str(int(floor(float(v) / 60.0 ))),":")
		else:
			minute_show.text = str( str(int(floor(float(v) / 60.0 ))),":")
		if v - (floor(float(v) / 60.0 ) * 60 ) < 10:
			second_show.text = str("0", str(int(v - (floor(float(v) / 60.0 ) * 60 ))),":")
		else:
			second_show.text = str( str(int(v - (floor(float(v) / 60.0 ) * 60 ))),":")
		if v < 10:
			emit_signal("round_time_warning")

func _ready():
	GameEvents.round_start.connect(init_round)
	GameEvents.boss_round_start.connect(boss_round)
	GameEvents.boss_round_end.connect(rage_mode_end)
	GameEvents.pyroxenes_pick_up.connect(end_boss_round)
	GameEvents.game_over.connect(game_over_stop)
	GameEvents.round_end.connect(_clear_boss_round_pending_end)
	GameEvents.round_end.connect(_clear_encounter_state)
	GameEvents.ui_visible.connect(game_ui_visible)
	GameEvents.fever_time_start.connect(play_fever_anim)
	GameEvents.boss_event.connect(_on_boss_event)
	GameEvents.first_round_add.connect(_on_first_round_add)

# 联机会话判定（未注入 mod 时始终 false → 单机原行为）
func _is_lan_session() -> bool:
	return ExtensionHooks.intercept_named("is_lan_session", [])

# 是否禁止本端自发 emit_round_end（客机由 host 广播 round_end）
func _round_end_emit_blocked() -> bool:
	return ExtensionHooks.intercept_named("round_end_emit_gate", [])

# 是否禁止本端本地触发 FEVER/rage（客机由 host 广播 fever_time_start / rage buff）
func _fever_time_handled() -> bool:
	return ExtensionHooks.intercept_named("fever_time_gate", [])

func game_ui_visible(now_visible: bool):
	visible = now_visible

func _physics_process(_delta):
	
	time_bar.value = round_timer.time_left / round_timer.wait_time
	if int(timer.time_left * 100) < 10:
		millisecond_show.text = str("0",int(timer.time_left * 100))
	else:
		millisecond_show.text = str(int(timer.time_left * 100))

func boss_round():
	boss_round_with_profile(_get_boss_profile())

func boss_round_with_profile(profile_override: BossRoundProfile = null):
	var profile := profile_override
	if profile == null:
		profile = _get_boss_profile()
	var limit := 90.0
	if profile != null and profile.time_limit > 0.0:
		limit = profile.time_limit
	is_boss_round = true
	boss_encounter_active = true
	boss_round_pending_end = true
	_normal_round_paused = false
	round_time = maxi(1, int(ceil(limit)) - 1)
	round_timer.wait_time = maxf(1.0, limit)
	timer.start()
	round_timer.start()

func init_round():
	now_round_num += 1
	_normal_round_paused = false
	_start_round_countdown()

# 启动一次本地倒计时（正常按钮/首轮客机共用；抽自原 init_round 计时部分）
func _start_round_countdown():
	round_time = 60 * time_mult - 1
	round_timer.wait_time = 60
	timer.start()
	round_timer.start()
	global_timer.start()
	$Control/NowRound.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/Label.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/MinuteShow.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/SecondShow.set("theme_override_colors/font_color", Color(1, 1, 1))
	$Control/HBoxContainer/MillisecondShow.set("theme_override_colors/font_color", Color(1, 1, 1))

# 联机客机：首轮本体不调 round_manager.first_round_start()，故不 emit round_start，
# 需在 first_round_add 时本地起一轮倒计时（对齐联机版）；round_end 由 host 广播驱动。
func _on_first_round_add() -> void:
	if not _is_lan_session() or multiplayer.is_server():
		return
	if client_round_countdown_started or now_round_num > 0:
		return
	_start_client_round_countdown.call_deferred()

func _start_client_round_countdown() -> void:
	if client_round_countdown_started or now_round_num > 0:
		return
	client_round_countdown_started = true
	now_round_num = maxi(now_round_num + 1, PlayerData.now_round)
	_start_round_countdown()

# ---------------- Boss 遭遇 / 普通回合计时协调 ----------------
# 首版只实际使用 replace_with_boss_timer；pause/resume/extend 为 Phase 2.5 预留。

func set_boss_encounter_active(active: bool) -> void:
	boss_encounter_active = active

func pause_normal_round() -> void:
	if _normal_round_paused or is_boss_round:
		return
	_normal_round_paused = true
	_saved_round_time = round_time
	_saved_round_wait = round_timer.wait_time
	_saved_round_time_left = round_timer.time_left
	_saved_global_time_left = global_timer.time_left
	timer.stop()
	round_timer.stop()
	global_timer.stop()

func resume_normal_round() -> void:
	if not _normal_round_paused:
		return
	_normal_round_paused = false
	is_boss_round = false
	boss_encounter_active = false
	rage_mode = false
	rage_time = 0
	boss_round_pending_end = false
	intruder_fever_active = false
	_fever_resolve_token += 1
	_force_rage_timeout = false
	round_time = _saved_round_time
	round_timer.wait_time = _saved_round_wait
	round_timer.start(maxf(0.05, _saved_round_time_left))
	global_timer.start(maxf(0.05, _saved_global_time_left))

# 中途乱入：启动 Boss 独立计时，不影响普通回合保存状态。
func start_boss_encounter_timer(profile: BossRoundProfile = null, force_rage: bool = false) -> void:
	var p := profile
	if p == null:
		p = _get_boss_profile()
	var limit := 90.0
	if p != null and p.time_limit > 0.0:
		limit = p.time_limit
	is_boss_round = true
	boss_encounter_active = true
	boss_round_pending_end = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = force_rage
	round_time = maxi(1, int(ceil(limit)) - 1)
	round_timer.wait_time = maxf(1.0, limit)
	timer.start()
	round_timer.start()

func stop_boss_encounter_timer() -> void:
	is_boss_round = false
	boss_encounter_active = false
	boss_round_pending_end = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = false
	timer.stop()
	round_timer.stop()

# 普通计时归零但乱入 Boss 仍存活：延长 15 秒 FEVER，而不是直接结束回合。
func start_intruder_fever(duration: float = 15.0) -> void:
	if intruder_fever_active:
		return
	intruder_fever_active = true
	is_boss_round = false
	boss_encounter_active = true
	boss_round_pending_end = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = false
	boss_group = get_tree().get_nodes_in_group("BOSS")
	round_time = maxi(1, int(ceil(duration)))
	round_timer.wait_time = maxf(1.0, duration)
	round_timer.start()
	timer.start()
	set_font_red()
	if not _fever_time_handled():
		GameEvents.emit_fever_time_start()

func _finish_intruder_fever() -> void:
	if not intruder_fever_active:
		return
	intruder_fever_active = false
	is_boss_round = false
	boss_encounter_active = false
	rage_mode = false
	rage_time = 0
	timer.stop()
	round_timer.stop()
	# 双路收敛：正常结算与 watchdog 谁先到谁发 round_end，token 保证只发一次。
	_fever_resolve_token += 1
	var token := _fever_resolve_token
	_resolve_intruder_then_end(token)
	_fever_resolve_watchdog(token)

func _resolve_intruder_then_end(token: int) -> void:
	if not is_inside_tree():
		return
	var manager := get_tree().get_first_node_in_group("EnemyManager")
	if manager != null and manager.has_method("resolve_boss_intruder_timeout"):
		await manager.resolve_boss_intruder_timeout()
	_complete_intruder_fever(token)

# 兜底：resolve 内部任何 await 永久不返回时也必须结束回合，
# 否则普通刷怪计时器会一直跑、回合永不转场。
func _fever_resolve_watchdog(token: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(maxf(0.1, fever_resolve_timeout), true, false, true).timeout
	if token != _fever_resolve_token:
		return
	push_warning("round_timer: 乱入撤退结算超时，强制结束回合")
	_complete_intruder_fever(token)

func _complete_intruder_fever(token: int) -> void:
	if token != _fever_resolve_token:
		return
	_fever_resolve_token += 1
	if not _round_end_emit_blocked():
		GameEvents.emit_round_end()

func replace_with_boss_timer(profile: BossRoundProfile = null) -> void:
	pause_normal_round()
	boss_round_with_profile(profile)

func extend_normal_round(seconds: float) -> void:
	if is_boss_round or seconds <= 0.0:
		return
	round_time += int(ceil(seconds))
	round_timer.wait_time += seconds
	if round_timer.time_left > 0.0:
		round_timer.start(round_timer.time_left + seconds)

func get_normal_time_left() -> float:
	if is_boss_round:
		return 0.0
	if _normal_round_paused:
		return _saved_round_time_left
	return round_timer.time_left

func get_boss_time_left() -> float:
	if not is_boss_round:
		return 0.0
	return round_timer.time_left

func _get_boss_profile() -> BossRoundProfile:
	var controller := _boss_controller()
	if controller != null and controller.has_method("get_profile"):
		return controller.get_profile()
	return null

func _boss_controller() -> Node:
	return get_tree().get_first_node_in_group("BossRoundController")

func game_over_stop(_player_dead: bool):
	SoundManager.game_end = true
	boss_round_pending_end = false
	boss_encounter_active = false
	intruder_fever_active = false
	_fever_resolve_token += 1
	is_boss_round = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = false
	timer.stop()
	global_timer.stop()
	round_timer.stop()

func _on_timer_timeout():
	if intruder_fever_active:
		var intruder_manager := get_tree().get_first_node_in_group("EnemyManager")
		if intruder_manager == null or not intruder_manager.has_method("has_active_boss_intruder") \
				or not intruder_manager.has_active_boss_intruder():
			_finish_intruder_fever()
			return
		round_time -= 1
		if round_time <= 0:
			_finish_intruder_fever()
			return
		rage_time += 1
		if rage_time > 5:
			rage_time = 0
			if not _fever_time_handled():
				boss_group = get_tree().get_nodes_in_group("BOSS")
				add_rage_buff()
		return
	if rage_mode == false:
		round_time -=1
		if round_time <= 0:
			if is_boss_round == false:
				var intruder_manager := get_tree().get_first_node_in_group("EnemyManager")
				if intruder_manager != null and intruder_manager.has_method("has_active_boss_intruder") \
						and intruder_manager.has_active_boss_intruder():
					start_intruder_fever(15.0)
					return
				var controller := _boss_controller()
				if controller != null and controller.has_method("on_normal_round_timeout") \
						and controller.has_method("is_encounter_active") and controller.is_encounter_active():
					var policy: int = controller.on_normal_round_timeout()
					if policy == BossEncounterEntry.OnNormalTimeout.HOLD_UNTIL_DEAD:
						if controller.has_method("hold_normal_round_for_boss"):
							controller.hold_normal_round_for_boss()
						return
					if policy == BossEncounterEntry.OnNormalTimeout.FAIL:
						timer.stop()
						round_time_out.emit()
						GameEvents.emit_game_over(true)
						return
					if policy == BossEncounterEntry.OnNormalTimeout.BOSS_ESCAPES:
						timer.stop()
						round_time_out.emit()
						if controller.has_method("resolve_normal_timeout_missed"):
							await controller.resolve_normal_timeout_missed()
						if not _round_end_emit_blocked():
							GameEvents.emit_round_end()
						return
				# 倒计时归 0 起到 round_end 之间的窗口也要锁暂停（否则转场前可弹暂停菜单）
				GameEvents.emit_pause_lock(true)
				await get_tree().create_timer(0.9).timeout
				timer.stop()
				round_time_out.emit()
				if not _round_end_emit_blocked():
					GameEvents.emit_round_end()
			else:
				if PlayerData.game_mode.has("hujiu"):
					timer.stop()
					round_time_out.emit()
					if not _round_end_emit_blocked():
						GameEvents.emit_round_end()
				else:
					var profile := _get_boss_profile()
					if profile != null:
						boss_timeout.emit(profile)
					if _force_rage_timeout:
						round_time_out.emit()
						_enter_rage_mode()
					elif profile != null and profile.timeout_mode == BossRoundProfile.TimeoutMode.END:
						timer.stop()
						round_time_out.emit()
						if not _round_end_emit_blocked():
							GameEvents.emit_round_end()
					elif profile != null and profile.timeout_mode == BossRoundProfile.TimeoutMode.FAIL:
						timer.stop()
						round_time_out.emit()
						GameEvents.emit_game_over(true)
					elif profile != null and profile.timeout_mode == BossRoundProfile.TimeoutMode.CUSTOM:
						round_time_out.emit()
						if not ExtensionHooks.intercept_named("boss_timeout_gate", [_first_active_boss(), profile]):
							_enter_rage_mode()
					else:
						round_time_out.emit()
						_enter_rage_mode()
	else:
		round_time += 1
		rage_time += 1
		var interval := 5
		var profile := _get_boss_profile()
		if profile != null and profile.rage_interval_ticks > 0:
			interval = profile.rage_interval_ticks
		if rage_time > interval:
			rage_time = 0
			if not _fever_time_handled():
				add_rage_buff()

func _enter_rage_mode() -> void:
	rage_mode = true
	var controller := _boss_controller()
	if controller != null and controller.has_method("get_active_bosses"):
		boss_group = controller.get_active_bosses()
	else:
		boss_group = get_tree().get_nodes_in_group("BOSS")
	if not _fever_time_handled():
		GameEvents.emit_fever_time_start()

func _first_active_boss() -> Node:
	var controller := _boss_controller()
	if controller != null and controller.has_method("get_active_bosses"):
		var bosses: Array = controller.get_active_bosses()
		if not bosses.is_empty():
			return bosses[0]
	return null

func add_rage_buff():
	var buff := enemy_buff
	var profile := _get_boss_profile()
	if profile != null and profile.fever_buff != null:
		buff = profile.fever_buff
	if buff == null:
		return
	var controller := _boss_controller()
	if controller != null and controller.has_method("get_active_bosses"):
		boss_group = controller.get_active_bosses()
	if boss_group.size() > 0:
		for i in boss_group.size():
			var boss = boss_group[i]
			if boss == null or not is_instance_valid(boss):
				continue
			var manager = boss.get("enemy_buff_manager")
			if manager != null and manager.has_method("apply_buff"):
				manager.apply_buff(buff, value)

func rage_mode_end():
	is_boss_round = false
	boss_encounter_active = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = false
	timer.stop()

# 本回合 round_end 已发生：清零 boss 结束标志，避免泄漏到后续（非 boss）回合。
func _clear_boss_round_pending_end():
	boss_round_pending_end = false

func _clear_encounter_state():
	boss_encounter_active = false
	intruder_fever_active = false
	_fever_resolve_token += 1
	is_boss_round = false
	rage_mode = false
	rage_time = 0
	_force_rage_timeout = false
	_normal_round_paused = false

func end_boss_round():
	# 仅 boss 回合（boss_round_start 后、本回合 round_end 前）的拾取有效；
	# 非 boss 回合的杂散 pyroxenes_pick_up（如联机视觉副本）一律忽略，防止跳关。
	if not boss_round_pending_end:
		return
	var profile := _get_boss_profile()
	if profile != null and not profile.end_on_pickup:
		return
	boss_round_pending_end = false
	await get_tree().create_timer(3.5).timeout
	if _round_end_emit_blocked():
		return
	var controller := _boss_controller()
	if controller != null and controller.has_method("request_end") and controller.has_method("is_encounter_active") and controller.is_encounter_active():
		controller.request_end(&"pickup")
		return
	GameEvents.emit_round_end()

func set_font_red():
	$Control/NowRound.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/Label.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/MinuteShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/SecondShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))
	$Control/HBoxContainer/MillisecondShow.set("theme_override_colors/font_color", Color(0.923, 0, 0.261))

func play_fever_anim():
	_play_banner(FEVER_BANNER_TEXT)

# Boss 乱入提示：复用 FEVER 横幅，只把文本换成 BOSS RAID。
func play_boss_intruder_anim() -> void:
	_play_banner(BOSS_RAID_BANNER_TEXT)

func _on_boss_event(event_name: String, _data: Dictionary) -> void:
	if event_name == BOSS_RAID_EVENT:
		play_boss_intruder_anim()

func _play_banner(text: String) -> void:
	banner_label.text = text
	fever_anim_1.play("fever_time")
	fever_anim_2.play("fever_anim")
	SoundManager.play_sfx("WarringSounds")

func _on_round_time_warning():
	if rage_mode == false:
		animation_player.play("new_animation")
	else:
		set_font_red()


func _on_round_time_out():
	set_font_red()

func cleanup_orphaned_nodes(node: Node):
	var child_count = node.get_child_count()
	for i in range(child_count):
		var child = node.get_child(i)
		cleanup_orphaned_nodes(child)
	if node.get_parent() == null:
		print("Found orphaned node: ", node.name)
		node.queue_free()

func _on_global_timer_timeout():
	GameEvents.emit_global_time_count()
