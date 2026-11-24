shader_type canvas_item;
// 品级材质：只换牌体材质，不改牌面图案（材质管品级）。
// grade: 0 普通 / 1 蓝·青玉 / 2 紫·紫晶 / 3 金·鎏金 / 4 钻·钻石

uniform int grade = 0;
uniform float dim = 0.0;        // 0..1 置灰（空槽里的幽灵牌）
uniform float flash = 0.0;      // 0..1 白闪
uniform float sheen_speed = 1.0;

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

vec3 grade_tint(int g) {
	if (g == 1) return vec3(0.62, 0.90, 0.78);
	if (g == 2) return vec3(0.74, 0.56, 0.95);
	if (g == 3) return vec3(1.00, 0.80, 0.34);
	return vec3(0.93, 0.96, 1.00);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 col = c.rgb;
	float mx = max(col.r, max(col.g, col.b));
	float mn = min(col.r, min(col.g, col.b));
	// 象牙底：亮且低饱和；墨色图案保持不变
	float ivory = smoothstep(0.55, 0.80, mx) * (1.0 - smoothstep(0.12, 0.34, mx - mn));

	if (grade > 0) {
		vec3 tint = grade_tint(grade);
		vec3 body = col * tint;
		// 晶面：斜向折线形成切面明暗
		// 柔和的斜向明暗起伏（不用硬边切面，避免出现棋盘格）
		float facet = 0.5 + 0.25 * sin((UV.x + UV.y * 0.8) * 7.0) + 0.25 * sin((UV.x - UV.y * 1.2) * 5.0 + 1.3);
		float facet_amt = grade == 3 ? 0.10 : 0.16;
		body *= 1.0 - facet_amt + facet * facet_amt * 2.0;
		if (grade == 4) {
			// 钻石：随时间流动的彩虹折射
			float h = UV.x * 2.2 + UV.y * 1.6 + TIME * 0.35;
			vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
			body = mix(body, body * (0.72 + 0.5 * rainbow), 0.55);
		}
		col = mix(col, body, ivory * 0.92);
		// 扫光
		float period = grade == 4 ? 1.8 : 2.8;
		float t = fract(TIME * sheen_speed / period) * 2.4 - 0.7;
		float band = smoothstep(0.16, 0.0, abs((UV.x + UV.y * 0.6) * 0.62 - t));
		col += band * (grade == 4 ? 0.50 : 0.30) * tint;
	}

	if (dim > 0.0) {
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(l) * vec3(0.50, 0.52, 0.48), dim);
		c.a *= mix(1.0, 0.62, dim);
	}
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, c.a) * modulate;
}
