shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec2 bar_size_px = vec2(44.0, 6.0);
uniform vec4 ash_color : source_color = vec4(0.055, 0.022, 0.014, 0.82);
uniform vec4 low_color : source_color = vec4(0.42, 0.025, 0.008, 1.0);
uniform vec4 mid_color : source_color = vec4(0.95, 0.16, 0.018, 1.0);
uniform vec4 high_color : source_color = vec4(1.0, 0.72, 0.12, 1.0);
uniform vec4 front_color : source_color = vec4(1.0, 0.97, 0.78, 1.0);
uniform float wave_amplitude : hint_range(0.0, 0.2) = 0.06;
uniform float wave_frequency : hint_range(0.0, 20.0) = 5.0;
uniform float wave_speed : hint_range(0.0, 20.0) = 7.0;
uniform float edge_softness_px : hint_range(0.1, 4.0) = 0.9;
uniform float corner_radius_px : hint_range(0.0, 4.0) = 1.5;
uniform float particle_amount : hint_range(0.0, 32.0) = 12.0;
uniform float particle_radius_px : hint_range(0.2, 4.0) = 1.25;
uniform float particle_lifetime : hint_range(0.1, 3.0) = 0.7;
uniform float particle_spacing : hint_range(0.01, 0.5) = 0.085;
uniform float particle_speed : hint_range(0.0, 0.5) = 0.17;
uniform float particle_rise : hint_range(0.0, 0.5) = 0.08;
uniform float particle_softness : hint_range(0.0, 2.0) = 0.55;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 size = max(bar_size_px, vec2(1.0));
	vec2 half_size = size * 0.5;
	float radius = min(corner_radius_px, min(size.x, size.y) * 0.5);
	float sd = rounded_box(UV * size - half_size, half_size, radius);
	float bar_mask = 1.0 - smoothstep(-edge_softness_px, edge_softness_px, sd);

	float wave = wave_amplitude * sin(UV.y * wave_frequency + TIME * wave_speed);
	float front = clamp(progress + wave, 0.0, 1.0);
	float soft_uv = edge_softness_px / max(size.x, 1.0);
	float fill = 1.0 - smoothstep(front - soft_uv, front + soft_uv, UV.x);
	float alive = smoothstep(0.0, 0.015, progress);
	fill *= alive;

	float heat = clamp(UV.x, 0.0, 1.0);
	vec3 fill_rgb = mix(low_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, heat));
	fill_rgb = mix(fill_rgb, high_color.rgb, smoothstep(0.55, 1.0, heat));

	float front_band = 1.0 - smoothstep(0.0, max(soft_uv * 2.0, 0.01), abs(UV.x - front));
	front_band *= alive;

	vec3 spark_rgb = vec3(0.0);
	float spark_sum = 0.0;
	float count = clamp(particle_amount, 0.0, 32.0);
	for (int i = 0; i < 32; i++) {
		if (float(i) >= count) {
			continue;
		}
		float fi = float(i);
		float seed = fi * 1.618 + 0.37;
		float r0 = hash11(seed);
		float r1 = hash11(seed + 1.7);
		float r2 = hash11(seed + 4.3);
		float life = fract(TIME / particle_lifetime + r0 * 7.0 + fi * particle_spacing);
		vec2 p = vec2(progress + life * particle_speed, mix(0.12, 0.88, r1) - life * particle_rise);
		vec2 d = (UV - p) * size;
		float particle_radius = particle_radius_px * mix(0.55, 1.35, r2) * (1.0 - 0.35 * life);
		float soft = max(particle_softness, 0.01);
		float mask = 1.0 - smoothstep(particle_radius - soft, particle_radius + soft, length(d));
		float fade = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.55, 1.0, life));
		float weight = mask * fade;
		spark_sum += weight;
		spark_rgb += mix(mid_color.rgb, front_color.rgb, 0.45 + 0.55 * r0) * weight;
	}
	spark_sum = clamp(spark_sum, 0.0, 1.0);
	spark_rgb = spark_sum > 0.0001 ? spark_rgb / max(spark_sum, 0.0001) : front_color.rgb;

	vec3 rgb = mix(ash_color.rgb, fill_rgb, fill);
	float alpha = mix(ash_color.a, 1.0, fill);
	rgb = mix(rgb, front_color.rgb, front_band * 0.9);
	alpha = max(alpha, front_band * 0.9);
	rgb = mix(rgb, spark_rgb, spark_sum * 0.9);
	alpha = max(alpha, spark_sum * 0.9);

	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0) * bar_mask);
}
