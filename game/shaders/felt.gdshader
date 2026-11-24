shader_type canvas_item;
// 墨绿绒面桌布 + 暗角 + 左上灯笼暖光。

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 base = mix(vec3(0.050, 0.170, 0.130), vec3(0.085, 0.260, 0.195), noise(uv * vec2(6.0, 10.0)));
	float grain = hash(floor(uv * vec2(540.0, 960.0)));
	base += (grain - 0.5) * 0.030;
	// 暗角
	vec2 d = uv - vec2(0.5);
	base *= 1.0 - dot(d, d) * 1.15;
	// 灯笼暖光，轻微摇曳
	float flick = 0.92 + 0.08 * sin(TIME * 2.3) * sin(TIME * 1.1 + 1.7);
	float lamp = exp(-distance(uv * vec2(1.0, 1.78), vec2(0.04, 0.05)) * 2.6) * flick;
	base += vec3(0.95, 0.62, 0.25) * lamp * 0.42;
	COLOR = vec4(base, 1.0);
}
