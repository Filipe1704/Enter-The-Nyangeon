extends Resource
class_name BossPhase

# 单次 Boss 战中的一个阶段。hp_ratio = 进入该阶段的血量比例（1.0 为满血）。
@export_range(0.0, 1.0) var hp_ratio: float = 0.5
@export var enter_anim_name: StringName = &""
@export var phase_anim_player_path: NodePath
@export var invulnerable_duration: float = 0.0
@export var buff: Buff
@export var buff_layer: int = 1
@export var buff_value: float = 1.0
@export var buff_duration: float = 0.0
@export var bgm: AudioStream
@export var camera_focus: bool = false
@export_multiline var description: String = ""
