extends PanelContainer

signal previewed(button: Node)

@export_file("*.tscn") var path: String

@export var level: Level
@export var level_select: Node

@onready var animation_player = $AnimationPlayer
@onready var level_color = %LevelColor
@onready var level_name = %LevelName
@onready var timer: Timer = $Timer

var on_selected: bool = false

var on_touch: bool = false
var _selection_id: int = 0
var _preview_open: bool = false

func _ready():
	mouse_entered.connect(mouse_in)
	gui_input.connect(level_selected)
	focus_entered.connect(mouse_in)
	
	level_select.level_is_selected.connect(close_mouse)
	level_select.player_selected.connect(open_mouse)
	
	get_level()

func get_level():
	level_color.color = level.level_color
	level_name.text = level.level_name
	level_name.set("theme_override_colors/font_color", level.level_name_color)

func open_mouse():
	cancel_selection()
	mouse_filter = 0
	focus_mode = Control.FOCUS_ALL

func close_mouse():
	mouse_filter = 2
	focus_mode = Control.FOCUS_NONE

func cancel_selection() -> void:
	_selection_id += 1
	timer.stop()
	on_selected = false
	on_touch = false
	_preview_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	# 初始化/取消直接恢复默认外观；mouse_out 从高亮首帧开始，会让所有按钮闪亮。
	animation_player.play("RESET")
	animation_player.advance(0)

# 预览是否允许展开：由难度页统一决定（入场动画完成前、已提交选择后为 false）。
# 入场窗口内按钮已可接鼠标，但父级的 previewed 会被忽略；若此时展开，_preview_open 会
# 永久停在 true 且不被记录为 _open_level_button，动画就卡在展开态。
# 没有该方法的父级（如联机难度面板）保持原有行为。
func _preview_allowed() -> bool:
	if level_select == null or not is_instance_valid(level_select):
		return true
	if not level_select.has_method("is_preview_ready"):
		return true
	return bool(level_select.call("is_preview_ready"))


func mouse_in():
	if on_selected:
		return
	if not _preview_allowed():
		return
	if mouse_filter != Control.MOUSE_FILTER_IGNORE and not has_focus():
		grab_focus()
		return
	open_preview()

func open_preview() -> void:
	if on_selected or _preview_open:
		return
	if not _preview_allowed():
		return
	_preview_open = true
	SoundManager.play_sfx("ButtonSounds2")
	animation_player.play("mouse_in")
	previewed.emit(self)

func close_preview() -> void:
	if on_selected or not _preview_open:
		return
	_preview_open = false
	on_touch = false
	animation_player.play("mouse_out")


func level_selected(event: InputEvent):
	if on_selected or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	if event is InputEventMouseMotion and event.relative != Vector2.ZERO and event.device != InputEvent.DEVICE_ID_EMULATION:
		grab_focus()
		return
	if event as InputEventScreenTouch and event.pressed:
		if on_selected == false and on_touch == false:
			var selection_id := _selection_id
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			if selection_id != _selection_id:
				return
			on_touch = true
			open_preview()
		else:
			if level_select.has_method("prepare_level_selection") and not level_select.prepare_level_selection(level):
				return
			SoundManager.play_sfx("ButtonSounds")
			on_selected = true
			level_select.level_is_selected.emit()
			animation_player.play("selected")
			
			_apply_level()
			
			timer.start()
	
	if on_selected == false and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		accept_event()
		if level_select.has_method("prepare_level_selection") and not level_select.prepare_level_selection(level):
			return
		SoundManager.play_sfx("ButtonSounds")
		on_selected = true
		level_select.level_is_selected.emit()
		animation_player.play("selected")
		
		_apply_level()
		
		timer.start()

func _apply_level() -> void:
	if level == null:
		return
	PlayerData.level_id = level.level_id
	PlayerData.level_num = level.level_num
	PlayerData.level_hp = level.level_hp
	PlayerData.level_damage = level.level_damage
	PlayerData.level_score_mult = level.level_score_mult
	PlayerData.level_reward = level.level_reward
	PlayerData.current_level = level

func _on_timer_timeout() -> void:
	if not on_selected or not level_select.visible:
		return
	level_select.transition_started = true
	SoundManager.bgm_fade_out()
	Transition.play_left_start()
	await Transition.left_end_start
	GameEvents.change_scene(path,level_select.player)
