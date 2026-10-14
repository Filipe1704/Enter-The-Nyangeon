extends SceneTree

var failures := 0
var role := ""
var mode := ""
var directory := ""
var port := 0
var relay_url := ""
var session
var statuses: Array = []
var damage_proc_count := 0
var pre_damage_count := 0
class TestBullet extends Node:
	var damage_data
	var flight_time := 5.0

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
	if mode == "relay_queue":
		_relay_queue_case()
		_finish()
		return
	var level = load("res://resources/level/normal.tres")
	for field in ["level_id", "level_num", "level_hp", "level_damage", "level_score_mult", "level_reward"]:
		root.get_node("PlayerData").set(field, level.get(field))
	change_scene_to_file("res://scenes/main/menu_screen.tscn")
	await create_timer(0.3).timeout
	session.local_player_scene_path = session.DEFAULT_PLAYER_SCENE
	if mode.begins_with("cancel") and mode != "cancel_client_scene":
		await _cancel_case()
		_finish()
		return
	if mode in ["late_select", "late_ready"]:
		await _late_case()
		_finish()
		return
	var total := 3 if mode in ["rejoin3", "relay_rejoin3", "simultaneous_leave"] else 2
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
	if mode == "cancel_client_scene":
		await _cancel_remote_case()
		_finish(); return
	if mode == "coins":
		await _coin_case()
		_finish(); return
	if role == "host":
		session.begin_battle()
	if not await wait_until(func(): return current_scene != null and current_scene.scene_file_path == session.DEFAULT_BATTLE_SCENE and session.battle_active and session.player_by_peer_id.size() == total - 1, "正式关卡入场完成"):
		_finish(); return
	mark(role + "_battle")
	if role == "host":
		await wait_mark("client_battle")
		if total == 3: await wait_mark("survivor_battle")
		mark("battle_ready")
	else:
		await wait_mark("battle_ready")
	if mode == "simultaneous_leave":
		await _simultaneous_leave_case()
	elif mode in ["rejoin3", "relay_rejoin3"]:
		await _rejoin_case()
	elif mode == "upgrade":
		await _upgrade_case()
	elif mode == "damage":
		await _damage_case()
	_finish()

func _cancel_case():
	if mode == "cancel_new_session": session.auto_enter_lobby = false
	check(session.host_game(port), "开房受理")
	if mode == "cancel_lobby":
		await create_timer(0.05).timeout
		session.close_session()
		await create_timer(1.2).timeout
		check(current_scene.scene_file_path == session.MENU_SCENE, "取消开房后不进入准备房")
		check(not root.get_node("Transition").is_left_end_start, "取消开房后撤回转场黑幕")
	elif mode == "cancel_battle":
		await wait_until(func(): return session.battle_active, "准备房完成")
		var previous := current_scene.get_instance_id()
		session.begin_battle()
		await create_timer(0.05).timeout
		session.close_session()
		await create_timer(1.3).timeout
		check(current_scene.get_instance_id() == previous, "取消开战后不换场也不重载准备房")
		check(not root.get_node("Transition").is_left_end_start, "取消开战后撤回转场黑幕")
	else:
		var transient := Node2D.new()
		root.add_child(transient)
		session._on_visual_root_child_entered(transient)
		transient.free()
		await process_frame
		session._close_transport_soon()
		session.close_session()
		check(session.host_game(port), "立即重开同一端口")
		await create_timer(0.6).timeout
		check(session.is_lan_game, "旧延迟关闭不影响新会话")

func _cancel_remote_case():
	var transition = root.get_node("Transition")
	if role == "host":
		await wait_mark("client_baseline")
		session.begin_battle()
		mark("switching")
		await wait_mark("client_done")
	else:
		await wait_until(func(): return not transition.animation_player.is_playing(), "准备房入场动画完成")
		var previous := current_scene.get_instance_id()
		mark("client_baseline")
		await wait_mark("switching")
		await wait_until(func(): return transition.animation_player.current_animation == "left_start", "客机已开始换场转场")
		session.close_session()
		await create_timer(1.3).timeout
		check(current_scene.get_instance_id() == previous, "客机取消后旧换场协程不执行")
		check(not transition.is_left_end_start, "客机取消后撤回转场黑幕")
		mark("client_done")

