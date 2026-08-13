shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
// =============================================================================
// 水面 shader —— 波浪顶点位移 + 菲涅尔 + 波光高光
// 半透明（blend_mix）让水面下的镜像世界透出来，形成"倒影"。
// =============================================================================

uniform vec3 deep_color : source_color = vec3(0.03, 0.20, 0.40);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.52, 0.70);

varying vec3 world_pos;

// 两层正弦波浪叠加（沿世界坐标，保证与岸形无关）
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w1 = sin(world_pos.x * 0.6 + TIME * 1.4) * 0.60;
	float w2 = cos(world_pos.z * 0.75 + TIME * 1.8) * 0.45;
	VERTEX.y += (w1 + w2) * 0.12;
}

void fragment() {
	// 波浪法线（对位移求导），让高光随波浪流动
	float k1 = 0.6, s1 = 1.4, k2 = 0.75, s2 = 1.8;
	float dx = cos(world_pos.x * k1 + TIME * s1) * k1 * 0.60;
	float dz = -sin(world_pos.z * k2 + TIME * s2) * k2 * 0.45;
	vec3 n = normalize(vec3(-dx * 0.12, 1.0, -dz * 0.12));

	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - max(dot(n, v), 0.0), 1.6);   // 掠射角更反光
	float spec = pow(max(dot(n, v), 0.0), 40.0) * 0.8;  // 太阳波光

	// 深浅水色随位置缓慢变化，模拟水底起伏
	float shade = 0.5 + 0.5 * sin(world_pos.x * 0.35 + world_pos.z * 0.28 + TIME * 0.7);
	vec3 col = mix(deep_color, shallow_color, shade);

	ALBEDO = col * (0.55 + fres * 1.0) + vec3(1.0) * spec;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	ALPHA = 0.86;
}
