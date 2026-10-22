class_name FogSettings
extends Resource

@export var texture: Texture2D
@export var h_frames: int = 12
@export var v_frames: int = 1

@export var color: Color = Color(0.5, 0.62, 0.55, 0.35)
@export var amount: int = 6
@export var lifetime: float = 5.0
@export var preprocess: float = 2.0

@export var scale_min: float = 2.0
@export var scale_max: float = 4.0
@export var rise_speed: Vector2 = Vector2(0.0, -8.0)
@export var drift_speed: Vector2 = Vector2(6.0, 0.0)
@export var turbulence: float = 10.0
@export var spread: float = 180.0

@export var alpha_min: float = 0.15
@export var alpha_max: float = 0.35

@export_group("Pixel Style")
@export var size_min_px: float = 0.0
@export var size_max_px: float = 0.0
@export var fog_material: ShaderMaterial
@export var alpha_levels: int = 4
@export var dither_strength: float = 0.5
@export var uv_warp: float = 0.10
@export var z_index: int = 0
@export var show_behind_parent: bool = false

@export_group("Transition")
@export var release_time: float = 0.6
@export var dissipate_time: float = 2.0
