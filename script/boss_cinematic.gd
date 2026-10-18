class_name BossCinematic

# Boss 演出 helper：统一镜头/UI/暂停锁/超时释放。
# 具体动画仍由 BossEnemy 播放，这里只负责“演出外壳”。
const DEFAULT_TIMEOUT: float = 8.0

static func play_enter(host: Node, boss: BossEnemy, policy: StringName = &"full", allow_camera: bool = true) -> void:
	if host == null or boss == null or not is_instance_valid(boss):
		return
	var use_camera := allow_camera and policy != &"none" and _can_use_camera(boss)
	if ExtensionHooks.intercept_named("boss_enter_cinematic_gate", [boss, &"enter"]):
		use_camera = false
	var marker: Marker2D = null
	var temp_marker: Marker2D = null
	if use_camera:
		marker = boss.get_camera_marker()
		if marker == null:
			temp_marker = Marker2D.new()
			host.add_child(temp_marker)
			temp_marker.global_position = boss.global_position
			marker = temp_marker
		GameEvents.emit_camera_move(marker, true)
		GameEvents.emit_ui_visible(false)
		GameEvents.emit_pause_lock(true)
		host.get_tree().paused = true
	boss.set_combat_enabled(false)
	boss.play_enter_anim()
	await _wait_signal(boss.boss_enter_finished, DEFAULT_TIMEOUT)
	if use_camera:
		release(host)
	if temp_marker != null and is_instance_valid(temp_marker):
		temp_marker.queue_free()
	if is_instance_valid(boss) and not boss._boss_dead:
		boss.set_combat_enabled(true)

static func play_death(host: Node, boss: BossEnemy, policy: StringName = &"full", allow_camera: bool = true) -> void:
	if host == null or boss == null or not is_instance_valid(boss):
		return
	var use_camera := allow_camera and policy != &"none" and _can_use_camera(boss)
	if ExtensionHooks.intercept_named("boss_death_cinematic_gate", [boss, &"death"]):
		use_camera = false
	var marker: Marker2D = null
	var temp_marker: Marker2D = null
	if use_camera:
		marker = boss.get_camera_marker()
		if marker == null:
			temp_marker = Marker2D.new()
			host.add_child(temp_marker)
			temp_marker.global_position = boss.global_position
			marker = temp_marker
		GameEvents.emit_camera_move(marker, true)
		GameEvents.emit_ui_visible(false)
		GameEvents.emit_pause_lock(true)
		host.get_tree().paused = true
	boss.set_combat_enabled(false)
	boss.play_death_anim()
	await _wait_signal(boss.boss_death_finished, DEFAULT_TIMEOUT)
	if use_camera:
		release(host)
	if temp_marker != null and is_instance_valid(temp_marker):
		temp_marker.queue_free()

static func play_phase(host: Node, boss: BossEnemy, phase_index: int, phase_data: BossPhase, policy: StringName = &"full") -> void:
	if host == null or boss == null or not is_instance_valid(boss) or phase_data == null:
		return
	var use_camera := policy != &"none" and _can_use_camera(boss)
	var marker: Marker2D = null
	var temp_marker: Marker2D = null
	if use_camera:
		marker = boss.get_camera_marker()
		if marker == null:
			temp_marker = Marker2D.new()
			host.add_child(temp_marker)
			temp_marker.global_position = boss.global_position
			marker = temp_marker
		GameEvents.emit_camera_move(marker, true)
		GameEvents.emit_ui_visible(false)
		GameEvents.emit_pause_lock(true)
		host.get_tree().paused = true
	boss.set_combat_enabled(false)
	boss.play_phase_anim(phase_index)
	await _wait_phase_signal(boss.boss_phase_anim_finished, phase_index, DEFAULT_TIMEOUT)
	if use_camera:
		release(host)
	if temp_marker != null and is_instance_valid(temp_marker):
		temp_marker.queue_free()
	if is_instance_valid(boss) and not boss._boss_dead:
		boss.set_combat_enabled(true)

static func play_escape(host: Node, boss: BossEnemy, policy: StringName = &"full") -> void:
	if host == null or boss == null or not is_instance_valid(boss):
		return
	var use_camera := policy != &"none" and _can_use_camera(boss)
	if use_camera:
		GameEvents.emit_pause_lock(true)
		host.get_tree().paused = true
	boss.set_combat_enabled(false)
	boss.play_escape_anim()
	await host.get_tree().create_timer(1.0, true, false, true).timeout
	if use_camera:
		release(host)

static func release(host: Node) -> void:
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	if host != null and host.is_inside_tree():
		host.get_tree().paused = false
	GameEvents.emit_pause_lock(false)

static func _can_use_camera(boss: BossEnemy) -> bool:
	if not boss.has_meta("network_remote_enemy"):
		return true
	if boss.boss_card == null:
		return false
	return boss.boss_card.network_remote_cinematic

static func _wait_phase_signal(sig: Signal, phase: int, timeout: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		await sig
		return
	var done: Array[bool] = [false]
	var cb := func(finished_phase: int):
		if finished_phase == phase:
			done[0] = true
	sig.connect(cb)
	var deadline := Time.get_ticks_msec() + int(maxf(0.1, timeout) * 1000.0)
	while not done[0] and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.05, true, false, true).timeout
	if sig.is_connected(cb):
		sig.disconnect(cb)

static func _wait_signal(sig: Signal, timeout: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		await sig
		return
	var done: Array[bool] = [false]
	var cb := func():
		done[0] = true
	sig.connect(cb)
	var deadline := Time.get_ticks_msec() + int(maxf(0.1, timeout) * 1000.0)
	while not done[0] and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.05, true, false, true).timeout
	if sig.is_connected(cb):
		sig.disconnect(cb)
