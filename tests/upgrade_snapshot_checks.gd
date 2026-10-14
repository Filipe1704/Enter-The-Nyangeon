extends SceneTree

var failures := 0
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: ", message)

func _run():
	var buffer = load("res://mod_sdk/coop_mod/mods/etn_coop/net/coop_snapshot_buffer.gd").new()
	buffer.push(100, Vector2.ZERO, Vector2(100, -50))
	buffer.push(200, Vector2(10, 20), Vector2(100, -50))
	var previous := Vector2(10, 20)
	for time in range(200, 500):
		check(buffer.sample(time), "有快照可采样")
		check(buffer.sample_pos.x >= previous.x and buffer.sample_pos.y <= previous.y, "有界外推沿速度方向单调移动")
		previous = buffer.sample_pos
		if time >= 320:
			check(buffer.sample_pos.is_equal_approx(Vector2(16, 17)), "外推上限保持积分末端位置")
			check(buffer.sample_vel == Vector2.ZERO, "外推上限后速度为零")
	buffer.push(500, Vector2(500, 0), Vector2.ZERO)
	check(buffer.consume_teleport(), "大位移仍识别为传送")
	buffer.sample(500)
	check(buffer.sample_pos == Vector2(500, 0), "新快照解除冻结")
	var player = load("res://scenes/player/momoi/momoi.tscn").instantiate()
	root.add_child(player)
	var pd = root.get_node("PlayerData")
	pd.player = player
	pd.reset_date()
	pd.get_player_base_ability()
	var manager = load("res://scenes/manager/upgrade_manager.tscn").instantiate()
	root.add_child(manager)
	manager.round_weight_upgrade()
	var initial: float = manager.weight_manager.rarity_weights[2]
	var last := initial
	for index in 3:
		manager.refresh_weight_upgrade()
		var weight: float = manager.weight_manager.rarity_weights[2]
		check(weight > last and weight > 0.0, "每次刷新保持最高稀有度并增长")
		last = weight
	manager.apply_upgrade(manager.upgrade_pool[0])
	check(manager.refresh_mult == 0.0, "选择后复位刷新增益")
	check(is_equal_approx(manager.weight_manager.rarity_weights[2], initial), "选择后恢复基准稀有度")
	player.stats.hp = player.stats.max_hp - 1
	manager.update_weight_manager_state()
	var fraction: float = manager.weight_manager.player_state.health_percent
	check(fraction > 0.3 and fraction < 1.0, "非满血使用真实浮点百分比")
	print("UPGRADE_SNAPSHOT_RESULT failures=", failures)
	quit(1 if failures else 0)
