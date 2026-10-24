extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.max_ammo_add += 50
	PlayerData.reload_timer_mult += 1
