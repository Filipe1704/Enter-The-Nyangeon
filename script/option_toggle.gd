extends PanelContainer

# 像素风格开关（复刻 game_option 的 FullScreen/Shake/VSync 开关视觉）。
# 供设置页与 MOD 列表行复用；自身处理 hover / 焦点 / 点击 / 触屏 / 确认键。

signal toggled(on: bool)

@export var track_color: Color = Color(0.0784314, 0.0784314, 0.0784314, 1)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var track: ColorRect = $ColorRect

var on: bool = false
var _hovered: bool = false
var _focused: bool = false


func _ready() -> void:
	track.color = track_color
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	focus_entered.connect(_on_focus_in)
	focus_exited.connect(_on_focus_out)
	gui_input.connect(_on_gui_input)
	if on:
		animation_player.play("selected")
		animation_player.seek(animation_player.current_animation_length, true)


func set_on(value: bool, animate: bool = true) -> void:
	on = value
	var anim := "selected" if on else "full_out"
	animation_player.play(anim)
	if not animate:
		animation_player.seek(animation_player.current_animation_length, true)


func toggle() -> void:
	_apply(not on)


func _apply(value: bool) -> void:
	on = value
	animation_player.play("selected" if on else "full_out")
	toggled.emit(on)


func _refresh_visual() -> void:
	if _hovered or _focused:
		animation_player.play("selected_out" if on else "full_on")
	else:
		animation_player.play("selected" if on else "full_out")


func _on_hover() -> void:
	_hovered = true
	_refresh_visual()


func _on_unhover() -> void:
	_hovered = false
	_refresh_visual()


func _on_focus_in() -> void:
	_focused = true
	_refresh_visual()


func _on_focus_out() -> void:
	_focused = false
	_refresh_visual()


func _on_gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		pressed = true
	if not pressed:
		return
	accept_event()
	_apply(not on)
