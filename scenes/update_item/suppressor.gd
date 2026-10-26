extends EquipItem

@onready var Suppressor: PackedScene = preload("res://scenes/update_item/suppressor_icon.tscn")

func _on_equip():
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
	PlayerData.bullet_recoil_mult -= 0.1
	if player != null:
		player.gun.fire_sounds.pitch_scale *= 0.7

	attach_muzzle_icon(Suppressor)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
