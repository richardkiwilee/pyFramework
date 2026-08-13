shader_type canvas_item;
// =============================================================================
// 爆气蓄力特效 shader —— 超级赛亚人风格的"爆气"能量场
// =============================================================================
// 特效不是全屏铺满，而是【缠绕在角色身上】的能量场：表示角色正在
// 蓄力爆气、即将释放必杀技。角色剪影由纯 SDF 绘制（无美术资源），
// 站在屏幕中央；能量贴着身体轮廓向外喷发，档位越高范围越大越亮。
//
// 三档爆气（mode），由 main.gd 每 1 秒循环切换：
//   0 = 烈焰爆气：从身体升腾的火苗，贴着轮廓燃烧，焰心白热
//   1 = 天雷灌顶：闪电从屏幕顶击落角色头顶 + 全身电弧噼啪 + 局部爆闪
//   2 = 龙卷缠身：能量旋涡高速环绕身体，头顶冲起旋转能量柱
//
// 档位 level（1~3）→ 强度 amp（0.55 / 1.0 / 1.45）：
//   能量场半径更大、更亮；档位 >= 2 时角色眼睛发光（爆气升级细节）。
// 注意：canvas shader 的 UV 原点在【左上角】、y 向下。
// =============================================================================

uniform int mode : hint_range(0, 2) = 0;
uniform int level : hint_range(1, 3) = 2;
uniform vec4 effect_color : source_color = vec4(1.0, 0.55, 0.08, 1.0);

// ------------------------------------------------------------------ 噪声工具
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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.7, 9.3);
		a *= 0.5;
	}
	return v;
}

// ------------------------------------------------------------------ 角色剪影（SDF）
// 扎马步的爆气姿势：头 + 躯干 + 叉开双腿 + 微张双臂
float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float body_sdf(vec2 p) {
	float head = length(p - vec2(0.5, 0.225)) - 0.062;
	float torso = sd_seg(p, vec2(0.5, 0.33), vec2(0.5, 0.47)) - 0.085;
	float leg_l = sd_seg(p, vec2(0.468, 0.47), vec2(0.452, 0.60)) - 0.036;
	float leg_r = sd_seg(p, vec2(0.532, 0.47), vec2(0.548, 0.60)) - 0.036;
	float arm_l = sd_seg(p, vec2(0.42, 0.35), vec2(0.368, 0.47)) - 0.030;
	float arm_r = sd_seg(p, vec2(0.58, 0.35), vec2(0.632, 0.47)) - 0.030;
	float d = min(head, torso);
	d = min(d, leg_l);
	d = min(d, leg_r);
	d = min(d, arm_l);
	d = min(d, arm_r);
	return d;
}

// ------------------------------------------------------------------ 深色舞台背景
vec3 stage_bg(vec2 uv) {
	vec3 c = mix(vec3(0.02, 0.025, 0.05), vec3(0.055, 0.055, 0.10), uv.y);
	c += vec3(0.05, 0.04, 0.07) * smoothstep(0.85, 1.0, uv.y);
	return c;
}

// ------------------------------------------------------------------ 1. 烈焰爆气
vec3 flame_aura(vec2 uv, float amp) {
	float bd = body_sdf(uv);
	float r = 0.10 + 0.17 * amp;              // 能量场半径（档位越高越大）
	float field = smoothstep(r, r * 0.25, bd);
	// 高度轮廓：脚下熄灭 → 身体最强 → 头顶以上渐隐
	field *= smoothstep(0.64, 0.47, uv.y) * (1.0 - smoothstep(0.055, 0.16, uv.y));
	if (field <= 0.001) {
		return vec3(0.0);
	}
	// 火苗：垂直向上流动的噪声
	float n = fbm(vec2(uv.x * 34.0, uv.y * 26.0 + TIME * 5.0));
	// 靠近身体的焰心更白更亮
	float core = exp(-bd * 10.0);
	vec3 c = mix(effect_color.rgb * 0.5, effect_color.rgb * 1.7, n);
	c = mix(c, vec3(1.0, 0.95, 0.8), core * 0.6);
	return c * field * (0.45 + 0.75 * n) * (0.6 + amp * 0.5);
}

