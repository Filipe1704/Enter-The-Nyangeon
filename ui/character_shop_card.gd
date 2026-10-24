extends "res://ui/shop_purchase_card.gd"

const TextureBinding := preload("res://script/lazy_texture_binding.gd")

@export var shop_card: CharacterCard

@onready var school: Label = %School
@onready var cost: Label = %Cost
@onready var name_1: Label = %Name1
@onready var name_2: Label = %Name2
@onready var weapon_icon: TextureRect = %WeaponIcon
@onready var weapon: Label = %Weapon
@onready var weapon_name: Label = %WeaponName
@onready var school_icon: TextureRect = %SchoolIcon
@onready var character_1: Sprite2D = %Character1
@onready var character_2: Sprite2D = %Character2

@onready var _portrait_binding = TextureBinding.new(self, [character_1, character_2])

func _ready() -> void:
	super._ready()
	get_card()

func get_card():
	if shop_card != null:
		name_1.text = shop_card.name_1
		name_2.text = shop_card.name_2
		weapon_name.text = shop_card.weapon_name
		# 武器类型名/图标：优先卡片自带；缺失时按 ModManager 注册表解析（通用合成商店卡的类型名/图标）。
		var wt: String = str(shop_card.weapon_type_name)
		weapon.text = ModManager.get_weapon_type_name(wt) if wt != "" else ""
		weapon_icon.texture = shop_card.weapon_icon
		if weapon_icon.texture == null and wt != "":
			weapon_icon.texture = ModManager.get_weapon_type_icon(wt)
		school.text = shop_card.school_name
		school_icon.texture = shop_card.school_icon
		cost.text = str(shop_card.cost)

# 立绘大图按需加载/释放（列表可见性由 shop_menu 调用）；幂等，避免重复解码
func reveal() -> void:
	if shop_card == null:
		return
	_portrait_binding.show_path(shop_card.character_sprite_path)

func conceal() -> void:
	_portrait_binding.clear()

func check_data():
	if shop_card != null:
		if PlayerData.character.has(shop_card.id):
			close_main_button()
			close_button()
			animation_player_2.play("deal_anim")

func add_character():
	if !PlayerData.character.has(shop_card.id):
		PlayerData.character.push_back(shop_card.id)
		Game.save_playerdata()
	if shop_card.group != "" and !PlayerData.group.has(shop_card.group):
		PlayerData.group.push_back(shop_card.group)
		Game.save_playerdata()
	# 解锁后通知各处刷新（社团列表动态补建 / 角色卡过滤等）
	GameEvents.emit_check_data()

func _get_purchase_cost() -> int:
	return shop_card.cost

func _grant_purchase() -> void:
	add_character()
