extends Node

@export var test_mode: bool = false
@export var upgrade_pool: Array[AbilityUpgrade]
@export var round_time: Node
@export var upgrade_screen_scene: PackedScene
@export var weight_manager: ItemWeightManager
@export var round_weight_curve_1: Curve          # 根据回合调整权重
@export var round_weight_curve_2: Curve          # 根据回合调整权重
@export var round_weight_curve_3: Curve          # 根据回合调整权重
@export var round_pool_curve: Curve          # 根据回合调整池大小
@export var round_max: float = 20.0
var current_upgrades: Dictionary = {}
var player: Node
var now_round:float = 0
var tags_group: Dictionary = {}

# 内部池
var item_pool: Array[AbilityUpgrade] = []
var weighted_random: WeightedRandomSystem.AliasMethod
var is_pool_built: bool = false

# 池配置
@export_category("池配置")
@export var pool_size: int = 30
@export var min_items_per_category: int = 1
@export var enable_smart_grouping: bool = true
@export var diversity_bonus: float = 0.3

var refresh_mult: float = 0.0
var pool_mult: float = 1.0

func _ready():
	GameEvents.round_upgrade.connect(add_upgrade_card)
	GameEvents.round_upgrade.connect(round_weight_upgrade)
	GameEvents.round_end.connect(round_bouns_upgrade)
	GameEvents.get_player.connect(reset_data)
	GameEvents.add_player_upgrade.connect(apply_upgrade)
	for u in ModManager.get_content("upgrades"):
		if u != null and not upgrade_pool.has(u):
			upgrade_pool.append(u)

func reset_data():
	current_upgrades.clear()