func _late_case():
	if role == "host":
		check(session.host_game(port), "开房受理")
		await wait_until(func(): return session.battle_active, "准备房完成")
		session.request_begin_select()
		if mode == "late_ready": session.report_local_selection(session.DEFAULT_PLAYER_SCENE)
		mark("listen")
		await wait_mark("client_done")
		check(session.player_scene_by_peer.size() == 1, "被拒身份不进入 roster")
		check(session._handshaked_peers.is_empty(), "被拒身份不进入成员屏障")
		mark("done")
	else:
		await wait_mark("listen")
		check(session.join_game("127.0.0.1", port), "加入请求受理")
		await wait_until(func(): return not session.is_lan_game or session._hello_acked, "握手给出明确结果")
		check(not session._hello_acked and not session.is_lan_game, "选人后拒绝新身份")
		check(statuses.has("coop_session_started"), "显示本局已开始提示")
		check(current_scene.scene_file_path == session.MENU_SCENE, "被拒玩家保持菜单")
		mark("client_done")
		await wait_mark("done")

func _rejoin_case():
	if role == "client":
		var old_id: int = session.multiplayer.get_unique_id()
		session.dev_spawn_summoned()
		session.dev_grant_item("arale_hat")
		session.report_local_support("serina", {"rate_mult": 2.0})
		session.dev_force_local_downed()
		session.set_local_display_name("重连者")
		mark("owned", old_id)
		await wait_mark("host_before")
		await wait_mark("survivor_before")
		session.dev_drop()
		await wait_until(func(): return not session._reconnecting and session._hello_acked and (mode == "relay_rejoin3" or session.multiplayer.get_unique_id() != old_id), "重连握手成功")
		if mode == "relay_rejoin3": check(session.multiplayer.get_unique_id() == old_id, "Relay 实际复用旧 ID，覆盖同身份补生路径")
		mark("rejoined", {"old": old_id, "new": session.multiplayer.get_unique_id()})
		for net_id in session.summoned_by_net_id:
			var summoned = session.summoned_by_net_id[net_id]
			check(not session._summon_is_remote(summoned), "本地召唤物重连后仍归本机所有")
		var player = session.get_local_player()
		player.global_position += Vector2(50, 0)
		mark("position", {"x": player.global_position.x, "y": player.global_position.y})
		await wait_mark("host_checked")
		await wait_mark("survivor_checked")
		mark("done")
	else:
		await wait_mark("owned")
		var original: int = int(read_mark("owned"))
		await wait_until(func(): return session.summoned_owner_by_net_id.values().has(original), "重连前收到客机召唤物")
		await wait_until(func(): return session.item_ids_by_peer.get(original, []).has("arale_hat"), "重连前收到道具视觉")
		await wait_until(func(): return session.player_by_peer_id[original].is_downed, "重连前收到倒地状态")
		mark(role + "_before")
		await wait_mark("rejoined")
		var ids = read_mark("rejoined")
		var old_id := int(ids.old)
		var new_id := int(ids.new)
		await wait_until(func(): return session.player_by_peer_id.has(new_id), "存活端补建新身份镜像")
		if old_id != new_id:
			check(not session.player_by_peer_id.has(old_id), "存活端清理旧身份镜像")
			check(not session.player_scene_by_peer.has(old_id), "roster 清理旧身份")
		check(session.player_scene_by_peer.has(new_id), "roster 恢复身份")
		check(session.player_by_peer_id.size() == 2, "三端均保留两名远端玩家")
		await wait_until(func(): return session.summoned_owner_by_net_id.values().has(new_id), "重连后补回召唤物及新归属")
		if old_id != new_id: check(not session.summoned_owner_by_net_id.values().has(old_id), "召唤物无旧身份归属")
		check(session.item_ids_by_peer.get(new_id, []).has("arale_hat"), "恢复道具视觉记录")
		check(session.player_by_peer_id.get(new_id) != null and session.player_by_peer_id[new_id].is_downed, "恢复新镜像的倒地状态")
		check(session.support_by_peer.get(new_id) == "serina", "恢复支援选择")
		check(session.player_name_by_peer.get(new_id) == "重连者", "恢复显示名称")
		await wait_mark("position")
		var position = read_mark("position")
		var proxy = session.player_proxy_by_peer_id.get(new_id)
		await wait_until(func(): return proxy != null and is_instance_valid(proxy) and proxy.player.global_position.distance_to(Vector2(position.x, position.y)) < 15, "新身份位置持续更新")
		mark(role + "_checked")
		await wait_mark("done")

