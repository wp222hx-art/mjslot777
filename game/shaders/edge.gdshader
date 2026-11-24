shader_type canvas_item;
// 时刻元素的边缘辉光：元素管时刻（冰=听牌、雷=成牌待胡、火=胡牌）。

uniform vec4 tint : source_color = vec4(0.56, 0.85, 1.0, 1.0);
uniform float strength = 0.0;
uniform float flicker = 0.0;   // 0 平稳（冰），1 强闪烁（雷/火）
uniform float rise = 0.0;      // >0 时辉光自下而上流动（火）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// 以屏幕宽度为单位的到边距离（竖屏 9:16），辉光只贴边、不盖住盘面
	float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y) * 1.778);
	float n = noise(uv * vec2(9.0, 14.0) + vec2(0.0, -TIME * (0.4 + rise * 2.2)));
	float band = 1.0 - smoothstep(0.0, 0.035 + n * 0.045, e);
	float fl = 1.0 - flicker * 0.45 * (0.5 + 0.5 * sin(TIME * 17.0 + n * 6.0)) * step(0.55, noise(vec2(TIME * 6.0, 3.1)));
	float bottom = rise * smoothstep(0.78, 1.0, uv.y) * (0.35 + 0.45 * n);
	float a = clamp((band * 0.75 + bottom) * strength * fl, 0.0, 0.8);
	COLOR = vec4(tint.rgb + vec3(band * 0.2), a * tint.a);
}
