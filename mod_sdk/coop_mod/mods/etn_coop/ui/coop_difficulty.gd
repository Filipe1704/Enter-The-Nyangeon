extends CanvasLayer

## 房主「难度选择」面板（全员就绪后弹出）。
## 复用本体 level_button（含关卡颜色/动画）与 gamemode_button（游戏模式），
## 关卡列表来自 CoopNet.get_level_catalog()（数据驱动，便于 Mod 扩展）。
## 选关后由 level_button 触发 GameEvents.change_scene → CoopNet 的 change_scene gate 统一开战。
## ESC = 房主放弃选择 → 全员取消就绪（CoopNet.cancel_select）。
## 静态布局在 coop_difficulty.tscn；本脚本按目录动态实例化关卡按钮。

signal level_is_selected
signal player_selected

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const LEVEL_BUTTON := preload("res://ui/level_button.tscn")
const DEFAULT_PLAYER_SCENE := "res://scenes/player/momoi/momoi.tscn"

@onready var _level_box: VBoxContainer = %LevelBox
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _mode_panel = $Control/GamemodeButton

var player: String = ""
# 与本体 ui/level_select.gd 对齐：ui/level_button.gd:_on_timer_timeout 会写这个属性。
# 缺声明时该赋值是运行时错误并中断回调 → 点难度后不转场、不进关卡（联机卡在难度界面）。
var transition_started: bool = false
var _open_level_button: Node


func _ready() -> void:
	var coop = CoopNetScript.instance
	if coop != null:
		if str(coop.local_player_scene_path) != "":
			player = str(coop.local_player_scene_path)
		else:
			player = DEFAULT_PLAYER_SCENE
	_populate_levels()
	level_is_selected.connect(_close_level_preview)
	# 激活关卡按钮（level_button 初始 mouse_filter=IGNORE，靠 player_selected → open_mouse）
	player_selected.emit()
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play("show_anim")


# 关闭时倒放进场动画（由 CoopFlow 调用，随后延时释放本层）
func play_hide() -> void:
	_close_level_preview()
	if _anim != null and _anim.has_animation("show_anim"):
		_anim.play_backwards("show_anim")


func _populate_levels() -> void:
	var coop = CoopNetScript.instance
	var catalog: Array = coop.get_level_catalog() if coop != null else []
	for entry in catalog:
		var lv = entry.get("level")
		if lv == null:
			continue
		var ins = LEVEL_BUTTON.instantiate()
		ins.level = lv
		ins.path = str(entry.get("scene_path", "res://scenes/main/main.tscn"))
		ins.level_select = self
		if ins.has_signal("previewed") and not ins.is_connected("previewed", _on_level_previewed):
			ins.connect("previewed", _on_level_previewed)
		_level_box.add_child(ins)


func _on_level_previewed(button: Node) -> void:
	if button == null or _mode_panel == null:
		return
	var level: Level = button.get("level")
	if level == null:
		return
	if _open_level_button != null and _open_level_button != button:
		if is_instance_valid(_open_level_button) and _open_level_button.has_method("close_preview"):
			_open_level_button.close_preview()
	_open_level_button = button
	if level.havoc_required:
		if not PlayerData.game_mode.has(GameMode.HAVOC_ID):
			_mode_panel.ensure_mode_selected(GameMode.HAVOC_ID, true, true)
	elif _mode_panel.is_havoc_auto_selected():
		_mode_panel.ensure_mode_selected(GameMode.HAVOC_ID, false, true)
	if PlayerData.game_mode.has(GameMode.HAVOC_ID):
		_mode_panel.set_enemy_mod_requirement(maxi(1, level.havoc_min_enemy_mods))
	else:
		_mode_panel.clear_enemy_mod_requirement()


func _close_level_preview() -> void:
	if _open_level_button != null and is_instance_valid(_open_level_button):
		if _open_level_button.has_method("close_preview"):
			_open_level_button.close_preview()
	_open_level_button = null


func prepare_level_selection(level: Level) -> bool:
	if level == null or _mode_panel == null:
		return true
	if not level.havoc_required and _mode_panel.is_havoc_auto_selected():
		_mode_panel.ensure_mode_selected(GameMode.HAVOC_ID, false, true)
	if level.havoc_required and not PlayerData.game_mode.has(GameMode.HAVOC_ID):
		_mode_panel.ensure_mode_selected(GameMode.HAVOC_ID, true, true)
	if not PlayerData.game_mode.has(GameMode.HAVOC_ID):
		if level.havoc_required:
			_mode_panel.play_enemy_mod_warning()
			SoundManager.play_sfx("UISounds2")
			return false
		_mode_panel.clear_enemy_mod_requirement()
		return true
	var min_mods := maxi(1, level.havoc_min_enemy_mods)
	_mode_panel.set_enemy_mod_requirement(min_mods)
	if _mode_panel.get_selected_enemy_mod_count() < min_mods:
		_mode_panel.play_enemy_mod_warning()
		SoundManager.play_sfx("UISounds2")
		return false
	_mode_panel.clear_enemy_mod_requirement()
	_mode_panel.confirm_havoc_auto_selection()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		var coop = CoopNetScript.instance
		if coop != null:
			coop.call("cancel_select")
		get_viewport().set_input_as_handled()
