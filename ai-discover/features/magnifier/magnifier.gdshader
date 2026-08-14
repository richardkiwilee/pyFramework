shader_type canvas_item;
// =============================================================================
// 放大镜 shader —— 圆形透镜放大屏幕纹理
// 透镜内：向中心收缩采样坐标（放大 1/zoom 的偏移）→ 内容被放大；
// 透镜外：透明。边缘加细描边环。
// =============================================================================

uniform float zoom = 2.0;
uniform float lens_radius = 100.0;
uniform vec2 lens_center = vec2(640.0, 360.0);
uniform vec2 view_size = vec2(1280.0, 720.0);

void fragment() {
	vec2 p = SCREEN_UV * view_size - lens_center;
	float r = length(p);
	if (r > lens_radius) {
		discard;   // 透镜外完全透明
	}
	// 放大采样：把采样点向圆心拉近 (1/zoom - 1) 的比例
	vec2 uv2 = SCREEN_UV + (SCREEN_UV - lens_center / view_size) * (1.0 / zoom - 1.0);
	vec3 col = texture(SCREEN_TEXTURE, uv2).rgb;
	// 边缘描边
	float rim = smoothstep(lens_radius - 3.0, lens_radius, r);
	col = mix(col, vec3(0.15, 0.16, 0.2), rim * 0.9);
	// 玻璃高光
	float glint = smoothstep(30.0, 0.0, length(p - vec2(-lens_radius * 0.35, -lens_radius * 0.35)));
	col += vec3(1.0) * glint * 0.12;
	COLOR = vec4(col, 1.0);
}
