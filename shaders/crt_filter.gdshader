// CRT with luminance preservation - screen-space canvas_item variant.
// Adapted from "CRT with Luminance Preservation" V4 by Harrison Allen (CC0).
// https://godotshaders.com/shader/crt-with-luminance-preservation/
//
// 与参考实现（低分辨率 SubViewport + ViewportTexture）不同，本变体直接采样
// 根视口 backbuffer，并按 virtual_size（= 游戏 640x360 逻辑分辨率）建立虚拟
// 像素网格，使扫描线 / 荫罩与游戏像素 1:1 对齐。
// 项目开启 viewport/hdr_2d，屏幕纹理为线性色，故全程线性运算，不做 sRGB 转换。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// 虚拟像素网格，默认等于游戏逻辑分辨率（640x360）。
uniform vec2 virtual_size = vec2(640.0, 360.0);

/**
	Set the type of mask this CRT will have.
	Dots: emulates a typical PC CRT monitor.
	Grille: emulates an aperture grille. Good with higher curve values.
	Wide Grille: more suitable for 4k monitors.
	Soft Grille: very close to wide grille, but a little softer.
	Slot mask: this is the pattern found on most TVs.
	*/
uniform int mask_type : hint_enum(
	"Dots:1",
	"Aperture Grille:2",
	"Wide Grille:3",
	"Wide Soft Grille:4",
	"Slot Mask:5",
	"Null:0") = 1;

uniform float curve : hint_range(0.0, 0.5) = 0.0;
uniform float sharpness : hint_range(0.5, 1.0) = 0.6666666666666667;
uniform float color_offset : hint_range(-0.5, 0.5) = 0.0;
uniform float mask_brightness : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_brightness : hint_range(0.5, 1.0) = 1.0;
uniform float min_scanline_thickness : hint_range(0.25, 1.0) = 0.5;
uniform float aspect : hint_range(0.5, 1.0) = 0.5625;
uniform float wobble_strength : hint_range(0.0, 1.0) = 0.0;

varying flat float wobble;

void vertex() {
	wobble = cos(TIME * TAU * 15.0) * wobble_strength / 8192.0;
}

vec2 warp(vec2 uv, float _aspect, float _curve) {
	// Centralize coordinates
	uv -= 0.5;

	uv.x /= _aspect;

	// Squared distance from the middle
	float warping = dot(uv, uv) * _curve;

	// Compensate for shrinking
	warping -= _curve * 0.25;

	// Warp the coordinates
	uv /= 1.0 - warping;

	uv.x *= _aspect;

	// Decentralize the coordinates
	uv += 0.5;

	return uv;
}

// 采样虚拟像素 (vpix)，屏幕纹理为线性色。
vec3 fetch(vec2 vpix) {
	return texture(screen_tex, (vec2(floor(vpix)) + 0.5) / virtual_size).rgb;
}

// Get scanlines from coordinates (returns in linear color)
vec3 scanlines(vec2 uv) {
	// Set coordinates to match the virtual pixel grid
	uv *= virtual_size;

	// Vertical coordinate scanline samples
	int y = int(uv.y + 0.5) - 1;

	float x = floor(uv.x);

	// Horizontal coordinates for the texture samples
	float ax = x - 2.0;
	float bx = x - 1.0;
	float cx = x;
	float dx = x + 1.0;
	float ex = x + 2.0;

	// Sample the texture at various points
	vec3 upper_a = fetch(vec2(ax, float(y)));
	vec3 upper_b = fetch(vec2(bx, float(y)));
	vec3 upper_c = fetch(vec2(cx, float(y)));
	vec3 upper_d = fetch(vec2(dx, float(y)));
	vec3 upper_e = fetch(vec2(ex, float(y)));

	// Adjust the vertical coordinate for the lower scanline
	y += 1;

	// Sample the texture at various points
	vec3 lower_a = fetch(vec2(ax, float(y)));
	vec3 lower_b = fetch(vec2(bx, float(y)));
	vec3 lower_c = fetch(vec2(cx, float(y)));
	vec3 lower_d = fetch(vec2(dx, float(y)));
	vec3 lower_e = fetch(vec2(ex, float(y)));

	// The x coordinates of electron beam offsets
	vec3 beam = vec3(uv.x - 0.5);
	beam.r -= color_offset;
	beam.b += color_offset;

	// Calculate weights
	vec3 weight_a = smoothstep(1.0, 0.0, (beam - ax) * sharpness);
	vec3 weight_b = smoothstep(1.0, 0.0, (beam - bx) * sharpness);
	vec3 weight_c = smoothstep(1.0, 0.0, abs(beam - cx) * sharpness);
	vec3 weight_d = smoothstep(1.0, 0.0, (dx - beam) * sharpness);
	vec3 weight_e = smoothstep(1.0, 0.0, (ex - beam) * sharpness);

	// Mix samples into the upper scanline color
	vec3 upper_col = vec3(
		upper_a * weight_a +
		upper_b * weight_b +
		upper_c * weight_c +
		upper_d * weight_d +
		upper_e * weight_e
	);

	// Mix samples into the lower scanline color
	vec3 lower_col = vec3(
		lower_a * weight_a +
		lower_b * weight_b +
		lower_c * weight_c +
		lower_d * weight_d +
		lower_e * weight_e
	);

	vec3 weight_scaler = vec3(1.0) / (weight_a + weight_b + weight_c + weight_d + weight_e);

	// Normalize weight
	upper_col *= weight_scaler;
	lower_col *= weight_scaler;

	// Apply scanline brightness
	upper_col *= scanline_brightness;
	lower_col *= scanline_brightness;

	// Scanline size (and roughly the apperent brightness of this line)
	vec3 upper_thickness = mix(vec3(min_scanline_thickness), vec3(1.0), upper_col);
	vec3 lower_thickness = mix(vec3(min_scanline_thickness), vec3(1.0), lower_col);

	// Vertical sawtooth wave used to generate scanlines
	float sawtooth = (uv.y + 0.5) - float(y);

	vec3 upper_line = vec3(sawtooth) / upper_thickness;
	upper_line = smoothstep(1.0, 0.0, upper_line);

	vec3 lower_line = vec3(1.0 - sawtooth) / lower_thickness;
	lower_line = smoothstep(1.0, 0.0, lower_line);

	// Correct line brightness below min_scanline_thickness
	upper_line *= upper_col / upper_thickness;
	lower_line *= lower_col / lower_thickness;

	// Combine the upper and lower scanlines
	return upper_line + lower_line;
}

