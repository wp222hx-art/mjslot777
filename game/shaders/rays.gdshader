shader_type canvas_item;
// 旋转光芒：黄金牌用金色，钻石局命中用彩虹。

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float rainbow = 0.0;
uniform float strength = 1.0;
uniform float speed = 0.35;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x) + TIME * speed;
	float rays = pow(0.5 + 0.5 * sin(a * 14.0), 3.0) * 0.75 + pow(0.5 + 0.5 * sin(a * 9.0 - TIME * speed * 2.0), 2.0) * 0.4;
	float fall = smoothstep(1.0, 0.08, r);
	float core = smoothstep(0.55, 0.0, r);
	vec3 col = tint.rgb;
	if (rainbow > 0.0) {
		vec3 rb = 0.5 + 0.5 * cos(a * 2.0 + vec3(0.0, 2.094, 4.188));
		col = mix(col, rb, rainbow * 0.8);
	}
	float alpha = clamp((rays * fall + core * 0.7) * strength, 0.0, 1.0);
	COLOR = vec4(col + vec3(core * 0.5), alpha * tint.a);
}
