shader_type canvas_item;
// =============================================================================
// BP 宝石槽 shader —— 八方旅人风格的 BP Boost 指示器
// =============================================================================
// 底部中央三颗菱形宝石（与《八方旅人》BP 槽一致：菱形 + 白炽核心）。
// level = 已充能数量（1~3），充能的宝石：
//   主题色填充 + 白炽核心 + 呼吸脉动 + 外辉光；
// 未充能的宝石：暗色描边 + 微弱的暗面。
// effect_color 与特效主 shader 共用同一份调色盘颜色。
// =============================================================================

uniform int level : hint_range(1, 3) = 2;
uniform vec4 effect_color : source_color = vec4(1.0, 0.55, 0.08, 1.0);

// 菱形距离场：返回 1 表示正好在菱边（|dx| + |dy| = r）
float gem_sdf(vec2 p, vec2 c, float r) {
	vec2 q = abs(p - c);
	return (q.x + q.y) / r;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = vec3(0.0);
	float alpha = 0.0;   // 背景必须透明，否则会挡住后面的特效
	for (int i = 0; i < 3; i++) {
		vec2 c = vec2(0.5 + (float(i) - 1.0) * 0.31, 0.5);
		float d = gem_sdf(uv, c, 0.15);
		float edge = 1.0 - smoothstep(0.94, 1.0, d);       // 菱边高光
		float inside = 1.0 - smoothstep(0.0, 1.0, d);      // 内部填充
		if (i < level) {
			// —— 已充能：主题色 + 白炽核心 + 呼吸脉动 + 外辉光 ——
			float pulse = 0.82 + 0.18 * sin(TIME * 3.2 + float(i) * 1.1);
			float glow = 1.0 - smoothstep(1.0, 2.4, d);
			col += mix(effect_color.rgb, vec3(1.0), 0.3) * inside * pulse;
			col += vec3(1.0) * (1.0 - smoothstep(0.0, 0.42, d)) * 0.85;
			col += effect_color.rgb * glow * 0.3 * pulse;
			col += vec3(1.0) * edge * 0.5 * pulse;
			alpha = max(alpha, inside);
			alpha = max(alpha, glow * 0.35);
		} else {
			// —— 未充能：暗色描边 + 微弱暗面 ——
			col += vec3(0.28, 0.30, 0.38) * edge * 0.8;
			col += vec3(0.10, 0.11, 0.15) * inside * 0.35;
			alpha = max(alpha, edge * 0.8);
			alpha = max(alpha, inside * 0.35);
		}
	}
	COLOR = vec4(col, alpha);
}
