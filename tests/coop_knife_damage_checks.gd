extends "res://tests/coop_item_visual_checks.gd"

# 通过真实菜刀 → HurtBox → 联机拦截器 → 主机结算 → 飘字信号，比较同一命中。
var displayed: Array[int] = []
var confirmed: Array[int] = []
var hit_hps: Array[int] = []

func _item_visual_case():
	if not await wait_until(func(): return not session.enemy_by_net_id.is_empty(), "预置敌人已同步"):
		return
	if role == "host":
		mark("damage_target", session._preplaced_ids_sorted()[0])
	await wait_mark("damage_target")
	var net_id := int(read_mark("damage_target"))
	if not await wait_until(func(): return session.enemy_by_net_id.has(net_id), "伤害目标镜像已同步"):
		return
	var enemy = session.enemy_by_net_id[net_id]
	var component = session._health_component_of(enemy)
	component.damage_taken.connect(func(amount, _data):
		displayed.append(amount)
		hit_hps.append(int(enemy.stats.hp)))
	root.get_node("GameEvents").enemy_damage_taken.connect(func(amount, _data, path):
		if path == enemy.get_path(): confirmed.append(amount))
	var player = session.get_local_player()
	player.set_physics_process(false)
	player.gun.set_physics_process(false)
	var knife
	if role == "client":
		knife = load("res://scenes/update_item/kitchen_knife.tscn").instantiate()
		player.add_child(knife)
		knife.set_physics_process(false)
		knife.hit_box.set_deferred("monitoring", false)
		knife.hit_box.set_deferred("monitorable", false)
		knife.enemy_group.assign([component.hurt_box])
		player.stats.critical_luck = 0
		player.stats.equip_damage = 1.0
		player.stats.global_damage = 1.0
		root.get_node("PlayerData").kick_damage_mult = 1.0
	await physics_frame
	var cases := [
		{"name": "neutral", "mult": 1.0, "hp": 1000},
		{"name": "resistance", "mult": 0.5, "hp": 1000},
		{"name": "vulnerability", "mult": 2.0, "hp": 1000},
		{"name": "execute", "mult": 1.0, "hp": 50},
		{"name": "ordinary_damage", "mult": 2.0, "hp": 1000},
		{"name": "ordinary_overkill", "mult": 1.0, "hp": 30},
		{"name": "execute_reset", "mult": 1.0, "hp": 50},
	]
	for fixture in cases:
		var key: String = fixture.name
		enemy.stats.max_hp = 1000
		# 除专门的回血用例外，固定目标不触发沙袋死亡后的自动回血。
		enemy.stats.dead_lock = key != "execute_reset"
		enemy.stats.hp = fixture.hp
		enemy.stats.global_hurt_damage = fixture.mult
		displayed.clear()
		confirmed.clear()
		hit_hps.clear()
		var damage_before := 0
		var attacker := int(session.player_by_peer_id.keys()[0])
		if role == "host": damage_before = int(session._ensure_team_stat(attacker).damage)
		mark(role + "_damage_ready_" + key)
		await wait_mark(("client" if role == "host" else "host") + "_damage_ready_" + key)
		if role == "client":
			# 旧快照可能在等待屏障时覆盖测试属性；命中前同步复位，隔离本次命中。
			enemy.stats.max_hp = 1000
			enemy.stats.hp = fixture.hp
			enemy.stats.global_hurt_damage = fixture.mult
			enemy.set_meta("predicted_hp", int(fixture.hp))
			var proxy = session.enemy_proxy_by_net_id.get(net_id)
			if proxy != null: proxy.reset_prediction_state()
			if key.begins_with("ordinary_"):
				component.take_damage(DamageData.equip_hit(45, knife))
			else:
				knife.damage_add()
			if not key.begins_with("execute") and key != "ordinary_overkill":
				var expected_loss := 90 if key == "ordinary_damage" else 45
				check(int(enemy.get_meta("predicted_hp")) == int(fixture.hp) - expected_loss, "预测血量只应用一次正确承伤倍率 " + key)
			mark("damage_sent_" + key)
			await wait_until(func(): return not confirmed.is_empty(), "客机收到权威命中 " + key, 3)
		else:
			await wait_mark("damage_sent_" + key)
			await wait_until(func(): return not displayed.is_empty(), "主机处理菜刀命中 " + key, 3)
			var damage_delta: int = int(session._ensure_team_stat(attacker).damage) - damage_before
			var hit_hp: int = hit_hps[0] if not hit_hps.is_empty() else int(fixture.hp)
			check(damage_delta == maxi(0, int(fixture.hp) - hit_hp), "记分伤害仍按有效扣血计算 %s（delta=%d，hp=%d）" % [key, damage_delta, hit_hp])
			if key == "execute_reset":
				await wait_until(func(): return enemy.stats.hp == enemy.stats.max_hp, "沙袋命中后恢复生命", 1)
			mark("damage_authority_" + key, {"displayed": displayed, "hp": hit_hp})
		await wait_mark("damage_authority_" + key)
		var authority = read_mark("damage_authority_" + key)
		var authority_display: Array[int] = []
		for amount in authority.displayed:
			authority_display.append(int(amount))
		print("KNIFE_DAMAGE role=%s case=%s displayed=%s authority=%s hp_loss=%d" % [role, key, displayed, authority.displayed, int(fixture.hp) - int(authority.hp)])
		check(displayed.size() == 1, "同次菜刀命中只显示一次 " + key)
		check(displayed == authority_display, "客机与主机同次菜刀伤害数字一致 " + key)
		if role == "client":
			var expected: int = 99999 if key.begins_with("execute") else (90 if key == "ordinary_damage" else 45)
			check(displayed == [expected], "菜刀真实伤害不受承伤倍率影响，斩杀保留命中伤害 " + key)
		mark(role + "_damage_checked_" + key)
		await wait_mark(("client" if role == "host" else "host") + "_damage_checked_" + key)
