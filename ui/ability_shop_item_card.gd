extends PanelContainer

@export var equip_card: Equip
@export var is_test: bool = false

@onready var texture_rect = $Node2D/ColorRect2/TextureRect
@onready var label = $Node2D/ColorRect2/Label
@onready var cost = $Node2D/upgrade/Node2D/ColorRect/Label
@onready var smoke = preload("res://scenes/bullet/spread_smoke.tscn")
@onready var marker_2d = $Marker2D
@onready var upgrade = $Node2D/upgrade
@onready var color_rect = $Node2D/ColorRect2
@onready var equip_text_p: PanelContainer = $Node2D/EquipTextP

var t_num: int = 0
var icon_num: int = 0
var coin_cost:int = 0

var player: Node

var cost_mult: float = 1.5

var rare_color: Array[Color] =[ Color(0.779, 0.795, 0.81), Color(0.464, 0.673, 0.832), Color(0.884, 0.764, 0.435), Color(0.985, 0.643, 0.909) ]

var on_touch: bool = false
var _tooltip: HoverTooltipBinding
var _current_tooltip: HoverTooltipBinding
var equip_text := ""
var equip_t := ""
var equip_t_2 := ""

func _ready():
	_tooltip = HoverTooltipBinding.bind(upgrade, _tooltip_content, func(): return player != null, func(): on_touch = false)
	_tooltip.touch_content = _combined_tooltip_content
	_current_tooltip = HoverTooltipBinding.bind(equip_text_p, _current_tooltip_content, func(): return player != null and t_num > 0)
	upgrade.mouse_entered.connect(mouse_in)
	upgrade.mouse_exited.connect(mouse_out)
	equip_text_p.mouse_entered.connect(text_show)
	equip_text_p.mouse_exited.connect(text_hide)
	upgrade.gui_input.connect(mouse_selected.bind(upgrade))
	equip_text_p.gui_input.connect(mouse_selected.bind(equip_text_p))
	GameEvents.get_player.connect(get_player)
	GameEvents.player_card_touch.connect(touch_out)
	texture_rect.texture = equip_card.icon[icon_num]
	cost_count()
	item_text_get()
	item_text_count()

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
	item_text_count()
	texture_rect.texture = equip_card.icon[icon_num]
	label.text = "T" + str(t_num)
	upgrade.mouse_filter = 0

func text_show():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")

func text_hide():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")

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

		if t_num >= 20:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return

		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			add_ability()

func mouse_selected(event: InputEvent, source: Control = null):

	if event is InputEventScreenTouch:
		if _tooltip.tapped(event, source):
			touch_button("touch", event.index)
		return

	if event.is_action_pressed("shoot"):

		if t_num >= 20:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return

		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			add_ability()

func cost_count():
	if is_test == false:
		coin_cost = round(float(pow(cost_mult,1)) + float(pow(cost_mult,1.5)) * float(pow(cost_mult,1.5)))
		cost.text = str(coin_cost)
	else:
		coin_cost = 0
		cost.text = "FREE"

func item_text_get():
	var text_1: String = ""
	var text_2: String = ""

	if t_num <= 6:
		color_rect.color = rare_color[0]
	elif t_num <= 12 and t_num > 6:
		color_rect.color = rare_color[1]
	elif t_num <= 18 and t_num > 12:
		color_rect.color = rare_color[2]
	else:
		color_rect.color = rare_color[3]

	if t_num < 20:
		if !equip_card.value_1.is_empty():
			if equip_card.value_1[t_num + 1] > 0:
				equip_text = "+" + str( int(equip_card.value_1[t_num + 1]) ) + tr(equip_card.value_1_name)
			else:
				equip_text = "-" + str( int(equip_card.value_1[t_num + 1]) ) + tr(equip_card.value_1_name)
			text_1 = equip_text + "  "
		if !equip_card.value_2.is_empty():
			if equip_card.value_2[t_num + 1] > 0:
				if equip_card.value_2[t_num + 1] < 1:
					equip_text = text_1 + "+" + str( int(equip_card.value_2[t_num + 1] * 100) ) + "%" + tr(equip_card.value_2_name)
				else:
					if equip_card.value_2_name == "player_critical":
						equip_text = text_1 + "+" + str( int(equip_card.value_2[t_num + 1]) ) + "%" + tr(equip_card.value_2_name)
					else:
						equip_text = text_1 + "+" + str( int(equip_card.value_2[t_num + 1]) ) + tr(equip_card.value_2_name)
			elif equip_card.value_2[t_num + 1] < 0:
				equip_text = text_1 + str( int(equip_card.value_2[t_num + 1] * 100) ) + "%" + tr(equip_card.value_2_name)
			text_2 = equip_text + "  "
		if !equip_card.value_3.is_empty():
			if equip_card.value_3[t_num + 1] > 0:
				if equip_card.value_3[t_num + 1] < 1:
					if equip_card.value_3_name == "player_damage_taken":
						equip_text = text_2 + "-" + str( int(equip_card.value_3[t_num + 1] * 100) ) + "%" + tr(equip_card.value_3_name)
					elif equip_card.value_3_name == "player_reload_speed":
						equip_text = text_2 + "+" + str(  int((1 - equip_card.value_3[t_num + 1]) * 100) ) + "%" + tr(equip_card.value_3_name)
					elif equip_card.value_3_name == "player_coin_refund":
						equip_text = text_2 + "+" + str( int(equip_card.value_3[t_num + 1] * 100) ) + "%" + tr(equip_card.value_3_name)
				else:
					if equip_card.value_3_name == "player_damage_taken":
						equip_text = text_2 + "-" + str( int(equip_card.value_3[t_num + 1]) ) + "%" + tr(equip_card.value_3_name)
					else:
						equip_text = text_2 + "+" + str( int(equip_card.value_3[t_num + 1]) ) + tr(equip_card.value_3_name)
			elif equip_card.value_3[t_num + 1] < 0:
				equip_text = text_2 + str( roundi(equip_card.value_3[t_num + 1] * 100) ) + "%" + tr(equip_card.value_3_name)

	else:
		equip_text = "已到达升级上限"

