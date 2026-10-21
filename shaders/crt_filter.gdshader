// VHS and CRT monitor effect - screen-space canvas_item variant.
// By pend00 (CC0): https://godotshaders.com/shader/vhs-and-crt-monitor-effect/
// Godot 4 移植参考：https://godotshaders.com/shader/vhs-and-crt-monitor-effect-2/
//
// 与参考实现（Godot 3 的 SCREEN_TEXTURE）不同，本变体：
// - 用 hint_screen_texture 取根视口 backbuffer，并保持 filter_nearest（像素画不被 mip 模糊）；
// - `resolution` 跟随设计分辨率（640x360），扫描线 / 像素块与游戏逻辑像素 1:1；
// - 荫罩频率单独取 `resolution.x / 3.0`：一条 RGB 条 = 2 逻辑像素，
//   若直接乘 `resolution.x`（参考默认 640x480 的写法）会变成亚像素频率并产生摩尔纹。
// 项目开启 viewport/hdr_2d，屏幕纹理为线性色，故全程线性运算，不做 sRGB 转换。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// true = 作为全屏叠层（ColorRect），读取屏幕纹理；false = 作用于节点自身的 TEXTURE。
uniform bool overlay = true;

uniform float scanlines_opacity : hint_range(0.0, 1.0) = 0.4;
uniform float scanlines_width : hint_range(0.0, 0.5) = 0.25;
uniform float grille_opacity : hint_range(0.0, 1.0) = 0.3;
// 图案网格（列 x 行）。扫描线 / 像素块 / 噪点按此划分，默认等于游戏逻辑分辨率。
uniform vec2 resolution = vec2(640.0, 360.0);

uniform bool pixelate = false;

uniform bool roll = true;
uniform float roll_speed = 8.0; // 正值向下滚动，负值向上
uniform float roll_size : hint_range(0.0, 100.0) = 15.0;
uniform float roll_variation : hint_range(0.1, 5.0) = 1.8;
uniform float distort_intensity : hint_range(0.0, 0.2) = 0.05;

uniform float noise_opacity : hint_range(0.0, 1.0) = 0.4;
uniform float noise_speed = 5.0;

uniform float static_noise_intensity : hint_range(0.0, 1.0) = 0.06;

uniform float aberration : hint_range(-1.0, 1.0) = 0.03;
uniform float brightness = 1.4; // 扫描线 + 荫罩会压暗画面，用亮度补偿
uniform bool discolor = true;

uniform float warp_amount : hint_range(0.0, 5.0) = 1.0; // 曲面玻璃造成的边缘桶形畸变
uniform bool clip_warp = false;

uniform float vignette_intensity = 0.4;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.5;

// 伪随机值，范围 -1.0 ~ 1.0
vec2 random(vec2 uv){
	uv = vec2( dot(uv, vec2(127.1, 311.7) ),
			   dot(uv, vec2(269.5, 183.3) ) );
	return -1.0 + 2.0 * fract(sin(uv) * 43758.5453123);
}

// 供扭曲效果使用的 Perlin 噪声
float noise(vec2 uv) {
	vec2 uv_index = floor(uv);
	vec2 uv_fract = fract(uv);

	vec2 blur = smoothstep(0.0, 1.0, uv_fract);

	return mix( mix( dot( random(uv_index + vec2(0.0, 0.0) ), uv_fract - vec2(0.0, 0.0) ),
					 dot( random(uv_index + vec2(1.0, 0.0) ), uv_fract - vec2(1.0, 0.0) ), blur.x),
				mix( dot( random(uv_index + vec2(0.0, 1.0) ), uv_fract - vec2(0.0, 1.0) ),
					 dot( random(uv_index + vec2(1.0, 1.0) ), uv_fract - vec2(1.0, 1.0) ), blur.x), blur.y) * 0.5 + 0.5;
}

// 按 UV 扭曲边缘，模拟 CRT 的球面玻璃
vec2 warp(vec2 uv){
	vec2 delta = uv - 0.5;
	float delta2 = dot(delta.xy, delta.xy);
	float delta4 = delta2 * delta2;
	float delta_offset = delta4 * warp_amount;

	return uv + delta * delta_offset;
}

// 用黑边遮住 warp 拉伸出来的像素
float border(vec2 uv){
	float radius = min(warp_amount, 0.08);
	radius = max(min(min(abs(radius * 2.0), abs(1.0)), abs(1.0)), 1e-5);
	vec2 abs_uv = abs(uv * 2.0 - 1.0) - vec2(1.0, 1.0) + radius;
	float dist = length(max(vec2(0.0), abs_uv)) / radius;
	float square = smoothstep(0.96, 1.0, dist);
	return clamp(1.0 - square, 0.0, 1.0);
}

// 边缘暗角
float vignette(vec2 uv){
	uv *= 1.0 - uv.xy;
	float vignette = uv.x * uv.y * 15.0;
	return pow(vignette, vignette_intensity * vignette_opacity);
}

