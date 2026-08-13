shader_type canvas_item;
// =============================================================================
// 万花筒 shader —— 扇形折叠 + 极坐标噪声场
// 经典对称图案算法：把极角 mod(TAU/N) 后取绝对值（三角折叠），
// 图案自动获得 N 重旋转对称；噪声场随时间演化、半径调制色相。
// =============================================================================

uniform int sectors = 6;
uniform float u_time = 0.0;
uniform float zoom = 1.0;
uniform vec2 view_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.7, 9.3);
		a *= 0.5;
	}
	return v;
}

vec3 hsv2rgb(float h, float s, float v) {
	vec3 c = vec3(h * 6.0, 1.0, 1.0);
	vec3 rgb = clamp(abs(mod(c.xxx + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), rgb, s);
}

void fragment() {
	vec2 p = SCREEN_UV * view_size - view_size * 0.5;
	float r = length(p) * zoom / 260.0;
	float a = atan(p.y, p.x);
	// 扇形折叠（万花筒核心）
	float k = 6.28318 / float(sectors);
	float a2 = mod(a, k);
	a2 = abs(a2 - k * 0.5);

	vec2 q = vec2(cos(a2) * r, sin(a2) * r);
	float n = fbm(q * 1.8 + vec2(u_time * 0.35, u_time * 0.22));
	float n2 = fbm(q * 3.2 - u_time * 0.25);

	float hue = fract(n * 0.7 + n2 * 0.3 + u_time * 0.05);
	float val = 0.15 + 0.85 * n2;
	float edge = smoothstep(0.0, 0.06, a2);          // 折叠缝微光
	vec3 col = hsv2rgb(hue, 0.65, val) * (0.8 + 0.5 * edge);
	// 中心柔光
	col += vec3(0.9, 0.95, 1.0) * smoothstep(60.0, 0.0, length(p)) * 0.4;
	// 暗角
	col *= 1.0 - smoothstep(300.0, 620.0, length(p));
	COLOR = vec4(col, 1.0);
}
