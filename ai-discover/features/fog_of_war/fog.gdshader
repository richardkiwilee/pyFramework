shader_type canvas_item;
// =============================================================================
// 战争迷雾 shader —— 双层揭示系统
//   explored_tex ：已探索层（GDScript 每帧把玩家足迹画进 ImageTexture，
//                  永久累积），显示为 40% 亮度的暗青色；
//   reveal_pos[i]：当前视野（实时均匀数组），完全可见；
//   其余区域 = 全黑迷雾（未探索）。
// 视野圆带软边，边缘用噪声抖动让迷雾边界有机一些。
// =============================================================================

uniform sampler2D explored_tex : filter_nearest;
uniform vec2 reveal_pos[4];
uniform float reveal_radius = 150.0;
uniform vec2 view_size = vec2(1280.0, 720.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = SCREEN_UV * view_size;
	float explored = texture(explored_tex, UV).r;

	// 视野圆（软边 + 噪声抖动边缘）
	float vis = 0.0;
	for (int i = 0; i < 4; i++) {
		if (reveal_pos[i].x < 0.0) {
			continue;
		}
		float d = length(p - reveal_pos[i]);
		float edge_noise = (hash21(floor(p / 14.0) + float(i) * 7.3) - 0.5) * 26.0;
		vis = max(vis, 1.0 - smoothstep(reveal_radius - 30.0, reveal_radius + 8.0 + edge_noise, d));
	}

	// 不透明迷雾：未探索 = 纯黑；已探索未在视野 = 暗青记忆；视野内 = 全亮
	float bright = max(vis, explored * (0.38 + 0.08 * sin(p.x * 0.3 + p.y * 0.2)));
	vec3 tint = mix(vec3(0.20, 0.28, 0.38), vec3(1.0), vis);
	COLOR = vec4(tint * bright, 1.0);
}
