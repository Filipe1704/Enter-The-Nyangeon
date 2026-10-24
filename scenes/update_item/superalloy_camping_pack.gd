extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.bullet_penetrate_add += 2
