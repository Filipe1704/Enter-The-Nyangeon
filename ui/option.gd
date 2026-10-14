extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var option_button_box = $Node2D/option_button_box/VBoxContainer
@onready var menu_box = $menu_box


var on_option: bool = false

func _ready():
	GameEvents.menu_button.connect(menu_button_press)
	ExtensionHooks.notify_named("populate_option_pages", [menu_box, option_button_box])
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	for page in menu_box.get_children():
		page.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	$Node2D/return.focus_mode = Control.FOCUS_NONE

func on_option_selected():
	animation_player.play("option_in")
	on_option = true

func out_option_selected():
	button_close()
	SoundManager.play_sfx("UISounds2")
	animation_player.play("option_out")
	on_option = false

func button_open():
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	$Node2D/return.focus_mode = Control.FOCUS_ALL
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_STOP
		i.focus_mode = Control.FOCUS_ALL
	if not buttons.is_empty():
		buttons[0].grab_focus()

func button_close():
	menu_box.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	$Node2D/return.focus_mode = Control.FOCUS_NONE
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		i.focus_mode = Control.FOCUS_NONE

func menu_button_press(button_id: String):
	if not on_option:
		return

	var matched: bool = false
	var menus: Array = menu_box.get_children()

	for i in menus:
		if i.option_id == button_id:
			i.menu_show()
			matched = true

	if matched:
		botton_out_anim(button_id)

func botton_out_anim(button_id: String):

	var buttons: Array = option_button_box.get_children()

	for i in buttons:
		if i.button_id != button_id and i.on_show:
			i.on_show = false
			i.mouse_exitedd_anim()

	var menus: Array = menu_box.get_children()

	for i in menus:
		i.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if i.option_id == button_id else Control.FOCUS_BEHAVIOR_DISABLED
		if i.option_id != button_id:
			i.menu_hide()