func item_text_count():

	equip_t = label.text

	var text_1_c: String = ""
	var text_2_c: String = ""

	var value_1 = 0
	var value_2 = 0
	var value_3 = 0

	if !equip_card.value_1.is_empty():
		for i in (t_num + 1):
			value_1 += equip_card.value_1[i]

	if !equip_card.value_2.is_empty():
		for i in (t_num + 1):
			value_2 += equip_card.value_2[i]

	if !equip_card.value_3.is_empty():
		if equip_card.value_3_name == "player_reload_speed":
			for i in (t_num + 1):
				value_3 += (1 - equip_card.value_3[i])
		else:
			for i in (t_num + 1):
				value_3 += equip_card.value_3[i]

	if !equip_card.value_1.is_empty():
		if value_1 >= 0:
			equip_t_2 = "+" + str( int(value_1) ) + tr(equip_card.value_1_name)
		else:
			equip_t_2 = "-" + str( int(value_1) ) + tr(equip_card.value_1_name)
		text_1_c = equip_t_2 + "  "
	if !equip_card.value_2.is_empty():
		if value_2 >= 0:
			if value_2 < 1 or equip_card.value_2_name == "player_pickup_range":
				if equip_card.value_2_name != "player_armor":
					equip_t_2 = text_1_c + "+" + str( int(value_2 * 100) ) + "%" + tr(equip_card.value_2_name)
			else:
				if equip_card.value_2_name == "player_critical":
					equip_t_2 = text_1_c + "+" + str( int(value_2) ) + "%" + tr(equip_card.value_2_name)
				else:
					equip_t_2 = text_1_c + "+" + str( int(value_2) ) + tr(equip_card.value_2_name)
		elif value_2 < 0:
			equip_t_2 = text_1_c + str( int(value_2 * 100) ) + "%" + tr(equip_card.value_2_name)
		text_2_c = equip_t_2 + "  "
	if !equip_card.value_3.is_empty():
		if value_3 >= 0:
			if value_3 < 1 or equip_card.value_3_name == "player_pickup_range":
				if equip_card.value_3_name == "player_damage_daken":
					equip_t_2 = text_2_c + "-" + str( int(value_3 * 100) ) + "%" + tr(equip_card.value_3_name)
				elif equip_card.value_3_name == "player_reload_speed":
					equip_t_2 = text_2_c + "+" + str( round(int(value_3 * 100)) ) + "%" + tr(equip_card.value_3_name)
				elif equip_card.value_3_name == "player_coin_refund":
					equip_t_2 = text_2_c + "+" + str( round(int(value_3 * 100)) ) + "%" + tr(equip_card.value_3_name)
			elif equip_card.value_3_name == "player_reload_speed":
					equip_t_2 = text_2_c + "+" + str( round(int(value_3 * 100)) ) + "%" + tr(equip_card.value_3_name)
			else:
				if equip_card.value_3_name == "player_critical":
					equip_t_2 = text_2_c + "+" + str( int(value_3) ) + "%" + tr(equip_card.value_3_name)
				else:
					equip_t_2 = text_2_c + "+" + str( int(value_3) ) + tr(equip_card.value_3_name)
		elif value_3 < 0:
			equip_t_2 = text_2_c + str( int(value_3 * 100) ) + "%" + tr(equip_card.value_3_name)

func smoke_anim():
	var ins = smoke.instantiate()
	ins.position = marker_2d.position
	add_child(ins)

func item_upgrade():
	if t_num >= 20:
		return

	t_num += 1
	cost_mult += 0.3
	cost_count()
	item_text_get()
	var v = round(int(float(t_num + 1) / float(2)))
	if icon_num != v:
		icon_num = v
		smoke_anim()
		texture_rect.texture = equip_card.icon[icon_num]
		label.text = "T" + str(v)
	item_text_count()
	if t_num >= 20:
		upgrade.mouse_filter = 2
		cost.text = "MAX"

func add_ability():

	if !equip_card.value_1.is_empty():
		var first = PlayerData.get( equip_card.value_1_id )
		PlayerData.set( equip_card.value_1_id , first + equip_card.value_1[t_num] )
	if !equip_card.value_2.is_empty():
		var first = PlayerData.get( equip_card.value_2_id )
		PlayerData.set( equip_card.value_2_id , first + equip_card.value_2[t_num] )
	if !equip_card.value_3.is_empty():
		if equip_card.value_3_name == "player_reload_speed":
			var first = PlayerData.get( equip_card.value_3_id )
			PlayerData.set( equip_card.value_3_id , first * equip_card.value_3[t_num] )
		else:
			var first = PlayerData.get( equip_card.value_3_id )
			PlayerData.set( equip_card.value_3_id , first + equip_card.value_3[t_num] )

	PlayerData.update_player_ability()

func preview_from_navigation() -> void:
	GameEvents.emit_player_card_touch()
	on_touch = true
	mouse_in()
	_tooltip.preview("focus")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and player != null:
		item_text_get()
		item_text_count()

func _tooltip_content() -> Array:
	return [{"text": equip_text, "translated": true}]

func _current_tooltip_content() -> Array:
	return [{"text": equip_t, "role": "title", "translated": true}, {"text": equip_t_2, "translated": true}]

func _combined_tooltip_content() -> Array:
	return _current_tooltip_content() + _tooltip_content()
