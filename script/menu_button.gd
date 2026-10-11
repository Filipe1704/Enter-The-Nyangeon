extends PanelContainer

@export var button_id: String

var on_touch: bool = false

@onready var animation_player = $AnimationPlayer

func _ready():
	gui_input.connect(menu_button_press)
	focus_entered.connect(mouse_entered_anim)
	focus_exited.connect(mouse_exitedd_anim)
	GameEvents.player_card_touch.connect(touch_out)

func mouse_entered_anim():
	SoundManager.play_sfx("ButtonSounds2")
	animation_player.play("on_select")

func mouse_exitedd_anim():
	if has_focus():
		return
	on_touch = false
	animation_player.play_backwards("on_select")

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		if not has_focus():
			animation_player.play_backwards("on_select")

func menu_button_press(event: InputEvent):
	if mouse_filter == Control.MOUSE_FILTER_IGNORE or event.is_echo():
		return
	# 高亮只由焦点驱动；真实鼠标位移才接管键盘选择，静止指针不抢焦点。
	if event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.relative != Vector2.ZERO and focus_mode != Control.FOCUS_NONE:
			grab_focus()
		return
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			grab_focus()
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			if not has_focus() or mouse_filter == Control.MOUSE_FILTER_IGNORE:
				return
			on_touch = true
		else:
			GameEvents.emit_check_data()
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.play_sfx("UISounds1")
			GameEvents.emit_menu_button(button_id)
	
	if event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept"):
		accept_event()
		GameEvents.emit_check_data()
		SoundManager.play_sfx("ButtonSounds")
		SoundManager.play_sfx("UISounds1")
		GameEvents.emit_menu_button(button_id)
