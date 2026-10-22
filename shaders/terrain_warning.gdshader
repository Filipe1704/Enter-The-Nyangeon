shader_type canvas_item;
render_mode blend_add;

uniform vec4 tint : source_color = vec4(0.9, 0.35, 1.0, 1.0);
uniform float pulse_speed = 6.283185;
uniform float alpha_min = 0.3;
uniform float alpha_max = 0.8;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float pulse = mix(alpha_min, alpha_max, 0.5 + 0.5 * sin(TIME * pulse_speed));
	COLOR = vec4(tint.rgb * (0.75 + 0.5 * pulse), tex.a * pulse * tint.a);
}
