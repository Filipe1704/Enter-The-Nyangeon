extends PanelContainer

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

func _ready():
	mouse_entered.connect(mouse_in)
	mouse_exited.connect(mouse_out)
	gui_input.connect(level_selected)
	focus_entered.connect(mouse_in)
	focus_exited.connect(mouse_out)
	
	level_select.level_is_selected.connect(close_mouse)
	level_select.player_selected.connect(open_mouse)
	
	GameEvents.player_card_touch.connect(touch_out)
	
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	animation_player.play("mouse_out")

func mouse_in():
	if on_selected == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("mouse_in")

func mouse_out():
	if on_selected == false:
		animation_player.play("mouse_out")

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_selected == false and on_touch == true:
		on_touch = false
		animation_player.play("mouse_out")


func level_selected(event: InputEvent):
	if on_selected or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	if event as InputEventScreenTouch and event.pressed:
		if on_selected == false and on_touch == false:
			var selection_id := _selection_id
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			if selection_id != _selection_id:
				return
			on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("mouse_in")
		else:
			SoundManager.play_sfx("ButtonSounds")
			on_selected = true
			level_select.level_is_selected.emit()
			animation_player.play("selected")
			
			PlayerData.level_id = level.level_id
			PlayerData.level_num = level.level_num
			PlayerData.level_hp = level.level_hp
			PlayerData.level_damage = level.level_damage
			PlayerData.level_score_mult = level.level_score_mult
			PlayerData.level_reward = level.level_reward
			
			timer.start()
	
	if on_selected == false and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		accept_event()
		SoundManager.play_sfx("ButtonSounds")
		on_selected = true
		level_select.level_is_selected.emit()
		animation_player.play("selected")
		
		PlayerData.level_id = level.level_id
		PlayerData.level_num = level.level_num
		PlayerData.level_hp = level.level_hp
		PlayerData.level_damage = level.level_damage
		PlayerData.level_score_mult = level.level_score_mult
		PlayerData.level_reward = level.level_reward
		
		timer.start()

func _on_timer_timeout() -> void:
	if not on_selected or not level_select.visible:
		return
	level_select.transition_started = true
	SoundManager.bgm_fade_out()
	Transition.play_left_start()
	await Transition.left_end_start
	GameEvents.change_scene(path,level_select.player)
