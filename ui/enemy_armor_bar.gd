extends Control

const SEGMENT_COUNT := 8
const EDGE_PADDING := 1.0
const SEGMENT_GAP := 1.0

const BG_COLOR := Color("#07121c")
const BORDER_COLOR := Color("#8fb8d8")
const FILL_LOW := Color("#3f6f96")
const FILL_HIGH := Color("#f4fbff")
const HIGHLIGHT_COLOR := Color(1.0, 1.0, 1.0, 0.35)

var _strength := 0.0
var _tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(44.0, 6.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_strength(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if absf(next - _strength) < 0.001:
		return
	_strength = next
	queue_redraw()

func get_strength() -> float:
	return _strength

func appear() -> void:
	_kill_tween()
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.16)

func play_break() -> void:
	_kill_tween()
	visible = true
	modulate = Color(1.35, 1.5, 1.65, 1.0)
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color(1.35, 1.5, 1.65, 0.0), 0.22)
	_tween.tween_callback(_finish_break)

func _finish_break() -> void:
	_strength = 0.0
	queue_redraw()
	visible = false
	modulate = Color.WHITE

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if full.size.x <= 0.0 or full.size.y <= 0.0:
		return
	draw_rect(full, BG_COLOR, true)
	var inner := Rect2(
		Vector2(EDGE_PADDING, EDGE_PADDING),
		size - Vector2(EDGE_PADDING, EDGE_PADDING) * 2.0
	)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var usable_width := inner.size.x - SEGMENT_GAP * float(SEGMENT_COUNT - 1)
	if usable_width <= 0.0:
		return
	var segment_width := usable_width / float(SEGMENT_COUNT)
	var lit := _strength * float(SEGMENT_COUNT)
	for i in range(SEGMENT_COUNT):
		var coverage := clampf(lit - float(i), 0.0, 1.0)
		if coverage <= 0.0:
			continue
		var t := float(i) / float(SEGMENT_COUNT - 1)
		var color := FILL_LOW.lerp(FILL_HIGH, t)
		var x := inner.position.x + float(i) * (segment_width + SEGMENT_GAP)
		var rect := Rect2(Vector2(x, inner.position.y), Vector2(segment_width * coverage, inner.size.y))
		draw_rect(rect, color, true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), HIGHLIGHT_COLOR, true)
	draw_rect(full, BORDER_COLOR, false, 1.0)
