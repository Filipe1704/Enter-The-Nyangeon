@tool
extends PanelContainer

@export var button_id: String
@export var text: String = "":
	set(value):
		text = value
		tooltip_text = value
		var label := get_node_or_null("Label") as Label
		if label != null:
			label.text = value
@onready var animation_player = $AnimationPlayer

var on_show: bool = false

func _ready():
	$Label.text = text
	tooltip_text = text
	resized.connect(_resize_highlight)
	_resize_highlight()
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(mouse_entered_anim)
	mouse_exited.connect(mouse_exitedd_anim)
	focus_entered.connect(mouse_entered_anim)
	focus_exited.connect(mouse_exitedd_anim)
	gui_input.connect(menu_button_press)

func _resize_highlight() -> void:
	# 只动画背景宽度；页签和文字始终留在容器分配的位置。
	$Node2D/ColorRect.size = size

func set_selected(selected: bool) -> void:
	if on_show == selected:
		return
	on_show = selected
	if selected:
		animation_player.play("selected")
	elif has_focus() or get_global_rect().has_point(get_global_mouse_position()):
		animation_player.play("on_select")
	else:
		animation_player.play("on_out")

func mouse_entered_anim():
	if on_show == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("on_select")

func mouse_exitedd_anim():
	if on_show == false and not has_focus():
		animation_player.play_backwards("on_select")

func menu_button_press(event: InputEvent):
	if mouse_filter == Control.MOUSE_FILTER_IGNORE or event.is_echo():
		return
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_menu_button(button_id)
		set_selected(true)
	
	if event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept"):
		accept_event()
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_menu_button(button_id)
		set_selected(true)
