extends "res://ui/ability_shop_card_base.gd"

@export var is_test: bool = false

@onready var cost = $Node2D/upgrade/Node2D/ColorRect/Coin
@onready var weapon_icon = $Node2D/RareColor/Weapon_icon
@onready var t_num_l = $Node2D/RareColor/TNumL
@onready var rare_color_c = $Node2D/RareColor

func _on_ready_extra() -> void:
	cost_count()

func reset_data():
	_tooltip.dismiss()
	t_num = 0
	icon_num = 0
	coin_cost = 0
	cost_count()
	item_text_get()
	t_num_l.text = "T" + str(t_num)

func cost_count():
	if is_test == false:
		if t_num == 0:
			coin_cost = 150
		elif t_num == 1:
			coin_cost = 800
		elif t_num == 2:
			coin_cost = 2000

		cost.text = str(coin_cost)
	else:
		coin_cost = 0
		cost.text = "FREE"

func item_text_get():

	weapon_icon.texture = player.ps_card.weapon_icon

	if t_num == 0:
		rare_color_c.color = rare_color[0]
	elif t_num == 1:
		rare_color_c.color = rare_color[1]
	elif t_num == 2:
		rare_color_c.color = rare_color[2]
	else:
		rare_color_c.color = rare_color[3]


# 本地化缺失时回退到角色描述，避免显示原始键（如 xxx_ps_1）
func _ps_text(card, idx: int) -> String:
	if card == null:
		return ""
	var key: String = str(card.id) + "_ps_" + str(idx)
	var t := tr(key)
	return t if t != key else str(card.description)

func item_upgrade():

	if t_num >= 3:
		return

	t_num += 1
	cost_count()
	item_text_get()
	smoke_anim()
	t_num_l.text = "T" + str(t_num)
	if t_num >= 3:
		cost.text = "MAX"

func _upgrade_cap() -> int:
	return 3

func _on_purchased() -> void:
	GameEvents.emit_player_ps_upgrade(t_num)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and player != null:
		item_text_get()

func _tooltip_content() -> Array:
	if player == null:
		return []
	var segments: Array = []
	for index in 4:
		segments.append({"text": _ps_text(player.player_card, index), "role": "body" if index <= t_num else "muted", "translated": true})
	return segments
