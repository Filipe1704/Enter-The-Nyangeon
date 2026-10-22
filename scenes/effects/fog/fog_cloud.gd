class_name FogCloud
extends GPUParticles2D

var _settings: FogSettings
var _amount_scale := 1.0
var _alpha_max := 0.35
var _release_time := 0.0
var _dissipate_time := 2.0
var _reveal := 1.0
var _use_reveal := false
var _fade_tween: Tween

func configure(settings: FogSettings, bounds: Rect2, amount_scale: float = 1.0, alpha_scale: float = 1.0) -> void:
	_settings = settings
	_amount_scale = maxf(0.05, amount_scale)
	if settings == null:
		return
	_release_time = maxf(0.0, settings.release_time)
	_dissipate_time = maxf(0.2, settings.dissipate_time)
	_use_reveal = settings.fog_material != null
	var alpha_lo := minf(settings.alpha_min, settings.alpha_max)
	_alpha_max = randf_range(alpha_lo, maxf(alpha_lo, settings.alpha_max)) * clampf(alpha_scale, 0.0, 1.0)
	texture = settings.texture
	local_coords = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = settings.z_index
	show_behind_parent = settings.show_behind_parent
	lifetime = maxf(0.1, settings.lifetime)
	preprocess = maxf(0.0, settings.preprocess)
	var density_divisor := sqrt(_amount_scale)
	amount = maxi(1, int(round(float(settings.amount) * density_divisor)))
	self.process_material = _make_process_material(settings, bounds, density_divisor)
	if settings.fog_material != null:
		_apply_pixel_material(settings)
	else:
		_apply_canvas_material(settings)

func _make_process_material(settings: FogSettings, bounds: Rect2, density_divisor: float) -> ParticleProcessMaterial:
	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var size := bounds.size
	particle_material.emission_box_extents = Vector3(maxf(8.0, size.x * 0.5), maxf(8.0, size.y * 0.5), 1.0)
	particle_material.direction = Vector3(settings.rise_speed.x, settings.rise_speed.y, 0.0)
	particle_material.spread = settings.spread
	particle_material.initial_velocity_min = 4.0
	particle_material.initial_velocity_max = 8.0
	particle_material.gravity = Vector3(settings.drift_speed.x, 0.0, 0.0)
	particle_material.scale_min = settings.scale_min
	particle_material.scale_max = settings.scale_max
	if settings.size_min_px > 0.0:
		var frame_px := _frame_pixel_size(settings)
		var size_divisor := maxf(1.0, density_divisor)
		particle_material.scale_min = settings.size_min_px / (frame_px * size_divisor)
		particle_material.scale_max = maxf(settings.size_min_px, settings.size_max_px) / (frame_px * size_divisor)
	particle_material.turbulence_noise_strength = settings.turbulence
	particle_material.color = Color(settings.color.r, settings.color.g, settings.color.b, _alpha_max)
	particle_material.color_ramp = _make_color_ramp()
	particle_material.anim_speed_min = 0.4
	particle_material.anim_speed_max = 0.9
	return particle_material

func _frame_pixel_size(settings: FogSettings) -> float:
	if settings.texture == null:
		return 1.0
	var base := maxf(1.0, settings.texture.get_size().x)
	if settings.fog_material != null:
		return base
	return maxf(1.0, base / maxf(1.0, float(settings.h_frames)))

func _apply_canvas_material(settings: FogSettings) -> void:
	var canvas_material := CanvasItemMaterial.new()
	canvas_material.particles_animation = true
	canvas_material.particles_anim_h_frames = maxi(1, settings.h_frames)
	canvas_material.particles_anim_v_frames = maxi(1, settings.v_frames)
	canvas_material.particles_anim_loop = true
	material = canvas_material

func _apply_pixel_material(settings: FogSettings) -> void:
	var shader_material := settings.fog_material
	shader_material.set_shader_parameter("alpha_levels", settings.alpha_levels)
	shader_material.set_shader_parameter("dither_strength", settings.dither_strength)
	shader_material.set_shader_parameter("uv_warp", settings.uv_warp)
	material = shader_material
	set_instance_shader_parameter("seed_offset", randf() * 10.0)

func start() -> void:
	_kill_fade_tween()
	emitting = true
	restart()
	if _release_time <= 0.0:
		return
	var delay := randf_range(0.0, 0.12)
	_fade_tween = create_tween()
	if _use_reveal:
		_set_reveal(0.0)
		_fade_tween.tween_method(_set_reveal, 0.0, 1.0, _release_time).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		modulate.a = 0.0
		_fade_tween.tween_property(self, "modulate:a", 1.0, _release_time).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func stop() -> void:
	_kill_fade_tween()
	emitting = false
	_fade_tween = create_tween()
	if _use_reveal:
		_fade_tween.tween_method(_set_reveal, _reveal, 0.0, _dissipate_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	else:
		_fade_tween.tween_property(self, "modulate:a", 0.0, _dissipate_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _set_reveal(value: float) -> void:
	_reveal = value
	set_instance_shader_parameter("reveal", value)

func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

func set_color(color: Color) -> void:
	var material_ref := self.process_material as ParticleProcessMaterial
	if material_ref != null:
		material_ref.color = Color(color.r, color.g, color.b, _alpha_max)

func _make_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.7),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = gradient
	return ramp_texture
