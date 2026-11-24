shader_type canvas_item;
// 奖励数字 / 牌型标题的鎏金渐变字：上亮下深，中线高光，一道扫光循环划过。
// 用法：字色设为纯白，描边与阴影设为深色；只有白色的字面会被染成金色。

uniform float height = 100.0;
uniform vec4 top : source_color = vec4(1.0, 0.98, 0.78, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.80, 0.26, 1.0);
uniform vec4 bottom : source_color = vec4(0.88, 0.46, 0.08, 1.0);
uniform float shine_speed = 0.55;

varying float vy;
varying float vx;
varying vec4 vcol;

void vertex() {
	vy = clamp(VERTEX.y / height, 0.0, 1.0);
	vx = VERTEX.x;
	vcol = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float fill = step(0.9, vcol.r) * step(0.9, vcol.g) * step(0.9, vcol.b);
	vec3 g = vy < 0.5 ? mix(top.rgb, mid.rgb, vy * 2.0) : mix(mid.rgb, bottom.rgb, (vy - 0.5) * 2.0);
	g += 0.22 * smoothstep(0.07, 0.0, abs(vy - 0.47));
	float sweep = (fract(TIME * shine_speed) * 2.0 - 0.5) * 1500.0;
	g += 0.55 * smoothstep(70.0, 0.0, abs(vx - vy * 50.0 - sweep));
	COLOR = vec4(mix(vcol.rgb, g, fill), vcol.a * tex.a);
}
