shader_type canvas_item;
render_mode unshaded;
// 影子只保留精灵的 alpha，颜色统一染成一种冷调深色。
// 直接用 modulate 的话影子里会透出投影物本身的颜色（红屋顶投出红影子），不对。
uniform vec4 shadow_color : source_color = vec4(0.05, 0.06, 0.16, 0.42);

void fragment() {
	COLOR = vec4(shadow_color.rgb, shadow_color.a * texture(TEXTURE, UV).a);
}