// ------------------------------------------------------------------ 2. 天雷灌顶
vec3 lightning_aura(vec2 uv, float amp) {
	float bd = body_sdf(uv);
	float r = 0.09 + 0.13 * amp;
	float field = smoothstep(r, r * 0.3, bd);
	vec3 col = vec3(0.0);
	// 持续电弧微光：贴着身体噼啪的细小火花
	float crackle = fbm(vec2(uv.x * 55.0 + TIME * 1.5, uv.y * 55.0 - TIME * 2.0));
	col += effect_color.rgb * field * crackle * 0.4;

	// 雷击包络：出现 → 维持 → 熄灭
	float t = TIME * 2.2;
	float strike = floor(t);
	float ft = fract(t);
	float env = smoothstep(0.0, 0.07, ft) * (1.0 - smoothstep(0.4, 0.85, ft));
	if (env <= 0.001) {
		return col;
	}

	// 主雷：从屏幕顶击落角色头顶（落点小幅随机抖动）
	float hx = 0.5 + (hash21(vec2(strike, 4.2)) - 0.5) * 0.03;
	float y0 = uv.y;
	float segs = 6.0 + 5.0 * amp;             // 档位越高段数越多
	float ds = 0.225 / segs;
	float bx = hx;
	float glow = 0.0;
	for (int i = 0; i < 12; i++) {
		float s = float(i) * ds;
		if (s > 0.225) {
			break;
		}
		float rnd = hash21(vec2(strike, float(i) + 0.7));
		float nx = bx + (rnd - 0.5) * ds * 2.0;
		if (y0 >= s && y0 < s + ds) {
			float f = (y0 - s) / ds;
			float lx = mix(bx, nx, f);
			float d = uv.x - lx;
			float w = 0.0035 + 0.003 * f;
			glow = exp(-d * d / (w * w));
		}
		bx = nx;
		if (y0 < s) {
			break;
		}
	}
	col += mix(effect_color.rgb, vec3(1.0), 0.6) * glow * env * (1.2 + amp);

	// 头顶落点爆闪（局部，不铺满全屏）
	float imp = exp(-length(uv - vec2(hx, 0.225)) * 60.0);
	col += vec3(1.0, 0.95, 0.8) * imp * env * (0.7 + 0.3 * amp);
	// 角色周身泛光
	col += vec3(0.8, 0.85, 1.0) * exp(-bd * 6.0) * env * 0.5 * (0.6 + 0.4 * amp);

	// 两条从头顶劈向两肩的短电弧（抖动亮点连成的弧）
	float arc = 0.0;
	for (int j = 0; j < 2; j++) {
		float sx = (j == 0) ? 0.40 : 0.60;
		for (int i = 0; i < 5; i++) {
			float f0 = float(i) / 4.0;
			float rnd = hash21(vec2(strike + float(j), float(i) + 3.3));
			vec2 q = vec2(mix(hx, sx, f0) + (rnd - 0.5) * 0.03, mix(0.225, 0.30, f0));
			float dd = length(uv - q);
			arc = max(arc, exp(-dd * dd / 0.000036));
		}
	}
	col += vec3(1.0) * arc * env * 0.9;
	return col;
}

// ------------------------------------------------------------------ 3. 龙卷缠身
vec3 tornado_aura(vec2 uv, float amp) {
	vec2 p = uv - vec2(0.5, 0.34);            // 相对角色中心
	float rr = length(p);
	float ang = atan(p.y, p.x);
	float bd = body_sdf(uv);
	float r = 0.09 + 0.15 * amp;
	float field = smoothstep(r, r * 0.3, bd); // 环绕身体的能量环
	field *= smoothstep(0.62, 0.55, uv.y);    // 小腿以下不缠绕

	vec3 col = vec3(0.0);
	// 旋涡带：围绕身体高速旋转的亮暗条纹
	float bands = 0.5 + 0.5 * sin(ang * 6.0 + rr * 45.0 - TIME * 11.0);
	float twist = fbm(vec2(ang * 2.5 + rr * 25.0, rr * 18.0 - TIME * 9.0));
	col += effect_color.rgb * field * bands * (0.7 + 0.9 * twist) * (0.8 + amp * 0.6);

	// 头顶能量柱：从头顶向上冲起、扭转的气柱（爆气核心视觉）
	float pillar = smoothstep(0.055, 0.0, abs(p.x)) * (1.0 - smoothstep(0.02, 0.30, -p.y));
	if (pillar > 0.001) {
		float col_n = fbm(vec2(uv.x * 20.0 + TIME * 4.0, uv.y * 30.0 + TIME * 8.0));
		float col_bands = 0.5 + 0.5 * sin(uv.x * 30.0 + uv.y * 12.0 - TIME * 10.0);
		col += effect_color.rgb * pillar * col_n * col_bands * (1.0 + amp);
		col += vec3(1.0) * pillar * smoothstep(0.02, 0.0, abs(p.x)) * 0.6;
	}
	return col;
}

// ------------------------------------------------------------------ 合成
void fragment() {
	vec2 uv = UV;
	vec3 col = stage_bg(uv);
	float amp = 0.55 + float(level - 1) * 0.45;

	// 地面阴影：压暗背景，让角色"站"住
	float sh = exp(-pow((uv.x - 0.5) / 0.26, 2.0) - pow((uv.y - 0.615) / 0.045, 2.0));
	col *= 1.0 - 0.6 * sh;

	// 角色本体：暗色剪影 + 特效色描边（能量从轮廓透出来）
	float bd = body_sdf(uv);
	float body_mask = 1.0 - smoothstep(0.0, 0.004, bd);
	float rim = smoothstep(0.010, -0.012, bd);
	vec3 body_col = vec3(0.05, 0.06, 0.10) + effect_color.rgb * rim * (0.55 + 0.85 * amp);
	col = mix(col, body_col, body_mask);

	// 爆气特效（全部局限在角色周围）
	if (mode == 0) {
		col += flame_aura(uv, amp);
	} else if (mode == 1) {
		col += lightning_aura(uv, amp);
	} else {
		col += tornado_aura(uv, amp);
	}

	// 脚下能量光晕
	float gglow = exp(-pow((uv.x - 0.5) / 0.24, 2.0) - pow((uv.y - 0.615) / 0.055, 2.0));
	col += effect_color.rgb * gglow * (0.18 + 0.32 * amp);

	// 眼睛发光（档位 >= 2 才亮：爆气升级的细节）
	float eye1 = smoothstep(0.009, 0.0, length(uv - vec2(0.477, 0.222)));
	float eye2 = smoothstep(0.009, 0.0, length(uv - vec2(0.523, 0.222)));
	col += vec3(1.0, 0.95, 0.75) * max(eye1, eye2) * step(1.5, float(level)) * (0.7 + 0.3 * sin(TIME * 14.0));

	// 暗角：把视线聚到角色身上
	float vig = 1.0 - length((uv - vec2(0.5, 0.4)) * vec2(1.3, 1.0)) * 0.55;
	col *= clamp(vig, 0.0, 1.0);
	COLOR = vec4(col, 1.0);
}
