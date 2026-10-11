extends CanvasLayer

signal level_is_selected
signal player_selected

@onready var animation_player = $AnimationPlayer
@onready var level_box: VBoxContainer = $Node2D2/Node2D/Node2D/VBoxContainer

const LEVEL_BUTTON := preload("res://ui/level_button.tscn")

var player: String
var transition_started: bool = false

func _ready():
	GameEvents.player_card_id.connect(get_player_id)
	GameEvents.level_select_in.connect(level_menu_in)
	_inject_mod_levels()

func _inject_mod_levels() -> void:
	for lv in ModManager.get_content("levels"):
		if lv == null:
			continue
		var ins = LEVEL_BUTTON.instantiate()
		ins.level = lv
		ins.level_select = self
		level_box.add_child(ins)

func _unhandled_input(event):
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if transition_started:
			return
		for button in level_box.get_children():
			button.cancel_selection()
		SoundManager.play_sfx("UISounds2")
		GameEvents.emit_level_select_out()
		animation_player.play("RESET")

func get_player_id(player_id: String):
	player = player_id

func emit_player_selected():
	player_selected.emit()

func level_menu_in():
	transition_started = false
	SoundManager.play_sfx("UISounds1")
	animation_player.play("select_in")
	await animation_player.animation_finished
	await get_tree().process_frame
	if visible and not transition_started and level_box.get_child_count() > 0:
		var first_button: Control = level_box.get_child(0)
		if first_button.focus_mode != Control.FOCUS_NONE:
			first_button.grab_focus()
