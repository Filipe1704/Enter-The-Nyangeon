extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.fire_dot_layer_add += 3
