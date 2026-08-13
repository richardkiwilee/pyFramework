shader_type canvas_item;
// =============================================================================
// 刀光 shader —— 月牙形斩击（基于屏幕坐标，不依赖多边形 UV）
// 多边形只负责"裁剪形状"，颜色梯度在 shader 里按屏幕位置计算：
//   r   = 像素到斩击圆心的距离 → 内缘白热核心、外缘主题色
//   da  = 像素相对斩击方向的角度 → 月牙两端渐隐
// =============================================================================

uniform vec4 slash_color : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec2 center = vec2(640.0, 360.0);   // 斩击圆心（屏幕像素坐标）
uniform float ang = 0.0;                    // 斩击方向（弧度）
uniform float spread = 1.5;                 // 月牙张角
uniform float inner_r = 100.0;              // 内半径（刀身内侧）
uniform float outer_r = 140.0;              // 外半径（刃尖）
uniform vec2 view_size = vec2(1280.0, 720.0);

void fragment() {
	vec2 p = SCREEN_UV * view_size - center;
	float r = length(p);
	float t = clamp((r - inner_r) / (outer_r - inner_r), 0.0, 1.0);
	float a = atan(p.y, p.x);
	// 角度差包绕到 -π..π（斩击方向可能跨 ±π 边界）
	float da = mod(a - ang + 3.14159, 6.28318) - 3.14159;
	float f = clamp((da + spread * 0.5) / spread, 0.0, 1.0);
	// 月牙两端渐隐
	float edge = smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.85, 1.0, f));
	// 内缘白热核心 → 外缘主题色
	float core = smoothstep(0.5, 0.08, t);
	vec3 col = mix(slash_color.rgb, vec3(1.0), core * 0.9);
	// 沿弧线的能量条纹（噪声流动）
	float n = fract(sin(dot(SCREEN_UV * vec2(460.0, 90.0) + TIME * 7.0, vec2(12.9, 78.2))) * 43758.5);
	float streak = 0.7 + 0.45 * n;
	COLOR = vec4(col * streak * 2.2, edge);
}
