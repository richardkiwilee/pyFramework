shader_type canvas_item;
// =============================================================================
// 故障风 shader —— CRT 扫描线 + RGB 色偏 + 随机水平撕裂
// 背景由程序化彩色条纹生成，叠加三层故障效果：
//   1. 扫描线：按行正弦压暗（CRT 质感）；
//   2. RGB 偏移：红蓝通道按行随机横向错位；
//   3. 撕裂：随机行段整体横移 + 亮条。
// =============================================================================

uniform float u_time = 0.0;
uniform vec2 view_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = SCREEN_UV * view_size;
	float row = floor(p.y / 2.0);
	// 行级随机（每帧抖动，让撕裂"闪"起来）
	float rnd = hash21(vec2(row, floor(u_time * 10.0)));

	// 程序化彩色底图（霓虹横条 + 网格）
	float bands = 0.5 + 0.5 * sin(p.y * 0.05 + u_time * 2.0);
	vec3 base = mix(vec3(0.05, 0.02, 0.12), vec3(0.10, 0.20, 0.30), bands);
	float grid = hash21(floor(p / 42.0));
	base += vec3(0.05, 0.02, 0.1) * grid;

	// 1. 扫描线
	base *= 0.82 + 0.18 * sin(p.y * 1.2 + u_time * 3.0);

	// 2. RGB 偏移（按行随机错位）
	float shift = (rnd - 0.5) * 26.0;
	float shift2 = (hash21(vec2(row, 77.7)) - 0.5) * 26.0;
	vec2 off_r = vec2(shift, 0.0) / view_size;
	vec2 off_b = vec2(-shift2, 0.0) / view_size;
	vec3 col;
	col.r = texture(TEXTURE, UV + off_r).r;
	col.g = base.g;
	col.b = texture(TEXTURE, UV + off_b).b;

	// 3. 随机撕裂带
	float tear = step(0.965, rnd);
	float tear_shift = (hash21(vec2(row, 3.3)) - 0.5) * 220.0;
	vec3 torn = texture(TEXTURE, UV + vec2(tear_shift / view_size.x, 0.0)).rgb;
	col = mix(col, torn, tear);
	col += vec3(0.35, 0.6, 0.9) * tear * 0.25;

	COLOR = vec4(col, 1.0);
}
