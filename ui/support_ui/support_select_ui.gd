extends Node2D

signal test_menu_changed
signal cards_changed

@export var support_card: PackedScene
@export var null_card: SupportCard
@export var test_d: Dictionary
@export var test_menu: bool = false

@onready var support_box: VBoxContainer = %support_box
@onready var ui_anim: AnimationPlayer = $ui_anim
@onready var card_anim: AnimationPlayer = $card_anim
@onready var main_card: PanelContainer = $main_card
@onready var main_name: Label = %MainName
@onready var sprite_2d: Sprite2D = $main_card/Sprite2D
@onready var margin_container: MarginContainer = $MarginContainer

var now_support: SupportCard
var on_select: bool = false
var list_open := false
var _keyboard_enabled := false
var _input_open := true
var _opening_sequence: int = 0

func _ready() -> void:
	main_card.mouse_entered.connect(mouse_in)
	main_card.mouse_exited.connect(mouse_out)
	margin_container.mouse_entered.connect(card_on_select)
	margin_container.mouse_exited.connect(card_out_select)
	GameEvents.support_card_select.connect(get_support_card)
	GameEvents.level_select_in.connect(check_data)
	if test_menu:
		check_data()

func has_keyboard_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused)

func set_interactive(enabled: bool) -> void:
	_keyboard_enabled = enabled
	_input_open = enabled
	main_card.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	main_card.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled:
		close_list(false)

func open_list(focus_items: bool = false) -> void:
	if not _input_open:
		return
	if not list_open:
		list_open = true
		_opening_sequence += 1
		add_cards()
		ui_anim.play("select_anim")
		SoundManager.play_sfx("ButtonSounds2")
	if focus_items:
		var sequence := _opening_sequence
		if ui_anim.is_playing():
			await ui_anim.animation_finished
		await get_tree().process_frame
		if not list_open or not _keyboard_enabled or sequence != _opening_sequence or not is_visible_in_tree():
			return
		var cards := support_box.get_children()
		if not cards.is_empty():
			var target: Control = cards[0]
			for card in cards:
				if now_support != null and card.shop_card.support_id == now_support.support_id:
					target = card
			target.grab_focus()
			margin_container.get_node("ScrollContainer").ensure_control_visible(target)

func close_list(restore_focus: bool = true) -> void:
	_opening_sequence += 1
	list_open = false
	on_select = false
	support_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	if restore_focus and _keyboard_enabled:
		main_card.grab_focus()
	ui_anim.play("RESET")

func check_data():
	if test_menu == false:
		if SupportData.game_support == null:
			now_support = null_card
		else:
			now_support = SupportData.game_support
			if !SupportData.support_data.has(now_support.support_id):
				now_support = null_card
			
		SupportData.get_card(now_support)
		if SupportData.game_support == null:
			SupportData.game_support = now_support
		update_card()
	else:
		now_support = null_card
		SupportData.get_card(now_support)
		update_card()

func get_support_card(support_card: SupportCard):
	if self.visible == false or not _input_open:
		return
	
	if support_card.support_id == "null":
		if test_menu == true:
			test_menu_changed.emit()
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	
	if SupportData.support_data.has(support_card.support_id) and test_menu == false:
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	
	if SupportData.support_pool.has(support_card) and test_menu == true:
		test_menu_changed.emit()
		now_support = support_card
		SupportData.game_support = now_support
		SupportData.get_card(now_support)
		Game.save_playerdata()
		if now_support != null:
			change_card()
	if _keyboard_enabled and has_keyboard_focus():
		close_list()
	

func card_on_select():
	on_select = true

func card_out_select():
	on_select = false

func mouse_in():
	if on_select == false:
		open_list()

func mouse_out():
	await get_tree().create_timer(0.1).timeout
	if on_select == false and not has_keyboard_focus():
		close_list(false)

func update_card():
	sprite_2d.texture = LazyTexture.load_uncached(now_support.character_sprite_path)
	main_name.text = now_support.support_name2

func change_card():
	card_anim.play("change_card")
	await card_anim.animation_finished
	update_card()
	card_anim.play_backwards("change_card")

func add_null_card():
	var ins = support_card.instantiate()
	ins.shop_card = null_card
	support_box.add_child(ins)
	ins.reveal()

func clear_box():
	var cards = support_box.get_children()
	if !cards.is_empty():
		for i in cards.size():
			cards[i].queue_free()

func add_cards():
	clear_box()
	add_null_card()
	if !SupportData.support_data.is_empty() and test_menu == false:
		var group = SupportData.support_data.values()
		for i in group.size():
			var ins = support_card.instantiate()
			ins.shop_card = group[i]["resource"]
			support_box.add_child(ins)
			ins.reveal()
	if !SupportData.support_pool.is_empty() and test_menu == true:
		for i in SupportData.support_pool.size():
			var ins = support_card.instantiate()
			ins.shop_card = SupportData.support_pool[i]
			support_box.add_child(ins)
			ins.reveal()
	support_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if _keyboard_enabled else Control.FOCUS_BEHAVIOR_DISABLED
	for card in support_box.get_children():
		if not card.is_queued_for_deletion():
			card.focus_mode = Control.FOCUS_ALL if _keyboard_enabled else Control.FOCUS_NONE
	cards_changed.emit()
	

func _on_main_card_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		open_list()
	elif event is InputEventMouseMotion and _keyboard_enabled and event.relative != Vector2.ZERO and event.device != InputEvent.DEVICE_ID_EMULATION:
		main_card.grab_focus()
	elif event.is_action_pressed("ui_accept") and _keyboard_enabled:
		main_card.accept_event()
		if not event.is_echo():
			open_list(true)
