shader_type spatial;
render_mode cull_disabled, unshaded;
// =============================================================================
// 传送门 shader —— 旋转噪声漩涡 + 边缘辉光 + 呼吸脉动
// 用在朝相机 billboard 的 QuadMesh 上，UV 圆形裁切成能量圆盘。
// =============================================================================

uniform vec4 core_color : source_color = vec4(0.30, 0.60, 1.0, 1.0);

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;                      // 圆盘裁切
	}
	float ang = atan(p.y, p.x);

	// 旋转的漩涡：噪声沿角度方向流动
	float swirl = fbm(vec2(ang * 1.6, r * 5.0 - TIME * 1.6));
	// 螺旋臂
	float arms = 0.5 + 0.5 * sin(ang * 4.0 - r * 18.0 + TIME * 3.5);

	// 中心亮核 + 边缘辉光环
	float core = smoothstep(0.35, 0.0, r);
	float rim = smoothstep(1.0, 0.62, r);

	vec3 col = core_color.rgb * (0.15 + 0.45 * swirl + 0.35 * arms);
	col += core_color.rgb * core * (0.6 + 0.4 * sin(TIME * 4.0));
	col += vec3(1.0) * core * core * 0.9;
	col += core_color.rgb * rim * 0.8;

	ALBEDO = col;
	EMISSION = col * (0.9 + 0.35 * arms);
}
