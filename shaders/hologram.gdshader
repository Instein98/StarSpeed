shader_type canvas_item;
// 小地图的全息质感（规格 5.6）：加色叠加、每 3 像素一条扫描线（−30%）、
// 8 Hz ±5% 闪动、1 像素同色 40% 光晕、上窄下宽的梯形（顶边为底边的 80%）。
render_mode blend_add;

uniform float game_time = 0.0;   // 由脚本传入，暂停时冻结
uniform vec2 tex_size = vec2(220.0, 115.0);

void fragment() {
	float width = mix(0.8, 1.0, UV.y);
	vec2 uv = vec2((UV.x - 0.5) / width + 0.5, UV.y);
	vec3 col = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0) {
		vec2 px = 1.0 / tex_size;
		col = texture(TEXTURE, uv).rgb;
		vec3 glow = max(
			max(texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb, texture(TEXTURE, uv - vec2(px.x, 0.0)).rgb),
			max(texture(TEXTURE, uv + vec2(0.0, px.y)).rgb, texture(TEXTURE, uv - vec2(0.0, px.y)).rgb));
		col = max(col, glow * 0.4);
		if (int(floor(uv.y * tex_size.y)) % 3 == 0) {
			col *= 0.7;
		}
		col *= 1.0 + 0.05 * sin(game_time * TAU * 8.0);
	}
	COLOR = vec4(col, 1.0);
}
