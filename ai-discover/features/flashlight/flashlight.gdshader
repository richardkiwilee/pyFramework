shader_type canvas_item;
// =============================================================================
// 手电筒光照 shader —— 光锥 + 距离衰减 + 柔边
// 背景是彩色噪声"藏宝图"，只有光锥内可见；
// 光锥方向随鼠标移动方向转动（GDScript 每帧推 uniform）。
// =============================================================================

uniform vec2 light_pos = vec2(640.0, 360.0);
uniform float light_angle = 1.5708;   // 锥形中线方向（弧度）
uniform float cone_half = 0.55;       // 半张角
uniform float flicker = 1.0;
uniform vec2 view_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// 彩色噪声背景（藏宝图感）
vec3 treasure_map(vec2 p) {
	vec2 cell = floor(p / 90.0);
	float n = hash21(cell);
	float n2 = hash21(cell + 37.0);
	vec3 base = mix(vec3(0.10, 0.14, 0.10), vec3(0.16, 0.12, 0.07), n2);
	if (n > 0.55) {
		base = vec3(0.12, 0.18, 0.30);            // 水
	} else if (n > 0.35) {
		base = vec3(0.30, 0.24, 0.12);            // 沙地
	}
	// 细节纹理
	float fine = hash21(floor(p / 22.0));
	base += vec3(0.03, 0.02, 0.01) * fine;
	// 宝藏标记（金色 X）
	vec2 c1 = vec2(0.62, 0.35) * view_size;
	if (length(p - c1) < 26.0 && hash21(vec2(3.0, 7.0)) > 0.1) {
		base = vec3(0.85, 0.7, 0.2);
	}
	return base;
}

void fragment() {
	vec2 p = SCREEN_UV * view_size;
	vec2 rel = p - light_pos;
	float d = length(rel);
	// 角度差包绕
	float a = atan(rel.y, rel.x);
	float da = mod(a - light_angle + 3.14159, 6.28318) - 3.14159;
	float cone = 1.0 - smoothstep(cone_half - 0.18, cone_half + 0.02, abs(da));
	float fall = 1.0 - smoothstep(90.0, 420.0, d);
	float light = cone * fall * flicker;
	// 光源处的小光晕
	float glow = smoothstep(40.0, 0.0, d);

	vec3 col = treasure_map(p);
	col *= 0.04 + 0.96 * light;
	col += vec3(1.0, 0.95, 0.8) * glow * 0.6;
	COLOR = vec4(col, 1.0);
}
