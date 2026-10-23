shader_type canvas_item;

uniform float pulse_speed = 3.927;
uniform float saturation_boost : hint_range(1.0, 2.5) = 1.4;
uniform float brightness_boost : hint_range(1.0, 2.0) = 1.3;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.5;
uniform vec4 glow_tint : source_color = vec4(1.0, 0.35, 0.8, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;
	float wave = 0.5 - 0.5 * cos(TIME * pulse_speed);

	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 vivid = mix(vec3(luma), col.rgb, mix(1.0, saturation_boost, wave));
	vivid *= mix(1.0, brightness_boost, wave);
	vivid += glow_tint.rgb * glow_strength * wave * col.a;

	COLOR = vec4(vivid, col.a);
}
