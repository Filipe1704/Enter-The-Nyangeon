class_name BossHPSlot
extends Control

# 可编辑槽位：视觉节点全部在 boss_hp_slot.tscn 中，脚本只绑定数据。
# SingleLayout / MultiLayout 由 BossHPGroup 切换显隐；脚本不改位置和尺寸。
const NAME_MAX_FONT := 15
const NAME_MIN_FONT := 9

@export var auto_fit_name: bool = true
@export var hp_gradient_white: Gradient
@export var hp_gradient_red: Gradient

@onready var _single_layout: Control = $SingleLayout
@onready var _multi_layout: Control = $MultiLayout
@onready var _single_name: Label = $SingleLayout/BossName
@onready var _multi_name: Label = $MultiLayout/BossName
@onready var _single_bar_area: Control = $SingleLayout/BarArea
@onready var _multi_bar_area: Control = $MultiLayout/BarArea
@onready var _single_hp2: TextureProgressBar = $SingleLayout/BarArea/HP2
@onready var _multi_hp2: TextureProgressBar = $MultiLayout/BarArea/HP2
@onready var _single_hp: TextureProgressBar = $SingleLayout/BarArea/HP
@onready var _multi_hp: TextureProgressBar = $MultiLayout/BarArea/HP
@onready var _single_value: Label = $SingleLayout/BarArea/HPValue
@onready var _multi_value: Label = $MultiLayout/BarArea/HPValue

var boss: BossEnemy = null
var single_mode: bool = true

var _name_labels: Array[Label] = []
var _bar_areas: Array[Control] = []
var _hp2_bars: Array[TextureProgressBar] = []
var _hp_bars: Array[TextureProgressBar] = []
var _value_labels: Array[Label] = []
var _hp_tweens: Array[Tween] = []
var _hp2_tweens: Array[Tween] = []
var _fit_queued: bool = false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_labels = [_single_name, _multi_name]
	_bar_areas = [_single_bar_area, _multi_bar_area]
	_hp2_bars = [_single_hp2, _multi_hp2]
	_hp_bars = [_single_hp, _multi_hp]
	_value_labels = [_single_value, _multi_value]
	single_mode = _single_layout.visible
	_apply_visibility()
	for label in _name_labels:
		label.minimum_size_changed.connect(_queue_fit)
	for area in _bar_areas:
		area.resized.connect(_refresh_bar_textures)
	resized.connect(_refresh_bar_textures)
	_refresh_bar_textures()
	_queue_fit()

func bind_boss(p_boss: BossEnemy) -> void:
	if boss != null and boss.stats != null and boss.stats.hp_changed.is_connected(_update_hp):
		boss.stats.hp_changed.disconnect(_update_hp)
	boss = p_boss
	if boss == null:
		return
	if boss.stats != null and not boss.stats.hp_changed.is_connected(_update_hp):
		boss.stats.hp_changed.connect(_update_hp)
	var boss_name := boss.get_boss_name()
	_single_name.text = _decorate_name(boss_name)
	_multi_name.text = boss_name
	_single_name.tooltip_text = boss_name
	_multi_name.tooltip_text = boss_name
	_update_hp(true)
	_queue_fit()

func set_single_mode(value: bool) -> void:
	if single_mode == value:
		return
	single_mode = value
	_apply_visibility()
	_queue_fit()
	_refresh_bar_textures()

func _apply_visibility() -> void:
	if _single_layout != null:
		_single_layout.visible = single_mode
	if _multi_layout != null:
		_multi_layout.visible = not single_mode

func _update_hp(instant: bool = false) -> void:
	if boss == null or boss.stats == null:
		return
	var max_hp := maxi(1, boss.stats.max_hp)
	var ratio := clampf(float(boss.stats.hp) / float(max_hp), 0.0, 1.0)
	for label in _value_labels:
		label.text = "%d/%d" % [boss.stats.hp, boss.stats.max_hp]
	if instant:
		for bar in _hp_bars:
			bar.value = ratio
		for bar in _hp2_bars:
			bar.value = ratio
		return
	for tween in _hp_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	for tween in _hp2_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_hp_tweens.clear()
	_hp2_tweens.clear()
	for bar in _hp_bars:
		var tween := create_tween()
		tween.tween_property(bar, "value", ratio, 0.05)
		_hp_tweens.append(tween)
	for bar in _hp2_bars:
		var tween := create_tween()
		tween.tween_property(bar, "value", ratio, 0.3)
		_hp2_tweens.append(tween)

func _refresh_bar_textures() -> void:
	if _bar_areas.is_empty():
		return
	for i in _bar_areas.size():
		var area := _bar_areas[i]
		var w := maxi(1, int(area.size.x))
		var h := maxi(1, int(area.size.y))
		if i < _hp2_bars.size() and hp_gradient_white != null:
			var texture2 := GradientTexture2D.new()
			texture2.gradient = hp_gradient_white
			texture2.width = w
			texture2.height = h
			_hp2_bars[i].texture_progress = texture2
		if i < _hp_bars.size() and hp_gradient_red != null:
			var texture := GradientTexture2D.new()
			texture.gradient = hp_gradient_red
			texture.width = w
			texture.height = h
			texture.fill_to = Vector2(0, 1)
			_hp_bars[i].texture_progress = texture

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if boss != null:
			var boss_name := boss.get_boss_name()
			_single_name.text = _decorate_name(boss_name)
			_multi_name.text = boss_name
			_single_name.tooltip_text = boss_name
			_multi_name.tooltip_text = boss_name
		_queue_fit()

func _decorate_name(plain_name: String) -> String:
	var name := plain_name.strip_edges()
	if name.begins_with("-") and name.ends_with("-"):
		return name
	return "-%s-" % name

func _queue_fit() -> void:
	if not auto_fit_name or _fit_queued:
		return
	_fit_queued = true
	call_deferred("_fit_names")

func _fit_names() -> void:
	_fit_queued = false
	if not auto_fit_name:
		return
	for i in _name_labels.size():
		var label := _name_labels[i]
		if label == null or label.text == "":
			continue
		var available := maxf(24.0, label.size.x - 6.0)
		var font := label.get_theme_font("font")
		if font == null:
			continue
		var fitted := NAME_MIN_FONT
		for font_size in range(NAME_MAX_FONT, NAME_MIN_FONT - 1, -1):
			var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if width <= available:
				fitted = font_size
				break
		label.add_theme_font_size_override("font_size", fitted)
		var is_single := i == 0
		label.max_lines_visible = 1 if is_single else 2
		if is_single:
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
		else:
			label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if _has_cjk(label.text) else TextServer.AUTOWRAP_WORD_SMART

func _has_cjk(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 0x2E80 and c <= 0x9FFF) or (c >= 0xAC00 and c <= 0xD7AF) or (c >= 0xF900 and c <= 0xFAFF):
			return true
	return false
