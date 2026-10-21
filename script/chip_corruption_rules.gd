class_name ChipCorruptionRules

const CHIP_CORRUPTION_ID := "chip_corruption"
const ATTACK_CORRUPTION_RATIO := 0.02

static func attack_corruption(attacker: Node) -> int:
	if attacker == null or not is_instance_valid(attacker):
		return 0
	var existing = attacker.get("damage_data")
	if existing != null:
		var existing_power = existing.get("corruption_power")
		if existing_power != null and int(existing_power) > 0:
			return int(existing_power)
	var manager = attacker.get("enemy_buff_manager")
	if manager == null:
		var enemy_stats = attacker.get("stats")
		if enemy_stats != null:
			var owner_body = enemy_stats.get_parent()
			if owner_body != null:
				manager = owner_body.get("enemy_buff_manager")
	if manager == null:
		return 0
	var buffs = manager.get("current_buff")
	if buffs == null or not buffs.has(CHIP_CORRUPTION_ID):
		return 0
	var tree = attacker.get_tree()
	if tree == null:
		return 0
	var player = tree.get_first_node_in_group("Player")
	if player == null:
		return 0
	var player_stats = player.get("stats")
	if player_stats == null:
		return 0
	var amount = int(round(float(player_stats.get("max_hp")) * ATTACK_CORRUPTION_RATIO))
	if amount < 1:
		amount = 1
	return amount
