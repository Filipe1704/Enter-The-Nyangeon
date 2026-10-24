extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.collision_num_add += 1
