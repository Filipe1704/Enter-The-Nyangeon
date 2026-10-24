extends "res://ui/shop_purchase_card.gd"

@export var shop_card: ClothesCard

@onready var user_name_2: Label = %UserName2
@onready var cost: Label = %Cost
@onready var name_1: Label = %Name1
@onready var name_2: Label = %Name2
@onready var user_name_1: Label = %UserName1
@onready var item_1: Sprite2D = %Item1
@onready var item_2: Sprite2D = %Item2

func _ready() -> void:
	super._ready()
	get_card()

func get_card():
	if shop_card != null:
		name_1.text = shop_card.name_1
		name_2.text = shop_card.name_2
		item_1.texture = shop_card.icon_2
		item_2.texture = shop_card.icon_2
		user_name_1.text = shop_card.user_name
		user_name_2.text = shop_card.user_name
		cost.text = str(shop_card.cost)

func check_data():
	if shop_card != null:
		var group: Array = PlayerData.clothes_group.get(shop_card.id_name, [])
		if group.has(shop_card.id):
			close_main_button()
			close_button()
			animation_player_2.play("deal_anim")

func add_item():
	var group: Array = PlayerData.clothes_group.get(shop_card.id_name, [])
	if !group.has(shop_card.id):
		group.push_back(shop_card.id)
		PlayerData.clothes_group[shop_card.id_name] = group
		Game.save_playerdata()

func _get_purchase_cost() -> int:
	return shop_card.cost

func _grant_purchase() -> void:
	add_item()
