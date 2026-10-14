extends SceneTree

class Target extends Node2D:
	var stats
	var health_component
	var player_card
	var faction := Faction.ENEMY_SIDE
	var damage_modifier: Array[Callable] = []

var failures := 0
var net
var target
var health
var damage_script
func _initialize(): _run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		print("FAIL: ", message)

func make_hit(kind: String = GameTags.BULLET_DAMAGE):
	return damage_script.make({"damage": 10, "type": kind, "source": GameTags.PLAYER})

func compare_wire(data, expected: int, full: bool = true):
	var hp: int = 1000 if full else 500
	target.stats.hp = hp
	health.take_damage(data)
	check(hp - target.stats.hp == expected, "本体结算符合效果数值：实际 %d / 预期 %d" % [hp - target.stats.hp, expected])
	target.stats.hp = hp
	var cfg = net._prepare_enemy_hit(target, data) if net.has_method("_prepare_enemy_hit") else net._damage_to_dict(data)
	var restored = damage_script.make(net._sanitize_for_authority(cfg))
	if cfg.has("resolved_damage"):
		health.take_damage(restored, true, true, int(cfg.resolved_damage))
	else:
		health.take_damage(restored, true, true)
	check(hp - target.stats.hp == expected, "真实 wire 往返后权威扣血与本体相同")
	check(restored.damage_modifier.is_empty(), "协议不携带 Callable")
	check(health.damage_multiplier == 1.0, "本次命中的倍率被消费")

func _run():
	await process_frame
	net = load("res://mods/etn_coop/net/coop_net.gd").instance
	damage_script = load("res://script/damage_data.gd")
	target = Target.new()
	root.add_child(target)
	target.global_position = Vector2(200, 0)
	target.stats = load("res://script/EnemyStats.gd").new()
	target.stats.max_hp = 1000
	target.stats.global_hurt_damage = 0.5
	target.add_child(target.stats)
	var hurt = load("res://script/hurt_box.gd").new()
	target.add_child(hurt)
	health = load("res://script/health_component.gd").new()
	health.stats = target.stats
	health.hurt_box = hurt
	target.add_child(health)
	health.owner = target
	target.health_component = health
	var data = make_hit()
	data.damage_modifier.append(func(_victim, amount): return amount * 2)
	compare_wire(data, 10)
	# 实际 Hina 距离闭包，目标距攻击者 200px；承伤 0.5 只应用一次。
	var player = Target.new()
	root.add_child(player)
	player.add_to_group("Player")
	player.player_card = load("res://resources/player/momoi.tres")
	player.stats = load("res://script/Stats.gd").new()
	player.add_child(player.stats)
	var pd = root.get_node("PlayerData")
	pd.player = player
	pd.reset_date()
	pd.get_player_base_ability()
	var hina = load("res://scenes/player/hina/hina_ps.gd").new()
	hina.player = player
	hina.apply_distance_bullet_mod()
	data = make_hit()
	data.damage_modifier.assign(player.damage_modifier)
	compare_wire(data, 10)
	hina.free()
	# 实际藏品订阅链：满血近战翻倍 / 半血近战增伤。
	var peroro = load("res://scenes/update_item/peroro_wheel.gd").new()
	root.add_child(peroro)
	compare_wire(make_hit(GameTags.MELEE_DAMAGE), 10)
	peroro.free()
	var solvent = load("res://scenes/update_item/solvent_extraction_set.gd").new()
	root.add_child(solvent)
	compare_wire(make_hit(GameTags.MELEE_DAMAGE), 12, false)
	solvent.free()
	# Kotori 的临时命中修饰不能留在可穿透复用的 DamageData 上。
	var kotori = load("res://scenes/player/kotori/KotoriPS.gd").new()
	kotori.stats = load("res://script/Stats.gd").new()
	kotori.stats.max_hp = 100
	root.add_child(kotori.stats)
	var events = root.get_node("GameEvents")
	var phase := "enemy_damage_calculating" if events.has_signal("enemy_damage_calculating") else "enemy_damage_taken"
	events.connect(phase, kotori.add_max_hp_damage)
	data = make_hit()
	compare_wire(data, 15)
	compare_wire(data, 15)
	check(data.damage_modifier.is_empty(), "命中阶段添加的修饰不积累到下一次命中")
	events.disconnect(phase, kotori.add_max_hp_damage)
	kotori.free()
	data = make_hit()
	data.flags.append(GameTags.TRUE_DAMAGE)
	data.damage_modifier.append(func(_victim, amount): return amount * 4)
	health.damage_multiplier = 3.0
	compare_wire(data, 10)
	compare_wire(make_hit(), 5)
	check(not net._sanitize_for_authority({"damage": 10, "resolved_damage": INF}).has("resolved_damage"), "拒收非有限的已计算伤害")
	check(not net._sanitize_for_authority({"damage": 10, "resolved_damage": "20"}).has("resolved_damage"), "拒收非数值的已计算伤害")
	health.damage_multiplier = 3.0
	health.is_invincible = true
	check(health.resolve_damage(make_hit()) == 0 and health.damage_multiplier == 1.0, "被拒绝的命中不泄漏预先写入的倍率")
	health.is_invincible = false
	compare_wire(make_hit(), 5)
	print("DAMAGE_CONTRACT_RESULT failures=", failures)
	quit(1 if failures else 0)
