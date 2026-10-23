class_name OrbitalStrikeMarker
extends Node2D

@export var beam_height: float = 200
@export var countdown_seconds: float = 4.0
@export var title_text: String = "380MM ORBITAL BARRAGE"

@onready var beam: Line2D = $Beam
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Title
@onready var countdown_label: Label = $Panel/Countdown

var _remaining := 0.0
var _active := false
var _pulse_time := 0.0
var _intro_tween: Tween
var _exit_tween: Tween

func _ready() -> void:
	title_label.text = title_text
	beam.points = PackedVector2Array([Vector2.ZERO, Vector2(0.0, -beam_height)])
	panel.pivot_offset = Vector2(68.0, 24.0)
	_remaining = countdown_seconds
	_update_countdown()

func setup(seconds: float) -> void:
	countdown_seconds = maxf(0.1, seconds)
	_remaining = countdown_seconds
	_update_countdown()

func start_countdown() -> void:
	if _exit_tween != null:
		_exit_tween.kill()
	_active = true
	_remaining = countdown_seconds
	_update_countdown()
	_play_intro()

func stop_countdown() -> void:
	_active = false

func play_exit() -> void:
	_active = false
	if _intro_tween != null:
		_intro_tween.kill()
	if _exit_tween != null:
		_exit_tween.kill()
	_exit_tween = create_tween().set_parallel(true)
	_exit_tween.tween_property(panel, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.2)
	_exit_tween.tween_property(beam, "modulate:a", 0.0, 0.2)
	_exit_tween.chain().tween_callback(queue_free)

func _process(delta: float) -> void:
	if not _active:
		return
	_pulse_time += delta
	_remaining = maxf(0.0, _remaining - delta)
	_update_countdown()
	beam.modulate.a = 0.72 + 0.28 * sin(_pulse_time * 18.0)

func _play_intro() -> void:
	if _intro_tween != null:
		_intro_tween.kill()
	panel.scale = Vector2(0.05, 1.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.8)
	_intro_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(panel, "scale:x", 1.0, 0.2)
	_intro_tween.tween_property(panel, "modulate", Color(1.0, 0.35, 0.3, 0.8), 0.2)

func _update_countdown() -> void:
	countdown_label.text = "%0.3f" % _remaining
