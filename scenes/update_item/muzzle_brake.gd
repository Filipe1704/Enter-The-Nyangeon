extends EquipItem

@onready var muzzle_brake: PackedScene = preload("res://scenes/update_item/muzzle_brake_icon.tscn")

func _on_equip():
	PlayerData.bullet_recoil_mult -= 0.4
	attach_muzzle_icon(muzzle_brake)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_recoil_mult -= 0.4
