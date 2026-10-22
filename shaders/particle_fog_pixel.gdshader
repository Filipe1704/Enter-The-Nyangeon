shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D noise_tex : repeat_enable, filter_nearest;
uniform float noise_scale = 2.5;
uniform vec2 noise_scroll = vec2(0.03, -0.02);
uniform float uv_warp = 0.10;
uniform float dissolve = 0.42;
uniform float dither_strength = 0.5;
uniform int alpha_levels = 4;
instance uniform float seed_offset = 0.0;
instance uniform float reveal = 1.0;

const float BAYER[16] = float[16](
	0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

float bayer4(vec2 pixel) {
	ivec2 p = ivec2(mod(pixel, 4.0));
	return BAYER[p.x + p.y * 4] / 16.0;
}

void fragment() {
	vec2 seed = vec2(seed_offset, seed_offset * 0.618);
	vec2 nuv = UV * noise_scale + noise_scroll * TIME + seed;
	vec2 n = texture(noise_tex, nuv).rg;
	vec4 tex = texture(TEXTURE, UV + (n - 0.5) * uv_warp);

	float mask = texture(noise_tex, UV * noise_scale * 0.5 + n * 0.35 + seed).r;
	float cut = step(dissolve, mask);

	float levels = float(max(alpha_levels, 1));
	float radius = length(UV - 0.5) * 2.0;
	float falloff = 1.0 - smoothstep(0.55, 1.0, radius + (n.r - 0.5) * 0.4);
	float alpha = tex.a * tex.r * COLOR.a * cut * falloff;
	alpha += (bayer4(FRAGCOORD.xy) - 0.5) * dither_strength / levels;
	alpha = clamp(alpha, 0.0, 1.0);
	alpha = floor(alpha * levels + 0.5) / levels;
	alpha *= reveal;

	COLOR = vec4(tex.rgb * COLOR.rgb, alpha);
}
