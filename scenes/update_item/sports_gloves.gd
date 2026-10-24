extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.bullet_damage_add += 5
