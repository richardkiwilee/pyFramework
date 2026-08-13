shader_type canvas_item;
// 中奖行辉光：金色横向渐变 + 呼吸脉动
void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * 6.0);
	float g = 1.0 - abs(UV.x - 0.5) * 2.0;   // 中间亮、两边暗
	COLOR = vec4(1.0, 0.85, 0.30, g * (0.15 + 0.30 * pulse));
}