func round_bouns_upgrade():
	if now_round < 20:
		now_round += 1.0
	weight_manager.defense_bonus += 0.3
	round_weight_upgrade()
	if test_mode == false:
		# 移动端外接鼠标时 HIDDEN 会让指针不可见且无法用鼠标选择；改为可见。
		if OS.has_feature("mobile"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func round_weight_upgrade():
	var round_local = float(min(now_round, 20)) / float(min(20, round_max))
	weight_manager.rarity_weights = {
		0: round_weight_curve_1.sample(round_local),
		1: round_weight_curve_2.sample(round_local),
		2: round_weight_curve_3.sample(round_local)
	}
	pool_size = round(round_pool_curve.sample(round_local))

func refresh_weight_upgrade():
	weight_manager.defense_bonus += 0.1
	# refresh_mult 表示额外增益，0 为中性；基准倍率始终保留 1。
	refresh_mult = (1.0 + refresh_mult) * 1.1 - 1.0
	pool_mult = max(0.2, pool_mult - 0.05)
	pool_size = max(10, pool_size * pool_mult)
	var round_local = now_round / round_max
	weight_manager.rarity_weights = {
		0: round_weight_curve_1.sample(round_local),
		1: round_weight_curve_2.sample(round_local),
		2: round_weight_curve_3.sample(round_local) * (1.0 + refresh_mult)
	}

func add_upgrade_card():
	if is_pool_built == true:
		refresh_weight_upgrade()
		is_pool_built = false
	var upgrade_screen_instance = upgrade_screen_scene.instantiate()
	add_child(upgrade_screen_instance)
	var chosen_upgrades = get_triple_choice(get_current_context())
	upgrade_screen_instance.set_ability_upgrades(chosen_upgrades as Array[AbilityUpgrade])
	upgrade_screen_instance.upgrade_selected.connect(on_upgrade_selected)
	upgrade_screen_instance.upgrade_reselect.connect(add_upgrade_card)

func apply_upgrade(upgrade:AbilityUpgrade):

	var has_upgrade = current_upgrades.has(upgrade.id)
	if !has_upgrade:
		current_upgrades[upgrade.id] = {
			"resource": upgrade,
			"quantity": 1,
			"order": upgrade.order_num
		}
		
		PlayerData.current_upgrades[upgrade.id] = {
			"upgrade_id": upgrade.id,
			"quantity": 1
		}
		
		player = PlayerRef.resolve(self)
		if player != null:
			var scene_path = "res://scenes/update_item/" + str(upgrade.id) + ".tscn"
			var mod_scene := ModManager.get_scene("upgrades", str(upgrade.id))
			if mod_scene != "":
				scene_path = mod_scene
			var scene = load(scene_path)
			if scene != null:
				var up_item = scene.instantiate()
				player.add_child(up_item)
			else:
				push_warning("[upgrade_manager] 缺少道具场景：%s" % scene_path)
		
		if current_upgrades[upgrade.id]["order"] > 0:
			current_upgrades[upgrade.id]["order"] -= 1
			#if current_upgrades[upgrade.id]["order"] == 0:
				#var remove_n = upgrade_pool.find(upgrade)
				#if remove_n != -1:
					#upgrade_pool.remove_at(remove_n)
		
		
	else:
		current_upgrades[upgrade.id]["quantity"] += 1
		PlayerData.current_upgrades[upgrade.id]["quantity"] += 1
		if current_upgrades[upgrade.id]["order"] > 0:
			current_upgrades[upgrade.id]["order"] -= 1
			#if current_upgrades[upgrade.id]["order"] == 0:
				#var remove_n = upgrade_pool.find(upgrade)
				#if remove_n != -1:
					#upgrade_pool.remove_at(remove_n)
	
	weight_manager.record_selection(upgrade)
	update_weight_manager_state()
	GameEvents.emit_ability_upgrade_added(upgrade, current_upgrades)
	refresh_mult = 0.0
	pool_mult = 1.0
	round_weight_upgrade()
	is_pool_built = false

func on_upgrade_selected(upgrade: AbilityUpgrade):
	apply_upgrade(upgrade)

# 构建道具池
func build_pool(context: Dictionary = {}):
	item_pool.clear()
	
	# 计算所有道具的权重
	var items: Array[AbilityUpgrade] = []
	var weights: Array[float] = []
	
	for item in upgrade_pool:
		var weight = weight_manager.calculate_item_weight(item, context)
		if weight > 0:
			items.append(item)
			weights.append(weight)
	
	# 构建权重随机系统
	weighted_random = WeightedRandomSystem.AliasMethod.new(weights)
	
	# 填充池子
	for i in range(pool_size):
		var index = weighted_random.next_index()
		item_pool.append(items[index])
	
	is_pool_built = true

# 获取三选一选项
func get_triple_choice(context: Dictionary = {}) -> Array[AbilityUpgrade]:
	if not is_pool_built:
		build_pool(context)
	if item_pool.size() < 3:
		push_error("Item pool too small!")
		return []
	var options: Array[AbilityUpgrade] = []
	options = get_random_options()
	return options

# 从池中随机获取道具
func get_random_item_from_pool() -> AbilityUpgrade:
	if item_pool.size() == 0:
		build_pool()
	
	return item_pool[randi() % item_pool.size()]

# 简单随机选项（备用）
func get_random_options() -> Array[AbilityUpgrade]:
	var options: Array[AbilityUpgrade] = []
	var attempts = 0
	
	while options.size() < 3 and attempts < 100:
		var item = get_random_item_from_pool()
		if not options.has(item):
			options.append(item)
		attempts += 1
	
	return options

# 更新权重管理器状态
func update_weight_manager_state():
	player = PlayerRef.ensure(self, player)
	if player != null:
		weight_manager.update_player_state({
			"health_percent": float(player.stats.hp) / maxf(1.0, float(player.stats.max_hp)),
			"current_upgrades": current_upgrades,
			"round": PlayerData.now_round,
			"difficulty": PlayerData.level_num
		})

func get_current_context() -> Dictionary:
	return {
		"floor": PlayerData.now_round,
		"difficulty": PlayerData.level_num,
		"player_tags": tags_group,
		"item_count": current_upgrades.size()
	}
