shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// 科技风地面网格：UV 平铺 20×20 网格线
void fragment() {
	float gx = abs(fract(UV.x * 20.0) - 0.5);
	float gy = abs(fract(UV.y * 20.0) - 0.5);
	float line = smoothstep(0.02, 0.0, min(gx, gy));
	ALBEDO = mix(vec3(0.08, 0.09, 0.13), vec3(0.22, 0.28, 0.44), line);
	ROUGHNESS = 0.9;
}
