extends EquipItem

var luck_add: int = 0

func _on_equip():
	luck_count()

func _setup():
	PlayerData.player_ability_changed_end.connect(luck_count)
	PlayerData.reset_done.connect(_on_player_reset)

# reset_date() 已把 critical_luck_add 归零，丢弃本地记账，避免下次扣回不存在的贡献。
func _on_player_reset():
	luck_add = 0

# 幸运→暴击率写回管线字段，而非直接改 stats.critical_luck；这样未封顶总量仍供
# Hasumi PS1/PS3 等溢出消费方使用，判定值则继续受 PlayerData 的 101 上限约束。
func luck_count():
	var new_luck_add: int = max(0, round(player.stats.luck * 0.3))
	if new_luck_add == luck_add:
		return
	PlayerData.critical_luck_add -= luck_add
	luck_add = new_luck_add
	PlayerData.critical_luck_add += luck_add
	PlayerData.update_player_ability()
