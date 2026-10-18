extends PanelContainer

@export var is_test: bool = false

@onready var cost = $Node2D/upgrade/Node2D/ColorRect/Coin
@onready var weapon_icon = $Node2D/RareColor/Weapon_icon
@onready var t_num_l = $Node2D/RareColor/TNumL
@onready var rare_color_c = $Node2D/RareColor
@onready var marker_2d = $Marker2D
@onready var upgrade = $Node2D/upgrade
@onready var smoke = preload("res://scenes/bullet/spread_smoke.tscn")

var t_num: int = 0
var icon_num: int = 0
var coin_cost:int = 0

var on_touch: bool = false
var _tooltip: HoverTooltipBinding

var player: Node

var rare_color: Array[Color] =[ Color(0.779, 0.795, 0.81), Color(0.464, 0.673, 0.832), Color(0.884, 0.764, 0.435), Color(0.985, 0.643, 0.909) ]

func _ready():
	_tooltip = HoverTooltipBinding.bind(upgrade, _tooltip_content, func(): return player != null, func(): on_touch = false)
	upgrade.mouse_entered.connect(mouse_in)
	upgrade.mouse_exited.connect(mouse_out)
	upgrade.gui_input.connect(mouse_selected.bind(upgrade))
	GameEvents.get_player.connect(get_player)
	GameEvents.player_card_touch.connect(touch_out)
	cost_count()

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	reset_data()

func reset_data():
	_tooltip.dismiss()
	t_num = 0
	icon_num = 0
	coin_cost = 0
	cost_count()
	item_text_get()
	t_num_l.text = "T" + str(t_num)

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")

func mouse_out():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")

func touch_out() -> void:
	_tooltip.dismiss()
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")

func touch_button(mode: String = "touch", index: int = -1):
	if not on_touch:
		GameEvents.emit_player_card_touch()
		on_touch = true
		mouse_in()
		_tooltip.preview(mode, index)
	else:

		if t_num >= 3:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return

		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			GameEvents.emit_player_ps_upgrade(t_num)

func mouse_selected(event: InputEvent, source: Control = null):

	if event is InputEventScreenTouch:
		if _tooltip.tapped(event, source):
			touch_button("touch", event.index)
		return

	if event.is_action_pressed("shoot"):

		if t_num >= 3:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return

		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			GameEvents.emit_player_ps_upgrade(t_num)

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

func smoke_anim():
	var ins = smoke.instantiate()
	ins.position = marker_2d.position
	add_child(ins)

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

func preview_from_navigation() -> void:
	GameEvents.emit_player_card_touch()
	on_touch = true
	mouse_in()
	_tooltip.preview("focus")

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