func _upgrade_case():
	if role == "host":
		root.get_node("GameEvents").emit_round_end()
		await wait_until(func(): return session._round_upgrade_active, "正式回合进入升级")
		mark("upgrade")
		await wait_mark("client_rejoined")
		var ids = read_mark("client_rejoined")
		check(session.round_upgrade_ready_peers.has(int(ids.new)), "已继续玩家在新身份下仍就绪")
		check(not session.round_upgrade_ready_peers.has(int(ids.old)), "屏障无旧身份残留")
		root.get_node("GameEvents").emit_round_upgrade_end()
		await wait_until(func(): return not session._round_upgrade_active and not session._round_upgrade_hold, "全员继续后推进回合")
		mark("host_advanced")
		await wait_mark("client_done")
	else:
		await wait_mark("upgrade")
		await wait_until(func(): return session._in_round_upgrade, "客机进入升级页")
		root.get_node("GameEvents").emit_round_upgrade_end()
		await wait_until(func(): return session._round_upgrade_hold, "客机继续并封面等待")
		await create_timer(0.7).timeout
		var old_id: int = session.multiplayer.get_unique_id()
		session.dev_drop()
		await wait_until(func(): return not session._reconnecting and session._hello_acked and session.multiplayer.get_unique_id() != old_id, "升级期间重连成功")
		mark("client_rejoined", {"old": old_id, "new": session.multiplayer.get_unique_id()})
		await wait_mark("host_advanced")
		await wait_until(func(): return not session._in_round_upgrade and not session._round_upgrade_hold, "客机退出升级等待")
		mark("client_done")

func _coin_case():
	var player = session.get_local_player()
	var initial: int = player.stats.coin
	var cumulative := 0
	var cases := [[100, 2.0, 200, false], [7, 1.25, 9, true], [100, 0.0, 0, false], [3, 1.0, 3, true]]
	for index in cases.size():
		var item: Array = cases[index]
		cumulative += int(item[2])
		var suffix := str(index)
		if role == "host":
			await wait_mark("multiplier" + suffix)
			session.dev_spawn_coin(int(item[0]))
			mark("coin" + suffix)
			await wait_mark("picked" + suffix)
			check(player.stats.coin == initial + cumulative, "房主共享收益正确：" + suffix)
			check(session.coin_by_net_id.is_empty(), "房主已消费金币，零倍率也不残留")
			mark("done" + suffix)
		else:
			player.stats.coin_mult = float(item[1])
			mark("multiplier" + suffix)
			await wait_mark("coin" + suffix)
			await wait_until(func(): return not session.coin_by_net_id.is_empty(), "收到网络金币")
			var net_id: int = int(session.coin_by_net_id.keys()[0])
			var coin = session.coin_by_net_id[net_id]
			var position: Vector2 = coin.global_position
			if bool(item[3]):
				session._sync_coin_multiplier(float(item[1]))
				session.rpc_id(1, "_server_pickup_coin", net_id, 99999999, position)
			else:
				session.dev_pickup_coin()
			await wait_until(func(): return session.coin_by_net_id.is_empty(), "客机金币已消费")
			check(player.stats.coin == initial + cumulative, "客机倍率/取整收益正确：" + suffix)
			session.rpc_id(1, "_server_pickup_coin", net_id, 99999999, position)
			await create_timer(0.15).timeout
			check(player.stats.coin == initial + cumulative, "重复拾取不重复结算")
			mark("picked" + suffix)
			await wait_mark("done" + suffix)

func _simultaneous_leave_case():
	if role == "host":
		# 暂停自动 poll，让两个客机的断开在同一次真实 ENet poll 中被处理。
		multiplayer_poll = false
		mark("leave_now")
		await wait_mark("client_closed")
		await wait_mark("survivor_closed")
		for index in 6:
			session.multiplayer.poll()
			await process_frame
		multiplayer_poll = true
		await wait_until(func(): return session.multiplayer.get_peers().is_empty(), "两端真实断开均已处理")
		check(session._handshaked_peers.is_empty(), "断开宽限清除握手成员")
		mark("host_checked")
	else:
		await wait_mark("leave_now")
		session.close_session()
		mark(role + "_closed")
		await wait_mark("host_checked")

func _relay_queue_case():
	var relay = load("res://mods/etn_coop/net/coop_relay_peer.gd").new()
	relay._unique_id = 1
	relay._known_peers = {1: "self", 2: "old"}
	relay._admitted = {2: true}
	var packet := PackedByteArray([2, 0, 0, 0, 42])
	relay._on_data(packet)
	relay._on_control('{"type":"peer_disconnected","peer_id":2}')
	check(relay._incoming.is_empty(), "断线通知前排队的包不再交给已移除 sender")
	relay._on_data(packet)
	check(relay._incoming.is_empty() and relay._peers_to_connect.is_empty(), "晚到数据不能复活已断线身份")
	relay._on_control('{"type":"peer_pending","peer_id":2,"name":"new"}')
	relay._on_data(packet)
	check(relay._incoming.size() == 1, "复用 ID 后只保留新连接数据")
	var events: Array = []
	relay.peer_connected.connect(func(id): events.append("connect" + str(id)))
	relay.peer_disconnected.connect(func(id): events.append("disconnect" + str(id)))
	if relay.has_method("_flush_peer_events"):
		relay._flush_peer_events()
		check(events == ["disconnect2", "connect2"], "同 poll 内先移除旧身份再接入新身份")
	else:
		check(false, "可验证的连接事件顺序入口")