vec4 generate_mask(vec2 fragcoord) {
	switch (mask_type) {
		case 1: // Dots
			const vec3 pattern[] = {vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(0, 0, 0)};
			ivec2 icoords = ivec2(fragcoord);
			return vec4(pattern[(icoords.y * 2 + icoords.x) % 4], 0.25);
		case 2: // Grille
			const vec3 pattern[] = {vec3(0, 1, 0), vec3(1, 0, 1)};
			return vec4(pattern[int(fragcoord.x) % 2], 0.5);
		case 3: // Wide grille
			const vec3 pattern[] = {vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(0, 0, 0)};
			return vec4(pattern[int(fragcoord.x) % 4], 0.25);
		case 4: // Grille wide soft
			const vec3 pattern[] = {
				vec3(1.0, 0.125, 0.0),
				vec3(0.125, 1.0, 0.125),
				vec3(0.0, 0.125, 1.0),
				vec3(0.125, 0.0, 0.125)};
			return vec4(pattern[int(fragcoord.x) % 4], 0.3125);
		case 5: // Slotmask
			const vec3 pattern[] = {
				vec3(1, 0, 1), vec3(0, 1, 0), vec3(1, 0, 1), vec3(0, 1, 0),
				vec3(0, 0, 1), vec3(0, 1, 0), vec3(1, 0, 0), vec3(0, 0, 0),
				vec3(1, 0, 1), vec3(0, 1, 0), vec3(1, 0, 1), vec3(0, 1, 0),
				vec3(1, 0, 0), vec3(0, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0)};
			ivec2 icoords = ivec2(fragcoord) % 4;
			return vec4(pattern[icoords.y * 4 + icoords.x], 0.375);
		default:
			return vec4(0.5);
	}
}

// Add phosphor mask/grill
vec3 mask(vec3 linear_color, vec2 fragcoord) {
	// Get the pattern for the mask. Mask.w equals avg. brightness of the mask
	vec4 mask = generate_mask(fragcoord);

	// Dim the color if brightness is reduced to preserve mask details
	linear_color *= mix(mask.w, 1.0, mask_brightness);

	// How bright the color needs to be to maintain 100% brightness while masked
	vec3 target_color = linear_color / mask.w;

	// Target color limited to the 0 to 1 range.
	vec3 primary_col = clamp(target_color, 0.0, 1.0);

	// This calculates how bright the secondary subpixels will need to be
	vec3 highlights = target_color - primary_col;
	highlights /= 1.0 / mask.w - 1.0;

	primary_col *= mask.rgb;

	// Add the secondary subpixels
	primary_col += highlights * (1.0 - mask.rgb);

	return primary_col;
}

void fragment() {
	vec2 base_uv = SCREEN_UV;

	// Warp UV coordinates
	vec2 warped_coords = warp(base_uv, aspect, curve);

	// Add wobble
	warped_coords.x += wobble;

	// Sample the scanlines
	vec3 col = scanlines(warped_coords);

	// Apply phosphor mask on the virtual pixel grid (fixed to the glass)
	col = mask(col, floor(base_uv * virtual_size));

	COLOR.rgb = col;
	COLOR.a = 1.0;
}
