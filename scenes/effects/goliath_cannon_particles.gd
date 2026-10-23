class_name GoliathCannonParticles
extends GPUParticles2D

func play_at(radius: float) -> void:
	var material := process_material as ParticleProcessMaterial
	if material != null:
		var outer := maxf(12.0, radius * 0.9)
		material.emission_ring_radius = outer
		material.emission_ring_inner_radius = maxf(6.0, outer * 0.65)
	emitting = true
	restart()