func _damage_case():
	var events = root.get_node("GameEvents")
	if events.has_signal("enemy_damage_calculating"):
		events.connect("enemy_damage_calculating", func(_amount, _data, _path): pre_damage_count += 1)
	events.enemy_damage_taken.connect(func(_amount, _data, _path): damage_proc_count += 1)
	# 去掉与本场景无关的随机燃烧，固定数值只来自被测倍率/藏品。
	var player = session.get_local_player()
	for child in player.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("MomoiPS.gd"):
			child.free()
	var cases := [["melee", 20, false], ["closure", 20, false], ["mint", 20, false], ["true", 10, false], ["part", 10, true]]
	if role == "host":
		var path := "res://scenes/enemies/tester_automaton_shield.tscn"
		var enemy = load(path).instantiate()
		get_first_node_in_group("EnemiesRoot").add_child(enemy)
		enemy.global_position = player.global_position + Vector2(250, 0)
		enemy.active_state()
		enemy.frozen = true
		session.register_enemy_spawn(enemy, path)
		mark("damage_enemy", int(enemy.get_meta("net_id")))
		await wait_mark("damage_client_ready")
		for item in cases:
			var victim = enemy.body_part[0] if item[2] else enemy
			var hp: int = victim.stats.hp
			mark("hit_" + item[0])
			await wait_mark("sent_" + item[0])
			await wait_until(func(): return victim.stats.hp != hp, "房主收到真实命中 " + item[0])
			check(hp - victim.stats.hp == item[1], "权威 HP 差正确 " + item[0])
			mark("settled_" + item[0])
		check(pre_damage_count == 0 and damage_proc_count == 0, "房主不触发客机构筑的前置/后置 proc")
		await wait_mark("damage_done")
		mark("damage_host_checked")
	else:
		await wait_mark("damage_enemy")
		var id: int = int(read_mark("damage_enemy"))
		await wait_until(func(): return session.enemy_by_net_id.has(id), "客机收到实际敌人")
		var enemy = session.enemy_by_net_id[id]
		var peroro = load("res://scenes/update_item/peroro_wheel.tscn").instantiate()
		player.add_child(peroro)
		var mint = load("res://scenes/update_item/mint_chocolate_parfait.tscn").instantiate()
		player.add_child(mint)
		var callbacks: Array[int] = []
		mark("damage_client_ready")
		for item in cases:
			await wait_mark("hit_" + item[0])
			var victim = enemy.body_part[0] if item[2] else enemy
			var data = DamageData.make({"damage": 50 if item[2] else 10, "source": GameTags.EQUIP,
				"type": GameTags.MELEE_DAMAGE if item[0] == "melee" else GameTags.EQUIP_DAMAGE})
			if item[0] in ["closure", "part"]:
				data.damage_modifier.append(func(_victim, amount): return amount * 2)
			if item[0] == "true":
				data.flags.append(GameTags.TRUE_DAMAGE)
				data.damage_modifier.append(func(_victim, amount): return amount * 4)
			data.on_damage_dealt.append(func(_victim, amount): callbacks.append(int(amount)))
			if item[0] == "mint":
				data.damage_type.assign([GameTags.BULLET_DAMAGE])
				var bullet := TestBullet.new()
				bullet.damage_data = data
				player.add_child(bullet)
				events.emit_player_projectile_hit(bullet, enemy)
				check(session._gate_projectile_self_hit(bullet, enemy.get_node("HurtBox")), "自管理子弹命中被接管")
				bullet.queue_free()
			else:
				victim.health_component.take_damage(data)
			mark("sent_" + item[0])
			await wait_mark("settled_" + item[0])
			check(callbacks.back() == item[1], "命中闭包收到最终数值 " + item[0])
		await wait_until(func(): return damage_proc_count == 4, "归属端收到四次根命中后置 proc")
		check(callbacks.size() == 5, "本地命中生命周期各执行一次")
		check(pre_damage_count == 4, "前置阶段只处理四次非真实伤害，不随回传重复")
		mark("damage_done")
		await wait_mark("damage_host_checked")

func _finish():
	if session != null: session.close_session()
	print("COOP_RECOVERY mode=%s role=%s failures=%d" % [mode, role, failures])
	quit(1 if failures else 0)