void fragment()
{
	// warp 后的 UV 后续都复用，避免重复计算
	vec2 uv = overlay ? warp(SCREEN_UV) : warp(UV);
	vec2 text_uv = uv;
	vec2 roll_uv = vec2(0.0);
	float time = roll ? TIME : 0.0;

	// 按 resolution 把采样吸附到方格，制造像素质感
	if (pixelate)
	{
		text_uv = ceil(uv * resolution) / resolution;
	}

	// 滚动干扰带。噪点效果也要复用 roll_line，所以 roll 为 false 但 noise_opacity > 0 时同样计算。
	float roll_line = 0.0;
	if (roll || noise_opacity > 0.0)
	{
		roll_line = smoothstep(0.3, 0.9, sin(uv.y * roll_size - (time * roll_speed) ) );
		roll_line *= roll_line * smoothstep(0.3, 0.9, sin(uv.y * roll_size * roll_variation - (time * roll_speed * roll_variation) ) );
		roll_uv = vec2(( roll_line * distort_intensity * (1. - UV.x)), 0.0);
	}

	// 分通道采样做色差；roll 开启时同时应用滚动扭曲
	vec4 text;
	if (roll)
	{
		text.r = texture(screen_tex, text_uv + roll_uv * 0.8 + vec2(aberration, 0.0) * .1).r;
		text.g = texture(screen_tex, text_uv + roll_uv * 1.2 - vec2(aberration, 0.0) * .1).g;
		text.b = texture(screen_tex, text_uv + roll_uv).b;
		text.a = 1.0;
	}
	else
	{
		text.r = texture(screen_tex, text_uv + vec2(aberration, 0.0) * .1).r;
		text.g = texture(screen_tex, text_uv - vec2(aberration, 0.0) * .1).g;
		text.b = texture(screen_tex, text_uv).b;
		text.a = 1.0;
	}

	float r = text.r;
	float g = text.g;
	float b = text.b;

	uv = warp(UV);

	// 荫罩：把颜色通道拆成相邻的 R/G/B 竖条。
	// 频率取 resolution.x / 3.0，与设计分辨率的逻辑像素对齐（直接乘 resolution.x 会亚像素化）。
	float grille_res = max(resolution.x / 3.0, 1.0);
	if (grille_opacity > 0.0)
	{
		float g_r = smoothstep(0.85, 0.95, abs(sin(uv.x * (grille_res * 3.14159265))));
		r = mix(r, r * g_r, grille_opacity);

		float g_g = smoothstep(0.85, 0.95, abs(sin(1.05 + uv.x * (grille_res * 3.14159265))));
		g = mix(g, g * g_g, grille_opacity);

		float b_b = smoothstep(0.85, 0.95, abs(sin(2.1 + uv.x * (grille_res * 3.14159265))));
		b = mix(b, b * b_b, grille_opacity);
	}

	// 荫罩 + 扫描线会让画面很暗，用 brightness 补偿
	text.r = clamp(r * brightness, 0.0, 1.0);
	text.g = clamp(g * brightness, 0.0, 1.0);
	text.b = clamp(b * brightness, 0.0, 1.0);

	// 扫描线：设置每行之间的黑色间隔
	float scanlines = 0.5;
	if (scanlines_opacity > 0.0)
	{
		scanlines = smoothstep(scanlines_width, scanlines_width + 0.5, abs(sin(uv.y * (resolution.y * 3.14159265))));
		text.rgb = mix(text.rgb, text.rgb * vec3(scanlines), scanlines_opacity);
	}

	// 横向拉伸的带状噪点，随 noise_speed 移动
	if (noise_opacity > 0.0)
	{
		float n = smoothstep(0.4, 0.5, noise(uv * vec2(2.0, 200.0) + vec2(10.0, (TIME * (noise_speed))) ) );

		// 用 roll_line 限定噪点的垂直范围，再叠一层随机噪声打散图案
		roll_line *= n * scanlines * clamp(random((ceil(uv * resolution) / resolution) + vec2(TIME * 0.8, 0.0)).x + 0.8, 0.0, 1.0);
		text.rgb = clamp(mix(text.rgb, text.rgb + roll_line, noise_opacity), vec3(0.0), vec3(1.0));
	}

	// 全屏静态噪点
	if (static_noise_intensity > 0.0)
	{
		text.rgb += clamp(random((ceil(uv * resolution) / resolution) + fract(TIME)).x, 0.0, 1.0) * static_noise_intensity;
	}

	// 黑边遮住 warp 的瑕疵，再叠暗角
	text.rgb *= border(uv);
	text.rgb *= vignette(uv);
	// 让黑边区域透明，方便把效果叠在电视 / 显示器贴图上
	if (clip_warp)
	{
		text.a = border(uv);
	}

	// 复古脱色（降饱和 + 提对比），模拟 VHS 录像
	if (discolor)
	{
		float saturation = 0.5;
		float contrast = 1.2;
		vec3 greyscale = vec3(text.r + text.g + text.b) / 3.;
		text.rgb = mix(text.rgb, greyscale, saturation);

		float midpoint = pow(0.5, 2.2);
		text.rgb = (text.rgb - vec3(midpoint)) * contrast + midpoint;
	}

	COLOR = text;
}
