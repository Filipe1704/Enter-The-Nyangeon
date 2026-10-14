extends SceneTree

var failures := 0
var role := ""
var mode := ""
var directory := ""
var port := 0
var relay_url := ""
var session
var statuses: Array = []

func _initialize(): _run.call_deferred()

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: " + message)

func mark(key: String, value = true):
	var path := directory.path_join(key)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)

func read_mark(key: String):
	return JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(key)))

func wait_until(predicate: Callable, message: String, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var ok: bool = predicate.call()
	check(ok, message)
	return ok

func wait_mark(key: String) -> bool:
	return await wait_until(func(): return FileAccess.file_exists(directory.path_join(key)), "等待屏障 " + key)

func _run():
	await process_frame
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--role="): role = value
		if arg.begins_with("--mode="): mode = value
		if arg.begins_with("--directory="): directory = value
		if arg.begins_with("--port="): port = int(value)
		if arg.begins_with("--relay-url="): relay_url = value
	session = load("res://mods/etn_coop/net/coop_net.gd").instance
	session.settings.upnp_enabled = false
	session.connection_status_changed.connect(func(value): statuses.append(value))
	var level = load("res://resources/level/normal.tres")
	for field in ["level_id", "level_num", "level_hp", "level_damage", "level_score_mult", "level_reward"]:
		root.get_node("PlayerData").set(field, level.get(field))
	change_scene_to_file("res://scenes/main/menu_screen.tscn")
	await create_timer(0.3).timeout
	session.local_player_scene_path = session.DEFAULT_PLAYER_SCENE
	var total := 2
	if role == "host":
		if relay_url.is_empty():
			check(session.host_game(port), "开房受理")
		else:
			session.create_relay_room(relay_url)
		if not await wait_until(func(): return session.battle_active, "准备房完成"):
			_finish(); return
		mark("listen", session.relay_room_code)
	else:
		if not await wait_mark("listen"):
			_finish(); return
		check(session.join_game("127.0.0.1", port) if relay_url.is_empty() else session.join_relay_room(relay_url, str(read_mark("listen"))), "加入受理")
	if not await wait_until(func(): return session.battle_active and session.player_by_peer_id.size() == total - 1, "全端准备房镜像齐全"):
		_finish(); return
	# 房主镜像就绪不代表客机已处理完 roster，等双方确认后再检查道具。
	mark(role + "_lobby")
	if role == "host":
		await wait_mark("client_lobby")
	await _item_visual_case()
	_finish()

func _finish():
	if session != null:
		session.close_connection(true)
		# 只验证本次新增的道具缓存迁移，不依赖其他身份恢复修复。
		var visual := Node2D.new()
		session.item_ids_by_peer[101] = ["little_kei"]
		session.item_visual_by_peer[101] = [visual]
		session.item_states_by_peer[101] = {"little_kei": {"scale": 1.1}}
		session._migrate_peer_state(101, 102)
		check(session.item_ids_by_peer.get(102, []) == ["little_kei"] and not session.item_ids_by_peer.has(101), "道具 id 随房主身份迁移")
		check(session.item_visual_by_peer.get(102, []) == [visual] and not session.item_visual_by_peer.has(101), "道具外观列表随房主身份迁移")
		check(session.item_states_by_peer.get(102, {}).get("little_kei", {}).get("scale") == 1.1 and not session.item_states_by_peer.has(101), "道具显示缓存随房主身份迁移")
		session.item_ids_by_peer.clear()
		session.item_visual_by_peer.clear()
		session.item_states_by_peer.clear()
		visual.free()
	print("COOP_ITEMS mode=%s role=%s failures=%d" % [mode, role, failures])
	quit(1 if failures else 0)

func _item_nodes(peer: int, id: String) -> Array:
	var found: Array = []
	for node in session.item_visual_by_peer.get(peer, []):
		if is_instance_valid(node) and node.scene_file_path.get_file().get_basename() in [id, id + "_icon"]:
			found.append(node)
	return found

func _item_visual_case():
	mark(role + "_items_ready")
	await wait_mark(("client" if role == "host" else "host") + "_items_ready")
	await create_timer(1.1).timeout
	var player = session.get_local_player()
	var events = root.get_node("GameEvents")
	var item_state = load("res://mods/etn_coop/net/coop_item_state.gd")
	var malformed: Dictionary = item_state.sanitize({
		"unknown_item": {},
		"little_kei": {"phase": NAN, "speed": INF, "scale": -INF, "animations": [["arbitrary_method", 1.0, true]]},
		"life_jacket": {"shield": "true", "animations": [["new_animation", INF, 1]]},
	})
	check(not malformed.has("unknown_item") and is_finite(malformed.little_kei.phase) and malformed.little_kei.animations[0].is_empty(), "道具快照拒绝未知动画与非有限数值")
	check(not malformed.life_jacket.shield and malformed.life_jacket.animations[0].is_empty(), "道具快照拒绝错误字段类型")
	if events.crosshair_position.is_connected(player.get_crosshair_pos):
		events.crosshair_position.disconnect(player.get_crosshair_pos)
	player.set_physics_process(false)
	var peer: int = session.player_by_peer_id.keys()[0]
	var local: Dictionary = {}
	var ids := ["kitchen_knife", "little_kei", "life_jacket", "ginseng_doll", "energy_supplement"]
	for id in ids:
		local[id] = load("res://scenes/update_item/%s.tscn" % id).instantiate()
		player.add_child(local[id])
		session._on_local_ability_upgrade_added(load("res://resources/upgrades/%s.tres" % id), {})
	mark(role + "_items")
	await wait_mark(("client" if role == "host" else "host") + "_items")
	if not await wait_until(func(): return _item_nodes(peer, "energy_supplement").size() > 0, "动态道具远端副本建成", 3): return
	var mirror = session.player_by_peer_id[peer]
	var aim_index := 0
	for offset in [Vector2(300, 250), Vector2(-300, -250), -player.global_position]:
		player.crosshair_pos = player.global_position + offset
		var aim_key := "_aim_" + str(aim_index)
		mark(role + aim_key, [player.crosshair_pos.x, player.crosshair_pos.y])
		var other_role := "client" if role == "host" else "host"
		await wait_mark(other_role + aim_key)
		var received: Array = read_mark(other_role + aim_key)
		var expected := Vector2(received[0], received[1])
		await wait_until(func(): return mirror.crosshair_pos.is_equal_approx(expected), "镜像瞄准字段已回填", 1)
		await process_frame
		var knife = _item_nodes(peer, "kitchen_knife")[0].get_node("knife")
		# 所有权端收到的目标与刀刃实际朝向应一致，世界原点也是合法目标。
		check(absf(wrapf(knife.global_rotation - knife.global_position.direction_to(expected).angle(), -PI, PI)) < 0.05, "菜刀双向/原点瞄准")
		mark(role + aim_key + "_checked")
		await wait_mark(other_role + aim_key + "_checked")
		aim_index += 1
	await _knife_smoothness_probe(player, peer, local)
	local.little_kei._apply_effect(2)
	await create_timer(0.2).timeout
	var kei = _item_nodes(peer, "little_kei")[0]
	var path = kei.get_node("Path2D/PathFollow2D")
	var before: float = path.progress_ratio
	await create_timer(0.15).timeout
	check(absf(wrapf(path.progress_ratio - before, -0.5, 0.5)) > 0.005, "小小凯伊远端绕行")
	check(kei.get_node("Path2D/PathFollow2D/Kei/Area2D").scale.is_equal_approx(Vector2(1.1, 1.1)), "小小凯伊叠加范围同步")
	# 获取消息不重发：后续快照必须能够补回被释放的动态副本。
	var lost = _item_nodes(peer, "ginseng_doll")[0]
	session.item_visual_by_peer[peer].erase(lost)
	lost.queue_free()
	await wait_until(func(): return _item_nodes(peer, "ginseng_doll").size() == 1, "持续快照补建缺失道具", 1)
	local.life_jacket.player_get_hurt()
	local.ginseng_doll.add_damage_health(5)
	# 测试房自带不死保护会立即把 hp=0 回满；本例需触发真实保命回调。
	if player.stats.hp_changed.is_connected(current_scene.protect_player):
		player.stats.hp_changed.disconnect(current_scene.protect_player)
	player.stats.hp = 0
	local.energy_supplement.fatal_damage_health(999)
	mark(role + "_items_triggered")
	await wait_mark(("client" if role == "host" else "host") + "_items_triggered")
	for id in ["life_jacket", "ginseng_doll", "energy_supplement"]:
		await wait_until(func(): return _item_nodes(peer, id)[0].get_node("Node2D/AnimationPlayer").is_playing(), "远端触发动画 " + id, 0.8)
	var jacket = _item_nodes(peer, "life_jacket")[0]
	check(not jacket.get_node("Node2D2").visible, "救生衣抵挡后隐藏护盾")
	# 动画不得重新开启镜像伤害判定。
	for shape in jacket.find_children("*", "CollisionShape2D", true, false):
		check(shape.disabled, "纯视觉动画保持碰撞禁用")
	for area in jacket.find_children("*", "Area2D", true, false):
		check(area.collision_layer == 0 and area.collision_mask == 0 and not area.monitoring, "纯视觉动画保持监测禁用")
	mark(role + "_items_checked")
	await wait_mark(("client" if role == "host" else "host") + "_items_checked")
	local.life_jacket.add_player_hurt_invalid()
	await wait_until(func(): return jacket.get_node("Node2D2/AnimationPlayer").is_playing(), "救生衣恢复动画同步", 0.8)
	for id in ["little_kei", "black_ninpero", "cowboy_hat", "sniper_scope", "suppressor"]:
		for i in range(2): session._on_local_ability_upgrade_added(load("res://resources/upgrades/%s.tres" % id), {})
	await create_timer(0.2).timeout
	for id in ["little_kei", "black_ninpero", "cowboy_hat", "sniper_scope", "suppressor"]:
		check(_item_nodes(peer, id).size() == 1, "重复升级不重复生成 " + id)
	session._rebuild_peer_item_visuals(peer)
	await create_timer(0.2).timeout
	check(_item_nodes(peer, "little_kei").size() == 1, "重建后外观仍唯一")
	check(_item_nodes(peer, "little_kei")[0].get_node("Path2D/PathFollow2D/Kei/Area2D").scale.is_equal_approx(Vector2(1.1, 1.1)), "重建后恢复道具状态")
	local.ginseng_doll.end_damage_health()
	mark(role + "_items_done")
	await wait_mark(("client" if role == "host" else "host") + "_items_done")


# 逐帧平滑度探针（2026-10-15）：拥有者准星连续扫动，按帧采样远端镜像刀刃朝向。
# 只按快照到达更新的实现会在快照间隔内保持不动（20Hz 台阶），hold 比例可直接量化“很卡”。
func _knife_smoothness_probe(player, peer: int, local_items: Dictionary) -> void:
	var mirror_knives := _item_nodes(peer, "kitchen_knife")
	if mirror_knives.is_empty():
		check(false, "平滑度探针需要远端菜刀副本")
		return
	var mirror_knife: Node2D = mirror_knives[0].get_node("knife")
	var local_knife: Node2D = local_items.kitchen_knife.get_node("knife")
	var old_max_fps: int = Engine.max_fps
	Engine.max_fps = 60
	# 目标圆心取镜像自身位置：准星在镜像右侧 ±1.2rad 内往返扫动。
	# 弧线保持在右侧可避免镜像 graphics.scale.x 翻面（翻面会让 global_rotation 折叠出 π 假跳变），
	# 从而把「只按快照到达才更新」的台阶单独量化出来。
	var mirror = session.player_by_peer_id[peer]
	var center: Vector2 = mirror_knife.global_position
	var frames := 0
	var mirror_holds := 0
	var local_holds := 0
	var mirror_max_step := 0.0
	var mirror_max_error := 0.0
	# 预热 40 帧：让上一段静态瞄准的过渡完全消失后再取样。
	var phase_frames := 0
	for i in range(40):
		var warm_u := float(phase_frames % 120) / 120.0
		var warm_tri := 2.0 * warm_u if warm_u <= 0.5 else 2.0 * (1.0 - warm_u)
		var warm_sweep := -1.2 + 2.4 * warm_tri
		player.crosshair_pos = center + Vector2(cos(warm_sweep), sin(warm_sweep)) * 200.0
		phase_frames += 1
		await process_frame
	var mirror_prev: float = mirror_knife.global_rotation
	var local_prev: float = local_knife.global_rotation
	for i in range(120):
		var u := float(phase_frames % 120) / 120.0
		var tri := 2.0 * u if u <= 0.5 else 2.0 * (1.0 - u)
		var sweep := -1.2 + 2.4 * tri
		player.crosshair_pos = center + Vector2(cos(sweep), sin(sweep)) * 200.0
		phase_frames += 1
		await process_frame
		frames += 1
		var mirror_step: float = absf(wrapf(mirror_knife.global_rotation - mirror_prev, -PI, PI))
		var local_step: float = absf(wrapf(local_knife.global_rotation - local_prev, -PI, PI))
		if mirror_step < 0.0005:
			mirror_holds += 1
		if local_step < 0.0005:
			local_holds += 1
		mirror_max_step = maxf(mirror_max_step, mirror_step)
		var aim = mirror.get("crosshair_pos")
		if aim is Vector2 and not aim.is_equal_approx(mirror_knife.global_position):
			mirror_max_error = maxf(mirror_max_error, absf(wrapf(mirror_knife.global_rotation - mirror_knife.global_position.direction_to(aim).angle(), -PI, PI)))
		mirror_prev = mirror_knife.global_rotation
		local_prev = local_knife.global_rotation
	Engine.max_fps = old_max_fps
	var mirror_ratio := float(mirror_holds) / float(maxi(1, frames))
	var local_ratio := float(local_holds) / float(maxi(1, frames))
	print("KNIFE_SMOOTH role=%s frames=%d mirror_hold=%.3f owner_hold=%.3f mirror_max_step=%.4f mirror_max_error=%.4f" % [role, frames, mirror_ratio, local_ratio, mirror_max_step, mirror_max_error])
	check(mirror_ratio <= 0.15, "远端菜刀镜像逐帧平滑（mirror_hold=%.3f）" % mirror_ratio)
	check(mirror_max_step <= 0.15, "远端菜刀镜像无台阶跳变（max_step=%.4f）" % mirror_max_step)
	check(mirror_max_error <= 0.2, "远端菜刀朝向对准镜像准星（max_error=%.4f）" % mirror_max_error)
