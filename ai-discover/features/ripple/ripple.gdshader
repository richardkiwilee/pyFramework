shader_type canvas_item;
// =============================================================================
// 点击波纹 shader —— 深水背景 + 扩散圆环
// 波纹数据（位置/出生时刻）由 GDScript 以 uniform 数组注入，
// 时间统一用 GDScript 传入的 u_time（与波纹出生时刻同一时钟），
// 不依赖 shader 内置 TIME，逻辑更可控。
// =============================================================================

uniform vec2 ripple_pos[8];
uniform float ripple_time[8];          // -1 = 该槽位无波纹
uniform float u_time = 0.0;
uniform vec2 view_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = SCREEN_UV * view_size;
	// 深水背景 + 缓慢流动的微光纹理
	float n = hash21(floor(p / 26.0) + floor(vec2(u_time * 0.8, u_time * 0.4)));
	vec3 col = vec3(0.02, 0.05, 0.10) + vec3(0.03, 0.06, 0.11) * n;
	col += vec3(0.02, 0.04, 0.09) * smoothstep(0.0, 720.0, p.y);

	for (int i = 0; i < 8; i++) {
		float age = u_time - ripple_time[i];
		if (age < 0.0 || age > 2.5) {
			continue;
		}
		float d = length(p - ripple_pos[i]);
		float fade = 1.0 - age / 2.5;
		float r = age * 260.0;                     // 主环半径
		float band = smoothstep(26.0, 0.0, abs(d - r));
		col += vec3(0.45, 0.78, 1.0) * band * fade * 0.9;
		float band2 = smoothstep(14.0, 0.0, abs(d - r * 0.55));  // 内圈次环
		col += vec3(1.0) * band2 * fade * 0.3;
		// 环心亮斑
		col += vec3(0.6, 0.9, 1.0) * smoothstep(30.0, 0.0, d) * fade * fade * 0.5;
	}
	COLOR = vec4(col, 1.0);
}
